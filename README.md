# Location

Location is a Squirrel driver class written to provide support for Google’s geolocation API on Electric Imp devices.

It should be inlcuded and instantiated in **both** device code and agent code. The two instances will communicate as required to locate the device based on nearby WiFi networks. This data is sent to Google by the agent instance, which returns the device’s latitude and longitude.

Google’s [geolocation API](https://developers.google.com/maps/documentation/geolocation/intro) controls access through the use of an API key. You must obtain your own API key and pass it into the device and agent instances of the Location class at instantiation.

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

The *getLocation()* function returns a table with *either* the keys *latitude* and *longitude*, *or* the key *err*. These keys’ values will be the device’s co-ordinates as determined by the geolocation API.

If an error
