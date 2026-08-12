var FALLBACK_SUNRISE_MINUTES = 7 * 60
var FALLBACK_SUNSET_MINUTES = 19 * 60
var DEFAULT_SETTINGS = {
  appearanceMode: "auto",
  scheduleMode: "automatic",
  dayStart: "07:00",
  nightStart: "19:00",
  location: null
}

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function parseGsettingsOutput(output) {
  var value = trim(output)
  var match = value.match(/(?:^|:\s*)['"]?(prefer-light|prefer-dark|default)['"]?$/)
  return match ? match[1] : ""
}

function parseThemeMode(output) {
  var value = trim(output).toLowerCase()
  return value === "light" || value === "dark" ? value : ""
}

function validAppearanceMode(value) {
  return value === "follow" || value === "auto" || value === "day" || value === "night"
}

function preferenceToMode(preference) {
  if (preference === "prefer-dark") return "dark"
  // GNOME's "default" color-scheme has no dark preference, so display it as light.
  if (preference === "prefer-light" || preference === "default") return "light"
  return ""
}

function parseDate(value) {
  if (typeof value === "number" && isFinite(value)) return new Date(value * 1000)
  if (typeof value !== "string" || value === "") return null
  var date = new Date(value)
  return isNaN(date.getTime()) ? null : date
}

function validCoordinateValue(value) {
  if (value === null || value === undefined || typeof value === "boolean") return false
  if (typeof value === "string" && trim(value) === "") return false
  return isFinite(Number(value))
}

function validCoordinates(latitude, longitude) {
  if (!validCoordinateValue(latitude) || !validCoordinateValue(longitude)) return false
  var lat = Number(latitude)
  var lon = Number(longitude)
  return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

function normalizedLocation(value) {
  if (!value || !validCoordinates(value.latitude, value.longitude)) return null
  return {
    latitude: Number(value.latitude),
    longitude: Number(value.longitude),
    name: trim(value.name)
  }
}

function validTime(value) {
  return /^(?:[01][0-9]|2[0-3]):[0-5][0-9]$/.test(trim(value))
}

function timeToMinutes(value) {
  if (!validTime(value)) return null
  var parts = trim(value).split(":")
  return Number(parts[0]) * 60 + Number(parts[1])
}

function normalizedFixedTimes(dayStart, nightStart) {
  var day = trim(dayStart)
  var night = trim(nightStart)
  if (!validTime(day) || !validTime(night) || day === night) return null
  return { dayStart: day, nightStart: night }
}

function normalizeSettings(value) {
  var data = value && typeof value === "object" ? value : {}
  var appearanceMode = validAppearanceMode(data.appearanceMode) ? data.appearanceMode : DEFAULT_SETTINGS.appearanceMode
  var mode = data.scheduleMode
  if (mode !== "automatic" && mode !== "location" && mode !== "fixed") mode = DEFAULT_SETTINGS.scheduleMode
  var dayStart = validTime(data.dayStart) ? trim(data.dayStart) : DEFAULT_SETTINGS.dayStart
  var nightStart = validTime(data.nightStart) ? trim(data.nightStart) : DEFAULT_SETTINGS.nightStart
  if (dayStart === nightStart) {
    dayStart = DEFAULT_SETTINGS.dayStart
    nightStart = DEFAULT_SETTINGS.nightStart
  }
  var location = normalizedLocation(data.location)
  if (mode === "location" && !location) mode = "automatic"
  return {
    appearanceMode: appearanceMode,
    scheduleMode: mode,
    dayStart: dayStart,
    nightStart: nightStart,
    location: location
  }
}

function parseSettings(raw) {
  try {
    return normalizeSettings(JSON.parse(String(raw || "{}")))
  } catch (e) {
    return normalizeSettings(null)
  }
}

function parseLocationResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    return normalizedLocation({
      latitude: data.latitude,
      longitude: data.longitude,
      name: data.city || data.region || data.country_name || data.country || ""
    })
  } catch (e) {
    return null
  }
}

function parseWeatherLocation(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    return normalizedLocation(data)
  } catch (e) {
    return null
  }
}

function parseGeocodingResults(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var results = data.results || []
    var output = []
    for (var i = 0; i < results.length; i++) {
      var item = results[i]
      var location = normalizedLocation(item)
      if (!location || !item.name) continue
      var detail = [item.admin1, item.country].filter(function(part) { return !!part }).join(", ")
      location.name = trim(item.name) + (detail ? ", " + detail : "")
      output.push(location)
    }
    return output
  } catch (e) {
    return []
  }
}

function parseForecastResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var daily = data.daily
    if (!daily || !daily.time || !daily.sunrise || !daily.sunset) return null
    var count = Math.min(daily.time.length, daily.sunrise.length, daily.sunset.length)
    var days = []
    for (var i = 0; i < count; i++) {
      var sunrise = parseDate(daily.sunrise[i])
      var sunset = parseDate(daily.sunset[i])
      if (!sunrise || !sunset || sunrise.getTime() >= sunset.getTime()) continue
      var dayValue = daily.time[i]
      var dayDate = typeof dayValue === "number" ? new Date(dayValue * 1000) : parseDate(String(dayValue) + "T12:00:00")
      days.push({ date: dayDate ? localDayKey(dayDate) : String(dayValue), sunrise: sunrise.toISOString(), sunset: sunset.toISOString() })
    }
    if (days.length === 0) return null
    return { days: days, timezone: trim(data.timezone || "") }
  } catch (e) {
    return null
  }
}

function parseCache(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (!data || typeof data !== "object") return null
    var location = normalizedLocation(data.location)
    var schedule = data.schedule
    if (!location || !schedule || !Array.isArray(schedule.days)) return null
    var parsedSchedule = parseForecastResponse(JSON.stringify({
      daily: {
        time: schedule.days.map(function(day) { return day.date }),
        sunrise: schedule.days.map(function(day) { return day.sunrise }),
        sunset: schedule.days.map(function(day) { return day.sunset })
      },
      timezone: schedule.timezone
    }))
    if (!parsedSchedule) return null
    return {
      location: location,
      locationSource: trim(data.locationSource),
      schedule: parsedSchedule
    }
  } catch (e) {
    return null
  }
}

function sameLocation(first, second) {
  var a = normalizedLocation(first)
  var b = normalizedLocation(second)
  return !!a && !!b && Math.abs(a.latitude - b.latitude) < 0.000001 && Math.abs(a.longitude - b.longitude) < 0.000001
}

function scheduleSettingsChanged(first, second) {
  var a = normalizeSettings(first)
  var b = normalizeSettings(second)
  var locationsMatch = (!a.location && !b.location)
    || (!!a.location && !!b.location && sameLocation(a.location, b.location) && a.location.name === b.location.name)
  return a.scheduleMode !== b.scheduleMode
    || a.dayStart !== b.dayStart
    || a.nightStart !== b.nightStart
    || !locationsMatch
}

function localDayKey(date) {
  function pad(value) { return value < 10 ? "0" + value : String(value) }
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function scheduleState(schedule, now) {
  var date = now instanceof Date ? now : new Date(now)
  if (isNaN(date.getTime())) date = new Date()
  var nowMs = date.getTime()
  var nextTransition = null
  var activeDay = null
  var firstSunrise = null
  var lastSunset = null
  var days = schedule && Array.isArray(schedule.days) ? schedule.days : []

  for (var i = 0; i < days.length; i++) {
    var sunrise = parseDate(days[i].sunrise)
    var sunset = parseDate(days[i].sunset)
    if (!sunrise || !sunset) continue
    if (!firstSunrise || sunrise.getTime() < firstSunrise.getTime()) firstSunrise = sunrise
    if (!lastSunset || sunset.getTime() > lastSunset.getTime()) lastSunset = sunset
    if (sunrise.getTime() <= nowMs && sunset.getTime() > nowMs) activeDay = { sunrise: sunrise, sunset: sunset }
    if (sunrise.getTime() > nowMs && (!nextTransition || sunrise.getTime() < nextTransition.getTime())) nextTransition = sunrise
    if (sunset.getTime() > nowMs && (!nextTransition || sunset.getTime() < nextTransition.getTime())) nextTransition = sunset
  }

  var covered = firstSunrise && lastSunset && nextTransition
    && nowMs >= firstSunrise.getTime() - 24 * 60 * 60 * 1000
    && nowMs <= lastSunset.getTime()
  return {
    mode: activeDay ? "light" : "dark",
    source: covered ? "sun" : "",
    nextTransition: covered ? nextTransition.toISOString() : ""
  }
}

function fallbackState(now, sunriseMinutes, sunsetMinutes) {
  var date = now instanceof Date ? now : new Date(now)
  if (isNaN(date.getTime())) date = new Date()
  var sunrise = isFinite(Number(sunriseMinutes)) ? Math.max(0, Math.min(1439, Number(sunriseMinutes))) : FALLBACK_SUNRISE_MINUTES
  var sunset = isFinite(Number(sunsetMinutes)) ? Math.max(0, Math.min(1439, Number(sunsetMinutes))) : FALLBACK_SUNSET_MINUTES
  if (sunrise === sunset) {
    sunrise = FALLBACK_SUNRISE_MINUTES
    sunset = FALLBACK_SUNSET_MINUTES
  }
  var minute = date.getHours() * 60 + date.getMinutes()
  var light = sunrise < sunset ? minute >= sunrise && minute < sunset : minute >= sunrise || minute < sunset
  var nextMinutes = light ? sunset : sunrise
  var next = new Date(date.getTime())
  next.setSeconds(0, 0)
  next.setHours(Math.floor(nextMinutes / 60), nextMinutes % 60, 0, 0)
  if (next.getTime() <= date.getTime()) next.setDate(next.getDate() + 1)
  return {
    mode: light ? "light" : "dark",
    source: "fixed-time",
    nextTransition: next.toISOString()
  }
}

function settingsState(schedule, settings, now) {
  var normalized = normalizeSettings(settings)
  var dayMinutes = timeToMinutes(normalized.dayStart)
  var nightMinutes = timeToMinutes(normalized.nightStart)
  if (normalized.scheduleMode !== "fixed") {
    var calculated = scheduleState(schedule, now)
    if (calculated.source === "sun") return calculated
  }
  return fallbackState(now, dayMinutes, nightMinutes)
}

function parseOverride(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    if (data.mode !== "light" && data.mode !== "dark") return null
    var expires = parseDate(data.expiresAt)
    if (!expires) return null
    return { mode: data.mode, expiresAt: expires.toISOString() }
  } catch (e) {
    return null
  }
}

