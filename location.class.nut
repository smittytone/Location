class Location {

    // This class is designed to be run on both device *and* agent. It requires
    // a Google Geolocation API key, passed into the constructor, though this is only
    // necessary on the agent. It is designed to be called once during a device's
    // current runtime, in order to determine the device’s latitude and longitude,
    // to pass into a weather forecast service, for example.
    //
    // Copyright Tony Smith, 2016-17

    static version = "1.2.0";

    _lat = 0;
    _long = 0;
    _located = false;
    _locatedTime = null;
    _locating = false;
    _isDevice = false;
    _locatedCallback = null;
    _networks = null;
    _apiKey = null;
    _debug = false;

    // Public functions

    constructor(apiKey = null, debug = false) {
        // The constructor sets nothing but the instance's record of whether it is running
        // on an agent or a device, and then sets the appropriate internal callbacks

        if (typeof debug == "bool") _debug = debug;

        if (imp.environment() == 2) {
            // Code is running on an agent
            _isDevice = false;

            // Check for a value Google Geolocation API key
            if (apiKey == null) {
                server.error("Location class requires a non-null API key. It cannot proceed without one");
                return null;
            } else {
                _apiKey = apiKey;
            }

            // Register handler for when device sends WLAN scan data
            device.on("location.class.internal.setwlans", _loctateFromWLANs.bindenv(this));

            if (_debug) server.log("Location class instantiated on the agent");
        } else {
            // Code is running on a device
            _isDevice = true;

            // Register handler for when agent asks for WiFi scan data
            agent.on("location.class.internal.getwlans", function(dummy) {
                try {
                    imp.scanwifinetworks(function(wlans) {
                        // Scan operates asynchronously
                        _networks = wlans;
                        agent.send("location.class.internal.setwlans", wlans);
                    }.bindenv(this));
                } catch (err) {
                    // Error indicates we're probably running another scan
                    if (_debug) server.log("device.constructor: WiFi scan already in progress");
                }
            });

            // Register handler for when agent sends location data to device
            agent.on("location.class.internal.setloc", _setLocale.bindenv(this));
            if (_debug) server.log("Location class instantiated on the device");
        }
    }

    function locate(usePrevious = true, callback = null) {
        // Triggers an attempt to locate the device. If a callback is passed,
        // it will be called to when the location has been found

        // Already checking? Bail
        if (_locating) return;
        _locating = true;

        if (callback != null) _locatedCallback = callback;

        if (_isDevice == true) {
            // Device first sends the WLAN scan data to the agent
            if (_debug) server.log("Getting WiFi data for the agent");

            if (usePrevious) {
                // User wants to use a previously collected list of WLANs
                if (_networks != null) {
                    // Send the existing list
                    if (_debug) server.log("Sending WiFi data to agent");
                    agent.send("location.class.internal.setwlans", _networks);
                } else {
                    // There is no existing list of WLANs, so get one now
                    try {
                        imp.scanwifinetworks(function(wlans) {
                            // Scan operates asynchronously
                            // Save provided WLAN list
                            _networks = wlans;

                            // Send the list to the agent
                            if (_debug) server.log("Sending WiFi data to agent");
                            agent.send("location.class.internal.setwlans", wlans);
                        }.bindenv(this));
                    } catch (err) {
                        // Error indicates we're probably running another scan
                        if (_debug) server.log("device.locate(): WiFi scan already in progress");
                    }
                }
            } else {
                // User wants to make a fresh WLAN scan
                try {
                    imp.scanwifinetworks(function(wlans) {
                        // Scan operates asynchronously
                        // Save provided WLAN list
                        _networks = wlans;

                        // Send the list to the agent
                        if (_debug) server.log("Sending WiFi data to agent");
                        agent.send("location.class.internal.setwlans", wlans);
                    }.bindenv(this));
                } catch (err) {
                    // Probably running another scan
                    if (_debug) server.log("device.locate(): WiFi scan already in progress");
                }
            }
        } else {
            // Agent asks the device for a WLAN scan
            device.send("location.class.internal.getwlans", true);
            if (_debug) server.log("Requesting WiFi data from device");
        }
    }

    function getLocation() {
        // Returns the location as a table with two keys, longitude and latitude
        // or one key, err, if the instance has not yet got a location (or is getting it)
        local locale = {};
        if (_located == true && _locating == false) {
            locale.longitude <- _long;
            locale.latitude <- _lat;
        } else {
            if (!_located) locale.err <- "Device location not yet obtained or cannot be obtained";
            if (_locating) locale.err <- "Device location not yet obtained. Please try again shortly";
        }
        return locale;
    }

    // ********** Private functions - DO NOT CALL **********

    // AGENT functions

    function _addColons(bssid) {
        // Format a WLAN basestation MAC for transmission to Google
        local result = bssid.slice(0, 2);
        for (local i = 2 ; i < 12 ; i += 2) {
            result = result + ":" + bssid.slice(i, i + 2)
        }
        return result;
    }

    function _loctateFromWLANs(networks = null)
    {
        // This is run *only* on an agent, to process WLAN scan data from the device
        // and send it to Google, which should return a location record
        if (networks) _networks = networks;
        if (networks == null && _networks != null) networks = _networks;

        if (networks == null) {
            // If we have no nearby WLANs and no saved list from a previous scan,
            // we can't proceed, so we need to warn the user
            server.error("Location can find no nearby networks from which the device's location can be determined.");
            _located = false;
            _locating = false;
            return;
        }

        local url = "https://www.googleapis.com/geolocation/v1/geolocate?key=" + _apiKey;
        local header = {"Content-Type" : "application/json"};
        local body = {};
        body.wifiAccessPoints <- [];
        foreach (network in networks) {
            local net = {};
            net.macAddress <- _addColons(network.bssid);
            net.signalStrength <- network.rssi.tostring();
            body.wifiAccessPoints.append(net);
        }

        // Send the WLAN data
        if (_debug) server.log("Requesting location from Google");
        local request = http.post(url, header, http.jsonencode(body));
        request.sendasync(_processLocation.bindenv(this));
    }

    function _processLocation(response) {
        // This is run *only* on an agent, to process data returned by Google
        if (_debug) server.log("Processing data received from Google");
        _locating = false;
        local data = http.jsondecode(response.body);
        if (response.statuscode == 200) {
            if ("location" in data) {
                _lat = data.location.lat;
                _long = data.location.lng;
                _located = true;
                _locatedTime = time();

                // Send the location data to the device
                if (_debug) server.log("Sending location to device");
                device.send("location.class.internal.setloc", data.location);

                // Call the 'device located' callback. This should only be
                // set if the location process was initiated by the agent
                if (_locatedCallback != null) _locatedCallback();
            }
        } else {
            if (_debug) server.log("Google sent error code: " + response.statuscode);
            if (response.statuscode > 499) {
                if (_debug) server.log("Will attempt to acquire location in 60s");
                imp.wakeup(60, _loctateFromWLANs.bindenv(this));
            } else {
                if ("error" in data) _handleError(data.error);
            }
        }
    }

    function _handleError(error) {
        // This is only run on the agent in response to an error condition signalled by Google
        if (error.code == 400) {
            // We can't recover from these errors
            _locating = false;
            if (error.errors[0].reason == "keyInvalid") {
                server.error("Google reports your Location API Key is invalid. Location cannot be determined");
            } else if (error.errors[0].reason == "parseError") {
                sever.error("Request JSON data malformed");
            }
        }

        if (error.code == 403) {
            // These errors are rate-limit related, so we can attempt to get the
            // device's location later on
            if (error.errors[0].reason == "userRateLimitExceeded") {
                // Too many requests issued too quickly - try again in 10s
                server.log(error.message + " - trying again in 10s");
                imp.wakeup(10, _loctateFromWLANs.bindenv(this));
            } else if (error.errors[0].reason == "dailyLimitExceeded") {
                // Too many requests issued today - try again after midnight
                if (_debug) server.log(error.message + " - trying again tomorrow");
                local now = date();
                local delay = (24 - now.hour) * 3600;
                imp.wakeup(delay, _loctateFromWLANs.bindenv(this));
            }
        }
    }

    // DEVICE functions

    function _setLocale(data) {
        // This is run only on a device,
        // in response to location data send by the agent
        _lat = data.lat;
        _long = data.lng;
        _located = true;
        _locating = false;

        // Call the 'device located' callback. This should only be
        // set if the location process was initiated by the device
        if (_locatedCallback != null) _locatedCallback();
    }
}
