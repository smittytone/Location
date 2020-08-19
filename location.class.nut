const LOCATION_CLASS_GEOLOCATION_URL = "https://www.googleapis.com/geolocation/v1/geolocate?key=";
const LOCATION_CLASS_GEOCODE_URL     = "https://maps.googleapis.com/maps/api/geocode/json?";
const LOCATION_CLASS_TIMEZONE_URL    = "https://maps.googleapis.com/maps/api/timezone/json?";

class Location {

    // This class is designed to be run on both device *and* agent. It requires a Google API key,
    // passed into the constructor, though this is only necessary on the agent. The API key should
    // be set to authorize access to the Geolocate, Geocoding and Timezone APIs. At this time, the
    // library does not support the use of multiple API keys.
    // The class instance is designed to be called once during a device's current runtime, in order
    // to determine the device’s latitude and longitude, to pass into a weather forecast service, for example.

    // Copyright Tony Smith, 2020

    static VERSION = "1.5.4";

    // Private properties

    _latitude = 0;
    _longitude = 0;
    _placeData = null;
    _timezoneData = null;
    _locatedCallback = null;
    _keyTable = null;
    _locatedTime = null;
    _networks = null;
    _deviceLogger = null;
    _located = false;
    _locating = false;
    _timezoning = false;
    _isDevice = false;
    _debug = false;

    // ********** Public functions **********

    constructor(googleGeoLocationApiKey = null, debug = false) {
        // The constructor sets nothing but the instance's record of whether it is running
        // on an agent or a device, and then sets the appropriate internal callbacks
        if (typeof debug == "bool") _debug = debug;

        if (imp.environment() == 2) {
            // Code is running on an agent
            _isDevice = false;

            // Check for a value Google Geolocation API key
            if (googleGeoLocationApiKey == null ||
                (typeof googleGeoLocationApiKey != "string" && typeof googleGeoLocationApiKey != "table") ||
                googleGeoLocationApiKey.len() == 0) {
                throw "Location class requires a non-null Google API key as a string, or keys as a table";
            } else {
                if (typeof googleGeoLocationApiKey == "string") {
                    _keyTable = { "GEOLOCATION_API_KEY" : googleGeoLocationApiKey,
                                  "GEOCODING_API_KEY"   : googleGeoLocationApiKey,
                                  "TIMEZONE_API_KEY"    : googleGeoLocationApiKey };
                } else {
                // Check we have all of the three required keys
                    if (!("GEOLOCATION_API_KEY" in googleGeoLocationApiKey &&
                          "GEOCODING_API_KEY" in googleGeoLocationApiKey &&
                          "TIMEZONE_API_KEY" in googleGeoLocationApiKey)) throw "Location class requires an API-key table with three specific slots (see documentation)";

                    // Set the API key table property to the passed in table
                    _keyTable = googleGeoLocationApiKey;

                    // Set the keys to strings
                    foreach (key, value in _keyTable) {
                        if (typeof value != "string") _keyTable[key] = value.tostring();
                    }
                }
            }

            // Register handler for when device sends WLAN scan data
            device.on("location.class.internal.setwlans", _locateFromWLANs.bindenv(this));

            if (_debug) server.log("Location class instantiated on the agent");
        } else {
            // Code is running on a device
            _isDevice = true;

            // Check device supports WiFi
            if (!("scanwifinetworks" in imp)) throw "Location class requires a WiFi-enabled imp";

            // Register handler for when agent asks for WiFi scan data
            agent.on("location.class.internal.getwlans", function(dummy) {
                _locating = true;
                _scan();
            }.bindenv(this));

            // Register handler for when agent sends location data to device
            agent.on("location.class.internal.setloc", _setLocale.bindenv(this));

            // Select logging target, which stored in '_deviceLogger', and will be 'seriallog' if 'seriallog.nut'
            // has been loaded BEFORE Location is instantiated on the device, otherwise it will be the
            // imp API object 'server'
            _deviceLogger = ("seriallog" in getroottable()) ? seriallog : server;
            if (_debug) _deviceLogger.log("Location class instantiated on the device");
        }
    }

