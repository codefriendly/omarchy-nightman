var FALLBACK_SUNRISE_MINUTES = 7 * 60
var FALLBACK_SUNSET_MINUTES = 19 * 60

function trim(value) {
  return String(value === undefined || value === null ? "" : value).replace(/^\s+|\s+$/g, "")
}

function parseGsettingsOutput(output) {
  var value = trim(output).replace(/^['"]|['"]$/g, "")
  return value === "prefer-light" || value === "prefer-dark" ? value : ""
}

function parseDate(value) {
  if (typeof value === "number" && isFinite(value)) return new Date(value * 1000)
  if (typeof value !== "string" || value === "") return null
  var date = new Date(value)
  return isNaN(date.getTime()) ? null : date
}

function validCoordinates(latitude, longitude) {
  var lat = Number(latitude)
  var lon = Number(longitude)
  return isFinite(lat) && isFinite(lon) && lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180
}

function parseLocationResponse(raw) {
  try {
    var data = JSON.parse(String(raw || "{}"))
    var latitude = Number(data.latitude)
    var longitude = Number(data.longitude)
    if (!validCoordinates(latitude, longitude)) return null
    return {
      latitude: latitude,
      longitude: longitude,
      name: trim(data.city || data.region || data.country_name || data.country || "")
    }
  } catch (e) {
    return null
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
    var location = data.location
    var schedule = data.schedule
    if (!location || !validCoordinates(location.latitude, location.longitude)) return null
    if (!schedule || !Array.isArray(schedule.days)) return null
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
      location: { latitude: Number(location.latitude), longitude: Number(location.longitude), name: trim(location.name) },
      schedule: parsedSchedule
    }
  } catch (e) {
    return null
  }
}

function localDayKey(date) {
  function pad(value) { return value < 10 ? "0" + value : String(value) }
  return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function scheduleState(schedule, now) {
  var date = now instanceof Date ? now : new Date(now)
  if (isNaN(date.getTime())) date = new Date()
  var nowMs = date.getTime()
  var previousSunset = null
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
    if (sunset.getTime() <= nowMs && (!previousSunset || sunset.getTime() > previousSunset.getTime())) previousSunset = sunset
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
  var sunrise = isFinite(Number(sunriseMinutes)) ? Number(sunriseMinutes) : FALLBACK_SUNRISE_MINUTES
  var sunset = isFinite(Number(sunsetMinutes)) ? Number(sunsetMinutes) : FALLBACK_SUNSET_MINUTES
  var minute = date.getHours() * 60 + date.getMinutes()
  var light = minute >= sunrise && minute < sunset
  var next = new Date(date.getTime())
  next.setSeconds(0, 0)
  if (light) {
    next.setHours(Math.floor(sunset / 60), sunset % 60, 0, 0)
  } else if (minute < sunrise) {
    next.setHours(Math.floor(sunrise / 60), sunrise % 60, 0, 0)
  } else {
    next.setDate(next.getDate() + 1)
    next.setHours(Math.floor(sunrise / 60), sunrise % 60, 0, 0)
  }
  return {
    mode: light ? "light" : "dark",
    source: "fixed-time",
    nextTransition: next.toISOString()
  }
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

function stateAt(schedule, now) {
  var calculated = scheduleState(schedule, now)
  return calculated.source === "sun" ? calculated : fallbackState(now)
}

function modeToPreference(mode) {
  return mode === "light" ? "prefer-light" : "prefer-dark"
}

if (typeof module !== "undefined") {
  module.exports = {
    FALLBACK_SUNRISE_MINUTES: FALLBACK_SUNRISE_MINUTES,
    FALLBACK_SUNSET_MINUTES: FALLBACK_SUNSET_MINUTES,
    parseGsettingsOutput: parseGsettingsOutput,
    validCoordinates: validCoordinates,
    parseLocationResponse: parseLocationResponse,
    parseForecastResponse: parseForecastResponse,
    parseCache: parseCache,
    scheduleState: scheduleState,
    fallbackState: fallbackState,
    parseOverride: parseOverride,
    overrideExpired: overrideExpired,
    shouldExpireOverride: shouldExpireOverride,
    pendingPreference: pendingPreference,
    retryDelay: retryDelay,
    stateAt: stateAt,
    modeToPreference: modeToPreference
  }
}
