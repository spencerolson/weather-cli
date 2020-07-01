# weather-cli

A simple cli for getting the current weather conditions and minutely precipitation data for the next hour.
```
$ weather
⛅ 03:30PM - 04:30PM

82.96° | broken clouds | 48% humidity

```

## Setup
1. Sign up at https://home.openweathermap.org/users/sign_up and generate an API key. Note: it takes some time (took me about an hour) after your key is generated for it to be "activated" for use.
2. Install the httparty gem:
```
gem install httparty
```
3. Get the latitude and longitude of the location you'd like to track weather for. The more precise, the better.
4. Store your API key, latitude, and longitude (I put mine in ~/.bashrc) as OPENWEATHER_API_KEY, MY_HOME_LAT, and MY_HOME_LONG environment variables. Example:
```
export OPENWEATHER_API_KEY='d8z144j92bf2p9f88bv21al08p1b2g00'
export MY_HOME_LAT='31.230234'
export MY_HOME_LONG='-27.193193'
```
5. Add the binary to your PATH or create a soft-link to it from a directory that's already in your path:
```
cd ~/bin
ln -s ~/path/to/weather-cli/weather
```
6. Try `weather` or `weather help`