    function locate(usePrevious = true, callback = null) {
        // Triggers an attempt to locate the device. If a callback is passed,
        // it will be called if and when the location has been found

        // Already checking for a location? If so, bail
        if (_locating) return;
        _locating = true;

        if (callback != null) _locatedCallback = callback;

        if (_isDevice) {
            // Device first sends the WLAN scan data to the agent
            if (usePrevious && _networks != null) {
                // User wants to use a previously collected list of WLANs;
                // the device has one, so it just sends it back
                if (_debug) _deviceLogger.log("Sending WiFi data to agent");
                agent.send("location.class.internal.setwlans", _networks);
            } else {
                // There is no existing list of WLANs, or a new one is required
                if (_debug) _deviceLogger.log("Getting WiFi data for the agent");
                _scan();
            }
        } else {
            // Does the agent have a list of WLANs it can use?
            if (usePrevious && _networks != null) {
                // Use the existing list of local WLANs
                _locateFromWLANs();
            } else {
                // Agent asks the device for a WLAN scan
                if (_debug) server.log("Requesting WiFi data from device");
                device.send("location.class.internal.getwlans", true);
            }
        }
    }

    function getLocation() {
        // Returns the location as a table with three keys, 'longitude', 'latitude' and 'placeData',
        // or one key, 'error', if the instance has not yet got a location (or is getting it)
        local location = {};

        if (_located && !_locating) {
            location.longitude <- _longitude;
            location.latitude <- _latitude;
            location.placeData <- _placeData;
        } else {
            if (!_located) location.error <- "Device location not yet obtained. Call locate() first";
            if (_locating) location.error <- "Device location still being determined. Please try again shortly";
        }

        return location;
    }

    function getTimezone() {
        // Returns the location as a table with keys, 'dateStr', 'gmtOffsetStr',
        // or one key, 'error', if the instance has not yet got a location (or is getting it)
        local timezone = {};

        if (_timezoneData != null && !_timezoning) {
            timezone = _timezoneData;
        } else {
            if (_timezone == null || _timezone.len() == 0) timezone.error <- "Device timezone not yet obtained or cannot be obtained";
            if (_timezoning) timezone.error <- "Device timezone not yet obtained. Please try again shortly";
        }

        return timezone;
    }

    function setDebug(value = true) {
        if (typeof value != "bool") value = true;
        _debug = value;
    }

    // ********** PRIVATE FUNCTIONS - DO NOT CALL DIRECTLY **********

    // ********** AGENT PRIVATE FUNCTIONS **********

    function _locateFromWLANs(networks = null) {
        // This is run ONLY on an agent, to process WLAN scan data from the device
        // and send it to Google, which should return a location record
        _locating = true;

        if (networks) _networks = networks;
        if (networks == null && _networks != null) networks = _networks;

        if (networks == null) {
            // If we have no nearby WLANs and no saved list from a previous scan,
            // we can't proceed, so we need to warn the user. Note this will be reported
            // to the host app when 'getLocation()' is called
            if (_debug) server.log("There are no nearby networks from which the device's location can be determined.");
            _located = false;
            _locating = false;
            return;
        }

        if (_debug) {
            if (networks.len() == 1) {
                server.log("There is 1 WLAN near the device");
            } else {
                server.log("There are " + networks.len() + " WLANs near the device");
            }
        }

        local url = LOCATION_CLASS_GEOLOCATION_URL + _keyTable.GEOLOCATION_API_KEY;
        local header = {"Content-Type" : "application/json"};
        local body = {};
        body.wifiAccessPoints <- [];
        foreach (network in networks) {
            local net = {};
            net.macAddress <- _addColons(network.bssid);
            net.signalStrength <- network.rssi.tostring();
            body.wifiAccessPoints.append(net);
        }

        // Send the WLAN data to Google
        if (_debug) server.log("Requesting location co-ordinate data from Google");
        local request = http.post(url, header, http.jsonencode(body));
        request.sendasync(_processLocation.bindenv(this));
    }

