const assert = require("assert")
const NightMan = require("../NightMan.js")

function iso(value) { return new Date(value).toISOString() }

assert.strictEqual(NightMan.parseGsettingsOutput("'prefer-dark'\n"), "prefer-dark")
assert.strictEqual(NightMan.parseGsettingsOutput("default"), "")
assert.strictEqual(NightMan.modeToPreference("light"), "prefer-light")
assert.strictEqual(NightMan.modeToPreference("dark"), "prefer-dark")

assert.deepStrictEqual(NightMan.parseLocationResponse('{"latitude":40.7,"longitude":-74,"city":"New York"}'), {
  latitude: 40.7,
  longitude: -74,
  name: "New York"
})
assert.strictEqual(NightMan.parseLocationResponse('{"latitude":999,"longitude":0}'), null)

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
assert.strictEqual(state.nextTransition, "")
state = NightMan.stateAt(schedule, new Date(2025, 0, 3, 8, 0, 0))
assert.strictEqual(state.source, "fixed-time")
assert.strictEqual(state.mode, "light")

state = NightMan.fallbackState(new Date(2025, 0, 1, 12, 0, 0))
assert.strictEqual(state.mode, "light")
assert.strictEqual(state.source, "fixed-time")
state = NightMan.fallbackState(new Date(2025, 0, 1, 22, 0, 0))
assert.strictEqual(state.mode, "dark")
assert.strictEqual(state.source, "fixed-time")
assert.ok(state.nextTransition)
state = NightMan.fallbackState(new Date(2025, 0, 2, 2, 0, 0))
assert.ok(state.nextTransition)

const savedOverride = NightMan.parseOverride(JSON.stringify({
  mode: "dark",
  expiresAt: "2025-01-01T19:00:00Z"
}))
assert.deepStrictEqual(savedOverride, { mode: "dark", expiresAt: "2025-01-01T19:00:00.000Z" })
assert.strictEqual(NightMan.parseOverride('{"mode":"dark","transitionKey":"old"}'), null)
assert.strictEqual(NightMan.overrideExpired(savedOverride.expiresAt, new Date("2025-01-01T18:59:59Z")), false)
assert.strictEqual(NightMan.overrideExpired(savedOverride.expiresAt, new Date("2025-01-01T19:00:00Z")), true)
assert.strictEqual(NightMan.shouldExpireOverride(false, true, savedOverride.expiresAt, new Date("2025-01-01T20:00:00Z")), false)
assert.strictEqual(NightMan.shouldExpireOverride(true, false, savedOverride.expiresAt, new Date("2025-01-01T20:00:00Z")), false)
assert.strictEqual(NightMan.shouldExpireOverride(true, true, savedOverride.expiresAt, new Date("2025-01-01T20:00:00Z")), true)

assert.strictEqual(NightMan.pendingPreference("prefer-light", "prefer-dark"), "prefer-dark")
assert.strictEqual(NightMan.pendingPreference("prefer-light", "prefer-light"), "")

assert.strictEqual(NightMan.retryDelay(0, 3), 30000)
assert.strictEqual(NightMan.retryDelay(1, 3), 60000)
assert.strictEqual(NightMan.retryDelay(2, 3), 120000)
assert.strictEqual(NightMan.retryDelay(3, 3), -1)

const cached = NightMan.parseCache(JSON.stringify({
  location: { latitude: 1, longitude: 2, name: "Here" },
  schedule: schedule
}))
assert.strictEqual(cached.location.name, "Here")
assert.strictEqual(cached.schedule.days.length, 2)

console.log("NightMan model tests passed")
