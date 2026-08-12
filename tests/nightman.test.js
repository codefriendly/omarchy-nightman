const assert = require("assert")
const NightMan = require("../NightMan.js")

function iso(value) { return new Date(value).toISOString() }

assert.strictEqual(NightMan.parseGsettingsOutput("'prefer-dark'\n"), "prefer-dark")
assert.strictEqual(NightMan.parseGsettingsOutput("color-scheme: 'prefer-light'\n"), "prefer-light")
assert.strictEqual(NightMan.parseGsettingsOutput("default"), "default")
assert.strictEqual(NightMan.parseGsettingsOutput("color-scheme: default"), "default")
assert.strictEqual(NightMan.parseThemeMode(" Light\n"), "light")
assert.strictEqual(NightMan.parseThemeMode("unknown"), "")
assert.strictEqual(NightMan.validAppearanceMode("follow"), true)
assert.strictEqual(NightMan.validAppearanceMode("manual"), false)
assert.strictEqual(NightMan.preferenceToMode("prefer-light"), "light")
assert.strictEqual(NightMan.preferenceToMode("default"), "light")
assert.strictEqual(NightMan.modeToPreference("light"), "prefer-light")
assert.strictEqual(NightMan.modeToPreference("dark"), "prefer-dark")
assert.strictEqual(NightMan.modeToPreference(""), "")
assert.strictEqual(NightMan.enforcedMode("follow", "light", ""), "")
assert.strictEqual(NightMan.enforcedMode("auto", "light", "dark"), "dark")
assert.strictEqual(NightMan.enforcedMode("day", "dark", ""), "light")
assert.strictEqual(NightMan.enforcedMode("night", "light", ""), "dark")

assert.strictEqual(NightMan.validTime("00:00"), true)
assert.strictEqual(NightMan.validTime("23:59"), true)
assert.strictEqual(NightMan.validTime("24:00"), false)
assert.strictEqual(NightMan.validTime("7:00"), false)
assert.strictEqual(NightMan.timeToMinutes("19:30"), 1170)
assert.deepStrictEqual(NightMan.normalizedFixedTimes(" 07:00 ", "19:00 "), { dayStart: "07:00", nightStart: "19:00" })
assert.strictEqual(NightMan.normalizedFixedTimes(" 07:00 ", "07:00"), null)
assert.deepStrictEqual(NightMan.parseSettings('{"scheduleMode":"fixed","dayStart":"08:15","nightStart":"20:45"}'), {
  appearanceMode: "auto", scheduleMode: "fixed", dayStart: "08:15", nightStart: "20:45", location: null
})
assert.strictEqual(NightMan.parseSettings('{"scheduleMode":"location","location":{"latitude":999,"longitude":0}}').scheduleMode, "automatic")
assert.deepStrictEqual(NightMan.parseSettings('{"scheduleMode":"automatic","location":{"latitude":59.9,"longitude":10.7,"name":"Oslo"}}').location, {
  latitude: 59.9, longitude: 10.7, name: "Oslo"
})
assert.deepStrictEqual(NightMan.parseSettings('{"appearanceMode":"day","scheduleMode":"fixed","dayStart":"08:00","nightStart":"08:00"}'), {
  appearanceMode: "day", scheduleMode: "fixed", dayStart: "07:00", nightStart: "19:00", location: null
})
assert.strictEqual(NightMan.parseSettings('{"appearanceMode":"bogus"}').appearanceMode, "auto")
assert.strictEqual(NightMan.parseSettings('{}').appearanceMode, "auto")

assert.deepStrictEqual(NightMan.parseIpWhoResponse('{"success":true,"latitude":30.4,"longitude":-97.6,"city":"Pflugerville","region":"Texas","country":"United States"}'), {
  latitude: 30.4, longitude: -97.6, name: "Pflugerville, Texas, United States"
})
assert.strictEqual(NightMan.parseIpWhoResponse('{"success":false,"message":"Rate limit exceeded"}'), null)
assert.strictEqual(NightMan.validCoordinates(null, 0), false)
assert.strictEqual(NightMan.validCoordinates("", 0), false)
assert.strictEqual(NightMan.validCoordinates(false, 0), false)
assert.deepStrictEqual(NightMan.parseWeatherLocation('{"name":"Oslo","latitude":59.9,"longitude":10.7}'), {
  latitude: 59.9, longitude: 10.7, name: "Oslo"
})
assert.strictEqual(NightMan.parseWeatherLocation('{"latitude":"nan","longitude":10}'), null)
const weatherLocation = { latitude: 1, longitude: 2, name: "Weather" }
const cachedLocation = { latitude: 3, longitude: 4, name: "Cached" }
const savedLocation = { latitude: 5, longitude: 6, name: "Saved" }
assert.deepStrictEqual(NightMan.automaticLocationCandidate(weatherLocation, cachedLocation, savedLocation), {
  location: weatherLocation, source: "weather", shouldCache: true
})
assert.deepStrictEqual(NightMan.automaticLocationCandidate(null, cachedLocation, savedLocation), {
  location: cachedLocation, source: "cache", shouldCache: false
})
assert.deepStrictEqual(NightMan.automaticLocationCandidate(null, null, savedLocation), {
  location: savedLocation, source: "saved", shouldCache: true
})
assert.strictEqual(NightMan.automaticLocationCandidate(null, null, null), null)
assert.deepStrictEqual(NightMan.normalizeSettings({
  scheduleMode: "fixed", dayStart: "08:00", nightStart: "20:00", location: savedLocation
}), {
  appearanceMode: "auto", scheduleMode: "fixed", dayStart: "08:00", nightStart: "20:00", location: savedLocation
})
assert.deepStrictEqual(NightMan.parseGeocodingResults('{"results":[{"name":"Oslo","admin1":"Oslo","country":"Norway","latitude":59.9,"longitude":10.7},{"name":"Bad","latitude":200,"longitude":0}]}'), [
  { latitude: 59.9, longitude: 10.7, name: "Oslo, Oslo, Norway" }
])