    function _processLocation(response) {
        // This is run ONLY on an agent, to process data returned by Google
        if (_debug) server.log("Processing location co-ordinate data received from Google");
        local data = null;

        try {
            // Make sure the returned JSON can be decoded
            data = http.jsondecode(response.body);
        } catch (err) {
            // Returned data not JSON?
            if (_debug) server.log("Google returned garbled JSON. Will attempt to re-acquire location in 60s");
            imp.wakeup(60, _locateFromWLANs.bindenv(this));
            return;
        }

        if (response.statuscode == 200) {
            if ("location" in data) {
                // Record the received information
                _latitude = data.location.lat;
                _longitude = data.location.lng;
                _locatedTime = time();

                // Now get the location
                _getPlace();
            }
        } else {
            if (_debug) server.log("Google sent error code: " + response.statuscode);
            if (response.statuscode > 499) {
                if (_debug) server.log("Will attempt to re-acquire location in 60s");
                imp.wakeup(60, _locateFromWLANs.bindenv(this));
            } else {
                if ("error" in data) _handleError(data.error, "Geolocation");
            }
        }
    }

    function _getPlace() {
        // Use the obtained co-ordinates to assemble the place name request
        local url = format("%slatlng=%f,%f&key=%s", LOCATION_CLASS_GEOCODE_URL, _latitude, _longitude, _keyTable.GEOCODING_API_KEY);
        local request = http.get(url);
        if (_debug) server.log("Requesting place name data from Google");
        request.sendasync(_processPlace.bindenv(this));
    }

    function _processPlace(response) {
        // This is run *only* on an agent, to process data returned by Google
        if (_debug) server.log("Processing place name data received from Google");
        local data = null;

        try {
            // Make sure the returned JSON can be decoded
            data = http.jsondecode(response.body);
        } catch (err) {
            // Returned data not JSON?
            if (_debug) server.log("Google returned garbled JSON. Will attempt to re-acquire location in 60s");
            imp.wakeup(60, _getPlace.bindenv(this));
            return;
        }

        if (response.statuscode == 200) {
            _locating = false;
            _located = true;
            if ("results" in data) _placeData = data.results;

            // Get the timezone
            _timezoning = true;
            _getTimezone();
        } else {
            if (_debug) server.log("Google sent error code: " + response.statuscode);
            if (response.statuscode > 499) {
                if (_debug) server.log("Will attempt to re-acquire location in 60s");
                imp.wakeup(60, _getPlace.bindenv(this));
            } else {
                if ("error" in data) _handleError(data.error, "Geocoding");
            }
        }
    }

    function _getTimezone() {
        // Get the device's timezone using the obtained co-ordinates
        local url = format("%slocation=%f,%f&timestamp=%d&key=%s", LOCATION_CLASS_TIMEZONE_URL, _latitude, _longitude, time(), _keyTable.TIMEZONE_API_KEY);
        local request = http.get(url, {});
        if (_debug) server.log("Requesting location timezone data from Google");
        request.sendasync(_processTimezone.bindenv(this));
    }

    function _processTimezone(response) {
        // Process the data returned by Google
        if (_debug) server.log("Processing location timezone data received from Google");
        local data = null;

        try {
            // Make sure the returned JSON can be decoded
            data = http.jsondecode(response.body);
        } catch(err) {
            // Returned data not JSON?
            if (_debug) server.log("Google returned garbled JSON. Will attempt to re-acquire timezone in 60s");
            imp.wakeup(60, _getTimezone.bindenv(this));
            return;
        }

        if (response.statuscode == 200) {
            _timezoning = false;
            _timezoneData = {};

            if ("status" in data) {
                if (data.status == "OK") {
                    // Success
                    local t = time() + data.rawOffset + data.dstOffset;
                    local d = date(t);
                    _timezoneData.time <- t;
                    _timezoneData.date <- d;
                    _timezoneData.dateStr <- format("%04d-%02d-%02d %02d:%02d:%02d", d.year, d.month+1, d.day, d.hour, d.min, d.sec);
                    _timezoneData.gmtOffset <- data.rawOffset + data.dstOffset;
                    _timezoneData.gmtOffsetStr <- format("GMT%s%d", _timezoneData.gmtOffset < 0 ? "-" : "+", math.abs(_timezoneData.gmtOffset / 3600));

                    // Send the location data to the device
                    local sendData = {};
                    sendData.latitude <- _latitude;
                    sendData.longitude <- _longitude;
                    sendData.placeData <- _placeData;
                    sendData.timezoneData <- _timezoneData;

                    device.send("location.class.internal.setloc", sendData);
                    if (_debug) server.log("Location data sent to device");
                }
            }

            // Finally, call the stored 'located' callback
            if (_locatedCallback != null) _locatedCallback();
        } else {
            if (_debug) server.log("Google sent error code: " + response.statuscode);
            if (response.statuscode > 499) {
                if (_debug) server.log("Will attempt to re-acquire timezone in 60s");
                imp.wakeup(60, _getTimezone.bindenv(this));
            } else {
                if ("error" in data) _handleError(data.error, "Timezone");
                _timezoning = false;
            }
        }
    }

