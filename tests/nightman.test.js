const assert = require("assert")
const NightMan = require("../NightMan.js")

function iso(value) { return new Date(value).toISOString() }

assert.strictEqual(NightMan.parseGsettingsOutput("'prefer-dark'\n"), "prefer-dark")
assert.strictEqual(NightMan.parseGsettingsOutput("default"), "")
assert.strictEqual(NightMan.modeToPreference("light"), "prefer-light")
assert.strictEqual(NightMan.modeToPreference("dark"), "prefer-dark")

assert.strictEqual(NightMan.validTime("00:00"), true)
assert.strictEqual(NightMan.validTime("23:59"), true)
assert.strictEqual(NightMan.validTime("24:00"), false)
assert.strictEqual(NightMan.validTime("7:00"), false)
assert.strictEqual(NightMan.timeToMinutes("19:30"), 1170)
assert.deepStrictEqual(NightMan.normalizedFixedTimes(" 07:00 ", "19:00 "), { dayStart: "07:00", nightStart: "19:00" })
assert.strictEqual(NightMan.normalizedFixedTimes(" 07:00 ", "07:00"), null)
assert.deepStrictEqual(NightMan.parseSettings('{"scheduleMode":"fixed","dayStart":"08:15","nightStart":"20:45"}'), {
  scheduleMode: "fixed", dayStart: "08:15", nightStart: "20:45", location: null
})
assert.strictEqual(NightMan.parseSettings('{"scheduleMode":"location","location":{"latitude":999,"longitude":0}}').scheduleMode, "automatic")
assert.deepStrictEqual(NightMan.parseSettings('{"scheduleMode":"fixed","dayStart":"08:00","nightStart":"08:00"}'), {
  scheduleMode: "fixed", dayStart: "07:00", nightStart: "19:00", location: null
})

assert.deepStrictEqual(NightMan.parseLocationResponse('{"latitude":40.7,"longitude":-74,"city":"New York"}'), {
  latitude: 40.7, longitude: -74, name: "New York"
})
assert.strictEqual(NightMan.parseLocationResponse('{"latitude":999,"longitude":0}'), null)
assert.strictEqual(NightMan.validCoordinates(null, 0), false)
assert.strictEqual(NightMan.validCoordinates("", 0), false)
assert.strictEqual(NightMan.validCoordinates(false, 0), false)
assert.deepStrictEqual(NightMan.parseWeatherLocation('{"name":"Oslo","latitude":59.9,"longitude":10.7}'), {
  latitude: 59.9, longitude: 10.7, name: "Oslo"
})
assert.strictEqual(NightMan.parseWeatherLocation('{"latitude":"nan","longitude":10}'), null)
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