const forecast = NightMan.parseForecastResponse(JSON.stringify({
  timezone: "America/New_York",
  daily: {
    time: [1719792000, 1719878400],
    sunrise: [1719828000, 1719914400],
    sunset: [1719871200, 1719957600]
  }
}))
assert.strictEqual(forecast.days.length, 2)
assert.strictEqual(forecast.timezone, "America/New_York")

const schedule = {
  days: [{
    date: "2025-01-01",
    sunrise: iso("2025-01-01T07:00:00Z"),
    sunset: iso("2025-01-01T19:00:00Z")
  }, {
    date: "2025-01-02",
    sunrise: iso("2025-01-02T07:01:00Z"),
    sunset: iso("2025-01-02T19:01:00Z")
  }]
}
let state = NightMan.scheduleState(schedule, new Date("2025-01-01T12:00:00Z"))
assert.strictEqual(state.mode, "light")
assert.strictEqual(state.nextTransition, iso("2025-01-01T19:00:00Z"))
state = NightMan.scheduleState(schedule, new Date("2025-01-01T20:00:00Z"))
assert.strictEqual(state.mode, "dark")
assert.strictEqual(state.nextTransition, iso("2025-01-02T07:01:00Z"))
state = NightMan.scheduleState(schedule, new Date("2025-01-02T20:00:00Z"))
assert.strictEqual(state.source, "")

state = NightMan.settingsState(schedule, { scheduleMode: "automatic", dayStart: "08:00", nightStart: "20:00" }, new Date("2025-01-01T12:00:00Z"))
assert.strictEqual(state.source, "sun")
state = NightMan.settingsState(schedule, { scheduleMode: "fixed", dayStart: "08:00", nightStart: "20:00" }, new Date(2025, 0, 1, 7, 0, 0))
assert.strictEqual(state.mode, "dark")
state = NightMan.settingsState(null, { scheduleMode: "automatic", dayStart: "08:00", nightStart: "20:00" }, new Date(2025, 0, 1, 9, 0, 0))
assert.strictEqual(state.mode, "light")
assert.strictEqual(state.source, "fixed-time")
state = NightMan.fallbackState(new Date(2025, 0, 1, 2, 0, 0), 20 * 60, 6 * 60)
assert.strictEqual(state.mode, "light")
assert.strictEqual(new Date(state.nextTransition).getHours(), 6)
state = NightMan.fallbackState(new Date(2025, 0, 1, 12, 0, 0), 20 * 60, 6 * 60)
assert.strictEqual(state.mode, "dark")
assert.strictEqual(new Date(state.nextTransition).getHours(), 20)

const savedOverride = NightMan.parseOverride(JSON.stringify({ mode: "dark", expiresAt: "2025-01-01T19:00:00Z" }))
assert.deepStrictEqual(savedOverride, { mode: "dark", expiresAt: "2025-01-01T19:00:00.000Z" })
assert.strictEqual(NightMan.overrideExpired(savedOverride.expiresAt, new Date("2025-01-01T18:59:59Z")), false)
assert.strictEqual(NightMan.shouldExpireOverride(true, true, savedOverride.expiresAt, new Date("2025-01-01T20:00:00Z")), true)

assert.strictEqual(NightMan.pendingPreference("prefer-light", "prefer-dark"), "prefer-dark")
assert.strictEqual(NightMan.pendingPreference("prefer-light", "prefer-light"), "")
assert.strictEqual(NightMan.retryDelay(0, 3), 30000)
assert.strictEqual(NightMan.retryDelay(3, 3), -1)
assert.strictEqual(NightMan.preferenceRetryDelay(0, 4), 250)
assert.strictEqual(NightMan.preferenceRetryDelay(3, 4), 2000)
assert.strictEqual(NightMan.preferenceRetryDelay(4, 4), -1)
assert.strictEqual(NightMan.transitionDelay("2025-01-01T07:00:00.000Z", new Date("2025-01-01T06:59:30.000Z")), 30000)
assert.strictEqual(NightMan.transitionDelay("", new Date()), -1)

const cached = NightMan.parseCache(JSON.stringify({
  location: { latitude: 1, longitude: 2, name: "Here" },
  locationSource: "weather",
  schedule: schedule
}))
assert.strictEqual(cached.location.name, "Here")
assert.strictEqual(cached.locationSource, "weather")
assert.strictEqual(cached.schedule.days.length, 2)
assert.strictEqual(NightMan.sameLocation({ latitude: 1, longitude: 2 }, { latitude: "1", longitude: "2" }), true)
assert.strictEqual(NightMan.sameLocation({ latitude: 1, longitude: 2 }, { latitude: 1.1, longitude: 2 }), false)

console.log("NightMan model tests passed")