function overrideExpired(expiresAt, now) {
  var expiration = parseDate(expiresAt)
  var date = now instanceof Date ? now : new Date(now)
  return !expiration || isNaN(date.getTime()) || date.getTime() >= expiration.getTime()
}

function shouldExpireOverride(cacheLoaded, overrideLoaded, expiresAt, now) {
  return cacheLoaded === true && overrideLoaded === true && overrideExpired(expiresAt, now)
}

function pendingPreference(activePreference, desiredPreference) {
  return activePreference === desiredPreference ? "" : desiredPreference
}

function retryDelay(retriesScheduled, maximumRetries) {
  var attempt = Math.max(0, Math.floor(Number(retriesScheduled) || 0))
  var maximum = Math.max(0, Math.floor(Number(maximumRetries) || 0))
  return attempt >= maximum ? -1 : 30 * 1000 * Math.pow(2, attempt)
}

function preferenceRetryDelay(retriesScheduled, maximumRetries) {
  var attempt = Math.max(0, Math.floor(Number(retriesScheduled) || 0))
  var maximum = Math.max(0, Math.floor(Number(maximumRetries) || 0))
  return attempt >= maximum ? -1 : 250 * Math.pow(2, attempt)
}

function transitionDelay(nextTransition, now) {
  var transition = parseDate(nextTransition)
  var date = now instanceof Date ? now : new Date(now)
  if (!transition || isNaN(date.getTime())) return -1
  return Math.max(1, Math.min(2147483647, transition.getTime() - date.getTime()))
}

function stateAt(schedule, now, dayStart, nightStart, forceFixed) {
  return settingsState(schedule, {
    scheduleMode: forceFixed ? "fixed" : "automatic",
    dayStart: validTime(dayStart) ? dayStart : DEFAULT_SETTINGS.dayStart,
    nightStart: validTime(nightStart) ? nightStart : DEFAULT_SETTINGS.nightStart
  }, now)
}

function modeToPreference(mode) {
  if (mode === "light") return "prefer-light"
  if (mode === "dark") return "prefer-dark"
  return ""
}

function enforcedMode(appearanceMode, scheduledMode, overrideMode) {
  if (appearanceMode === "day") return "light"
  if (appearanceMode === "night") return "dark"
  if (appearanceMode === "auto") return overrideMode === "light" || overrideMode === "dark" ? overrideMode : scheduledMode
  return ""
}

if (typeof module !== "undefined") {
  module.exports = {
    FALLBACK_SUNRISE_MINUTES: FALLBACK_SUNRISE_MINUTES,
    FALLBACK_SUNSET_MINUTES: FALLBACK_SUNSET_MINUTES,
    DEFAULT_SETTINGS: DEFAULT_SETTINGS,
    parseGsettingsOutput: parseGsettingsOutput,
    parseThemeMode: parseThemeMode,
    validAppearanceMode: validAppearanceMode,
    preferenceToMode: preferenceToMode,
    validCoordinates: validCoordinates,
    normalizedLocation: normalizedLocation,
    validTime: validTime,
    timeToMinutes: timeToMinutes,
    normalizedFixedTimes: normalizedFixedTimes,
    normalizeSettings: normalizeSettings,
    parseSettings: parseSettings,
    parseLocationResponse: parseLocationResponse,
    parseWeatherLocation: parseWeatherLocation,
    parseGeocodingResults: parseGeocodingResults,
    parseForecastResponse: parseForecastResponse,
    parseCache: parseCache,
    sameLocation: sameLocation,
    scheduleSettingsChanged: scheduleSettingsChanged,
    scheduleState: scheduleState,
    fallbackState: fallbackState,
    settingsState: settingsState,
    parseOverride: parseOverride,
    overrideExpired: overrideExpired,
    shouldExpireOverride: shouldExpireOverride,
    pendingPreference: pendingPreference,
    retryDelay: retryDelay,
    preferenceRetryDelay: preferenceRetryDelay,
    transitionDelay: transitionDelay,
    stateAt: stateAt,
    modeToPreference: modeToPreference,
    enforcedMode: enforcedMode
  }
}
