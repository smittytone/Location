# Location 1.4.0

Location is a Squirrel class written to provide support for Google’s geolocation API on Electric Imp devices.

It should be included and instantiated in **both** device code and agent code &mdash; use the same code for both. The two instances will communicate as required to locate the device based on nearby WiFi networks. This data is sent to Google by the agent instance, which returns the device’s latitude and longitude.

Google’s [geolocation API](https://developers.google.com/maps/documentation/geolocation/intro) controls access through the use of an API key. You must obtain your own API key and pass it into the device and agent instances of the Location class at instantiation. You will need to enabled these APIs in the [developer console](https://console.developers.google.com/apis).

**Note** Version 1.4.0 adds optional support for Google’s Timezone API.

**Note** Version 1.3.0 adds optional support for Google’s GeoCoding API.

**Note** Version 1.2.0 adds support for impOS&trade; 36’s asynchronous version of *imp.scanwifinetworks()*. This version is compatible with earlier versions of impOS.

### Typical Flow

Consider a weather station application. In this case, the agent needs to determine the device’s location in order to pass the co-ordinates to a third-party weather forecast API. The agent therefore initiates the process *when the device has signalled its readiness*:

1. Device completes start-up and signals the agent.
2. Agent initiates a location, causing it to signal the device to scan for local WiFi networks.
3. Device gathers all nearby wireless networks and sends this to the agent.
4. Agent relays network list to Google’s geolocation API.
5. Google returns the determined latitude and longitude. This takes place asynchronously.
6. Agent process the data returned by google.
7. Agent stores the location locally and uses it to format the message to be sent to the weather forecast API.
8. Agent relays the location to the device.
9. Device stores its location locally for future reference.

#### Device Code

```squirrel
locator <- Location();

if (server.isconnected()) {
    // Signal to the agent that the device is ready to display a forecast
    agent.send("ready", true);
} else {
    // Try to connect to the server
    server.connect(disconnectHandler, 30);
}
```

#### Agent Code

```squirrel
locator <- Location("<YOUR_GEOLOCATION_API_KEY>");

device.on("ready", function(dummy) {
    // The following code runs in response to receipt of 'ready' message from device
    locator.locate(false, function() {
        // Code below called when location is determined (or an error generated)
        local locale = locator.getLocation();
        if ("err" in locale) {
            // Report error
            server.error(locale.err);
        } else {
            // No error, so extract the co-ordinates...
            server.log("Device co-ordinates: " + locale.longitude + ", " + locale.latitude);
            server.log("Device location: " + locale.place);

            // ...and call the weather forecast service
            getWeatherForecast(locale.longitude, locale.latitude);
        }
    });
});
```

### Rate Limits

Google rate-limits access to the geolocation API on both a second-by-second and on a day-by-day basis. If you exceed these limits (typically because a great many devices have requested their locations at once, or do so more than once a day), the class will take appropriate behaviour: attempt to reacquire the location at 00:01 the following day (in the case of the 24-hour limit being exceeded) or in ten seconds’ time (momentary rate limit).

Details of the limits Google applies can be found [here](https://developers.google.com/maps/documentation/geolocation/usage-limits).

## Release Notes

- 1.4.0
    - Add support for Google's Timezone API to optionally determine the timezone in which the device is found.
- 1.3.0
    - Add support for Google's GeoCoding API to optionally reverse geolocate based on co-ordinates.
    - Minor code changes; documentation improvements.
- 1.2.2
    - WiFi scan code refactor to reduce library memory footprint.
- 1.2.1
    - Small code tweaks; clarify that the API key is only needed by the agent constructor.
- 1.2.0
    - Make *imp.scanwifinetworks()* calls asynchronous (requires impOS 36).
    - *locate()* now uses a previously gathered list of WLANs, if present, by default.
- 1.1.1
    - Minor code changes.
- 1.1.0
    - Initial release.

## Constructor

### Location(*googleGeoLocationApiKey[, debugFlag]*)

The constructor’s two parameters are your Google geolocation API key (mandatory on the agent instance; not required for the device instance) and an optional debugging flag. The latter defaults to `false` &mdash; progress reports will not be logged.

The geolocation API key is required by the agent to locate the device by latitude and longitude. If you don’t provide a geolocation API key, the library will throw a warning.

### Example

```squirrel
// Enable debugging
locator = Location("<YOUR_GEOLOCATION_API_KEY>", true);
```

## Public Functions

### locate(*[usePrevious][, callback]*)

The *locate()* function triggers an attempt to locate the device. It may be called by either the agent or device instance. If called by the agent instance, it is recommended that you first check that the device is connected. An optional callback function may be passed if your application needs to be notified when the location has been determined (or not).

The *usePrevious* parameter is also optional: pass `true` to make use of an existing record of nearby WiFi networks, if one is available. This defaults to `true`. If you pass `true` and the device lacks such a list, it will automatically create one.

The *callback* parameter is optional &mdash; use it to call code when the device’s location has been determined. It takes no parameters of its own.

### Example

```squirrel
locator.locate(false, function() {
    locale = locator.getLocation();  // 'locale' is a global table variable
    if ("err" in locale) {
        server.error(locale.err);
    } else {
        server.log("Device co-ordinates: " + locale.longitude + ", " + locale.latitude);
        server.log("Device location: " + locale.place);
    }
});
```

### getLocation()

The *getLocation()* function returns a table with *either* the keys *latitude*, *longitude* and *place*, *or* the key *err*. The first two of these keys’ values will be the device’s co-ordinates as determined by the geolocation API. The *place* key’s value is a human-readable string giving the device’s locale. The *err* key is *only* present when an error has taken place, and so should be used as an error check.

### Example

```squirrel
locale = locator.getLocation();
if ("err" in locale) {
    server.error(locale.err);
} else {
    server.log("Device co-ordinates: " + locale.longitude + ", " + locale.latitude);
    server.log("Device location: " + locale.place);
}
```

## License

The Location class is licensed under the [MIT License](./LICENSE).

Copyright &copy; Tony Smith, 2016-17.
