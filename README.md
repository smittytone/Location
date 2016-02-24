# Location

Location is a Squirrel driver class written to provide support for Google’s geolocation API on Electric Imp devices.

It should be inlcuded and instantiated in **both** device code and agent code. The two instances will communicate as required to locate the device based on nearby WiFi networks. This data is sent to Google by the agent instance, which returns the device’s latitude and longitude.

Google’s [geolocation API](https://developers.google.com/maps/documentation/geolocation/intro) controls access through the use of an API key. You must obtain your own API key and pass it into the device and agent instances of the Location class at instantiation.

### Typical Flow

Consider a weather station application. In this case, the agent needs to determine the device’s location in order to pass the co-ordinates to a third-party weather forecast API. The agent therefore initiates the process only when the device has connected:

- Agent calls [the *locate()* function](#locate-useprevious-callback) which messages the device.
- Device gathers all nearby wireless networks and returns this to the agent.
- Agent sends network list to Google’s geolocation API.
- Google returns the determined latitude and longitude.
- Agent asynchronously process the data returned by google.
- Agent stores the location locally and uses it to format the message to be sent to the weather forecast API.
- Agent relays the location to the device.
- Device stores its location locally for future reference.

### Rate Limits

Google rate-limits access to the geolocation API on both a second-by-second and on a day-by-day basis. If you exceed these limits (typically because a great many devices have requested their locations at once, or do so more than once a day), the class will take appropriate behaviour: attempt to reacquire the location at 00:01 the following day (in the case of the 24-hour limit being exceeded) or in ten seconds’ time (momentary rate limit).

Details of the limits Google applies can be found [here](https://developers.google.com/maps/documentation/geolocation/usage-limits).

## Constructor

### Location(*apiKey[, debugFlag]*)

The constructor’s two parameters are your Google geolocation API key (mandatory) and an optional debugging flag. The latter defaults to `false` &mdash; progress reports will not be logged.

### Example

```squirrel
locator = Location("<YOUR_GEOLOCATION_API_KEY>", true);
```

## Public Functions

### locate(*usePrevious[, callback]*)

The *locate()* function triggers an attempt to locate the devce. It may be called by either the agent or device instance. If called by the agent instance, it is recommended that you first check that the device is connected. An optional callback function may be passed if your application needs to be notified when the location has been determined (or not).

### getLocation()

The *getLocation()* function returns a table with *either* the keys *latitude* and *longitude*, *or* the key *err*. The first two of these keys’ values will be the device’s co-ordinates as determined by the geolocation API. The *err* key is *only* present when an error has taken place, and so should be used as an error check.

### Example

```squirrel
locale = locator.getLocation();
if (!("err" in locale)) {
    server.log("Location: " + locale.longitude + ", " + locale.latitude);
} else {
    server.error(locale.err);
}
```