    function _handleError(error, api) {
        // This is run *only* on the agent in response to an error condition signalled by Google
        if (error.code == 400) {
            // We can't recover from these errors
            _locating = false;
            if (error.errors[0].reason == "keyInvalid") {
                server.error("Google reports your " + api + " key is invalid.");
            } else if (error.errors[0].reason == "parseError") {
                server.error("Request JSON data malformed");
            } else {
                server.error("Error:" + error.errors[0].reason);
            }
        }

        if (error.code == 403) {
            // These errors are rate-limit related, so we can attempt to get the
            // device's location later on
            if (error.errors[0].reason == "userRateLimitExceeded") {
                // Too many requests issued too quickly - try again in 10s
                server.log(error.message + " - trying again in 10s");
                imp.wakeup(10, _locateFromWLANs.bindenv(this));
            } else if (error.errors[0].reason == "dailyLimitExceeded") {
                // Too many requests issued today - try again after midnight
                if (_debug) server.log(error.message + " - trying again tomorrow");
                local now = date();
                local delay = (24 - now.hour) * 3600;
                imp.wakeup(delay, _locateFromWLANs.bindenv(this));
            }
        }
    }

    function _addColons(bssid) {
        // Format a WLAN basestation MAC for transmission to Google
        local result = bssid.slice(0, 2);
        for (local i = 2 ; i < 12 ; i += 2) {
            result = result + ":" + bssid.slice(i, i + 2)
        }
        return result;
    }

    // ********** DEVICE PRIVATE FUNCTIONS **********

    function _setLocale(data) {
        // This is run *only* on a device in response to location data send by the agent
        if ("latitude" in data) _latitude = data.latitude;
        if ("longitude" in data) _longitude = data.longitude;
        if ("placeData" in data) _placeData = data.placeData;
        if ("timezoneData" in data) _timezoneData = data.timezoneData;

        _located = true;
        _locating = false;
        _timezoning = false;

        // Call the 'device located' callback. This should only be
        // set if the location process was initiated by the device
        if (_locatedCallback != null) _locatedCallback();
    }

    function _scan() {
        // This is run *only* on the device to scan for local WiFi networks
        // If impOS 36 is available, we do this asynchronously
        if (!("scanwifinetworks" in imp)) throw "Location class requires a WiFi-enabled imp";

        if ("info" in imp) {
            // We are on impOS 36 or above, so we can use async scanning
            try {
                imp.scanwifinetworks(function(wlans) {
                    _networks = wlans;
                    if (_debug) _deviceLogger.log("Sending WiFi data to agent");
                    agent.send("location.class.internal.setwlans", wlans);
                }.bindenv(this));
            } catch (err) {
                // Error indicates we're most likely already running a scan
                if (_debug) server.log("Warning: WiFi scan already in progress");
            }
        } else {
            // We are on impOS 34 or less, so use sync scanning
            _networks = imp.scanwifinetworks();
            if (_debug) _deviceLogger.log("Sending WiFi data to agent");
            agent.send("location.class.internal.setwlans", _networks);
        }
    }
}
