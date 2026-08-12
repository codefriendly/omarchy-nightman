import QtQuick
import Quickshell
import Quickshell.Io
import "NightMan.js" as NightMan

Item {
  id: root

  property var shell: null
  property var schedule: null
  property var location: null
  property string locationSource: "fallback"
  property var config: NightMan.normalizeSettings(null)
  property string mode: ""
  property string scheduledMode: ""
  property string scheduleSource: "fixed-time"
  property string nextTransition: ""
  property bool overrideActive: false
  property string overrideMode: ""
  property string overrideExpiresAt: ""
  property string currentPreference: ""
  property string lastError: ""
  property bool initialized: false
  property bool cacheLoaded: false
  property bool overrideLoaded: false
  property bool settingsLoaded: false
  property bool stateLoadStarted: false
  property string pendingPreference: ""
  property string activePreference: ""
  property int networkRetryCount: 0
  property string networkRetryAction: ""
  property string pendingSettingsText: ""
  property string settingsLastWritten: ""
  property string pendingCacheRaw: ""

  readonly property int maximumNetworkRetries: 3
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/nightman"
  readonly property string cachePath: stateDir + "/schedule.json"
  readonly property string overridePath: stateDir + "/override.json"
  readonly property string settingsPath: stateDir + "/settings.json"
  readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
  readonly property string activeLocationName: root.location ? (root.location.name || root.location.latitude + ", " + root.location.longitude) : "Fallback"

  function now() { return new Date() }

  function statusObject() {
    return {
      mode: root.mode,
      preference: NightMan.modeToPreference(root.mode),
      scheduledMode: root.scheduledMode,
      override: root.overrideActive,
      source: root.scheduleSource,
      scheduleBehavior: root.config.scheduleMode,
      nextTransition: root.nextTransition,
      location: root.activeLocationName,
      locationSource: root.locationSource,
      settings: root.config,
      lastError: root.lastError
    }
  }

  function calculatedState() {
    return NightMan.settingsState(root.schedule, root.config, root.now())
  }

  function evaluate() {
    var currentTime = root.now()
    var calculated = NightMan.settingsState(root.schedule, root.config, currentTime)
    root.scheduledMode = calculated.mode
    root.scheduleSource = calculated.source
    root.nextTransition = calculated.nextTransition

    if (root.overrideActive && NightMan.shouldExpireOverride(
        root.cacheLoaded && root.settingsLoaded, root.overrideLoaded, root.overrideExpiresAt, currentTime)) clearOverride(false)
    applyMode(root.overrideActive ? root.overrideMode : calculated.mode)
  }

  function scheduleStillUsable(nowDate) {
    return root.config.scheduleMode !== "fixed" && NightMan.scheduleState(root.schedule, nowDate).source === "sun"
  }

  function applyMode(value) {
    if (value !== "light" && value !== "dark") return
    root.mode = value
    if (!root.initialized || !root.cacheLoaded || !root.overrideLoaded || !root.settingsLoaded) return
    var preference = NightMan.modeToPreference(value)
    if (root.currentPreference === preference && !setPreferenceProc.running) return
    if (setPreferenceProc.running) {
      root.pendingPreference = NightMan.pendingPreference(root.activePreference, preference)
      return
    }
    startPreferenceWrite(preference)
  }

  function startPreferenceWrite(preference) {
    root.activePreference = preference
    root.pendingPreference = ""
    setPreferenceProc.command = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", preference]
    setPreferenceProc.running = true
  }

  function setManual(value) {
    if (value !== "light" && value !== "dark") return "invalid"
    if (root.overrideActive && root.overrideMode === value && !NightMan.overrideExpired(root.overrideExpiresAt, root.now())) {
      applyMode(value)
      return value
    }
    var calculated = calculatedState()
    root.overrideActive = true
    root.overrideMode = value
    root.overrideExpiresAt = calculated.nextTransition
    overrideFile.setText(JSON.stringify({ mode: value, expiresAt: root.overrideExpiresAt }, null, 2) + "\n")
    applyMode(value)
    return value
  }

  function toggleManual() {
    var current = root.mode || calculatedState().mode
    return setManual(current === "light" ? "dark" : "light")
  }

  function clearOverride(applyImmediately) {
    var changed = root.overrideActive || root.overrideMode !== "" || root.overrideExpiresAt !== ""
    root.overrideActive = false
    root.overrideMode = ""
    root.overrideExpiresAt = ""
    if (changed) overrideFile.setText("{}\n")
    if (applyImmediately !== false) evaluate()
  }

  function loadOverride(raw) {
    if (!root.stateLoadStarted) return
    var saved = NightMan.parseOverride(raw)
    root.overrideActive = !!saved
    root.overrideMode = saved ? saved.mode : ""
    root.overrideExpiresAt = saved ? saved.expiresAt : ""
    root.overrideLoaded = true
    evaluate()
  }

  function loadSettings(raw) {
    if (!root.stateLoadStarted) return
    var text = String(raw || "")
    if (root.pendingSettingsText !== "" && text === root.pendingSettingsText) root.pendingSettingsText = ""
    var firstLoad = !root.settingsLoaded
    var previous = root.config
    var loaded = NightMan.parseSettings(text)
    root.config = loaded
    root.settingsLastWritten = JSON.stringify(loaded, null, 2) + "\n"
    root.settingsLoaded = true
    var scheduleChanged = NightMan.scheduleSettingsChanged(previous, loaded)
    if (!firstLoad && scheduleChanged) {
      root.clearOverride(false)
      root.location = loaded.scheduleMode === "location" ? loaded.location : null
      root.locationSource = loaded.scheduleMode === "location" ? "explicit" : (loaded.scheduleMode === "fixed" ? "fixed" : "fallback")
      root.schedule = null
    }
    if (root.pendingCacheRaw !== "") {
      var cachedRaw = root.pendingCacheRaw
      root.pendingCacheRaw = ""
      root.finishCacheLoad(cachedRaw)
    } else {
      root.evaluate()
      root.refreshSchedule()
    }
  }

  function updateSettings(next) {
    var normalized = NightMan.normalizeSettings(next)
    var text = JSON.stringify(normalized, null, 2) + "\n"
    if (text === root.settingsLastWritten) return true
    if (NightMan.scheduleSettingsChanged(root.config, normalized)) root.clearOverride(false)
    root.config = normalized
    root.settingsLastWritten = text
    root.pendingSettingsText = text
    settingsFile.setText(text)
    root.location = normalized.scheduleMode === "location" ? normalized.location : null
    root.locationSource = normalized.scheduleMode === "location" ? "explicit" : (normalized.scheduleMode === "fixed" ? "fixed" : "fallback")
    root.schedule = null
    root.evaluate()
    root.refreshSchedule()
    return true
  }

  function setScheduleBehavior(value) {
    if (value !== "automatic" && value !== "location" && value !== "fixed") return false
    if (value === "location" && !root.config.location) return false
    return updateSettings({
      scheduleMode: value,
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: root.config.location
    })
  }

  function setFixedTimes(dayStart, nightStart) {
    var times = NightMan.normalizedFixedTimes(dayStart, nightStart)
    if (!times) return false
    return updateSettings({ scheduleMode: "fixed", dayStart: times.dayStart, nightStart: times.nightStart, location: root.config.location })
  }

  function setExplicitLocation(value) {
    var locationValue = NightMan.normalizedLocation(value)
    if (!locationValue) return false
    return updateSettings({
      scheduleMode: "location",
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: locationValue
    })
  }

  function clearExplicitLocation() {
    return updateSettings({
      scheduleMode: "automatic",
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: null
    })
  }

  function finishCacheLoad(raw) {
    if (!root.stateLoadStarted) return
    if (!root.settingsLoaded) {
      root.pendingCacheRaw = String(raw || "{}")
      return
    }
    var cache = NightMan.parseCache(raw)
    if (cache && root.config.scheduleMode !== "fixed") {
      var expected = root.config.scheduleMode === "location" ? root.config.location : null
      if (!expected || NightMan.sameLocation(cache.location, expected)) {
        root.location = cache.location
        root.locationSource = cache.locationSource || (root.config.scheduleMode === "location" ? "explicit" : "cache")
        root.schedule = cache.schedule
      }
    }
    root.cacheLoaded = true
    evaluate()
    maybeStartNetwork()
  }

  function saveCache() {
    if (!root.location || !root.schedule) return
    cacheFile.setText(JSON.stringify({ location: root.location, locationSource: root.locationSource, schedule: root.schedule }, null, 2) + "\n")
  }

  function maybeStartNetwork() {
    if (!root.stateLoadStarted || !root.cacheLoaded || !root.settingsLoaded || locationProc.running || forecastProc.running) return
    if (root.config.scheduleMode === "fixed") {
      root.location = null
      root.locationSource = "fixed"
      root.evaluate()
      return
    }
    if (root.config.scheduleMode === "location") {
      root.location = root.config.location
      root.locationSource = "explicit"
      fetchForecast()
      return
    }
    weatherLocationReloadTimer.restart()
  }

  function useAutomaticCandidate(weatherRaw) {
    if (root.config.scheduleMode !== "automatic") return
    var weather = NightMan.parseWeatherLocation(weatherRaw)
    if (weather) {
      root.location = weather
      root.locationSource = "weather"
      fetchForecast()
    } else if (!locationProc.running) {
      locationProc.running = true
    }
  }

  function refreshSchedule() {
    root.networkRetryCount = 0
    root.networkRetryAction = ""
    networkRetryTimer.stop()
    root.maybeStartNetwork()
  }

  function scheduleNetworkRetry(action) {
    var delay = NightMan.retryDelay(root.networkRetryCount, root.maximumNetworkRetries)
    if (delay < 0) return
    root.networkRetryCount += 1
    root.networkRetryAction = action
    networkRetryTimer.interval = delay
    networkRetryTimer.restart()
  }

  function handleNetworkFailure(message, action) {
    if (!root.scheduleStillUsable(root.now())) {
      root.schedule = null
      root.lastError = message
      root.evaluate()
    }
    root.scheduleNetworkRetry(action)
  }

  function fetchForecast() {
    if (!root.location || forecastProc.running || root.config.scheduleMode === "fixed") return
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(root.location.latitude))
      + "&longitude=" + encodeURIComponent(String(root.location.longitude))
      + "&daily=sunrise,sunset&forecast_days=7&timeformat=unixtime&timezone=auto"
    forecastProc.command = ["curl", "-fsS", "--max-time", "8", url]
    forecastProc.running = true
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
  }

  FileView {
    id: weatherLocationFile
    path: root.weatherLocationPath
    watchChanges: true
    printErrors: false
    onFileChanged: if (root.config.scheduleMode === "automatic") reload()
    onLoaded: root.useAutomaticCandidate(text())
    onLoadFailed: root.useAutomaticCandidate("")
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.finishCacheLoad(text())
    onLoadFailed: root.finishCacheLoad("")
  }

  FileView {
    id: overrideFile
    path: root.overridePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadOverride(text())
    onLoadFailed: root.loadOverride("")
  }

  Process {
    id: ensureDirProc
    command: ["install", "-d", "-m", "0700", root.stateDir]
    onExited: function(exitCode) {
      root.stateLoadStarted = true
      if (exitCode !== 0) root.lastError = "Unable to create NightMan state directory"
      settingsFile.reload()
      cacheFile.reload()
      overrideFile.reload()
    }
  }

  Process {
    id: preferenceProbe
    command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.currentPreference = NightMan.parseGsettingsOutput(text) }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "Unable to read org.gnome.desktop.interface color-scheme"
      root.initialized = true
      root.evaluate()
    }
  }

  Process {
    id: setPreferenceProc
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.currentPreference = root.activePreference
        root.lastError = ""
      } else root.lastError = "Unable to set org.gnome.desktop.interface color-scheme"
      root.activePreference = ""
      root.pendingPreference = ""
      Qt.callLater(function() {
        var desired = NightMan.modeToPreference(root.mode)
        if (!setPreferenceProc.running && desired !== root.currentPreference) root.startPreferenceWrite(desired)
      })
    }
  }

  Process {
    id: locationProc
    property bool responseAccepted: false
    property bool superseded: false
    command: ["curl", "-fsS", "--max-time", "6", "https://ipapi.co/json/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightMan.parseLocationResponse(text)
        locationProc.superseded = root.config.scheduleMode !== "automatic"
        locationProc.responseAccepted = parsed !== null && !locationProc.superseded
        if (locationProc.responseAccepted) {
          root.location = parsed
          root.locationSource = "ip"
        }
      }
    }
    onRunningChanged: if (running) { responseAccepted = false; superseded = false }
    onExited: function(exitCode) {
      if (superseded) { Qt.callLater(root.maybeStartNetwork); return }
      if (exitCode !== 0 || !responseAccepted) root.handleNetworkFailure("Offline: using configured fixed times", "location")
      else { root.networkRetryCount = 0; root.fetchForecast() }
    }
  }

  Process {
    id: forecastProc
    property bool responseAccepted: false
    property bool superseded: false
    property var requestLocation: null
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightMan.parseForecastResponse(text)
        forecastProc.superseded = root.config.scheduleMode === "fixed" || !NightMan.sameLocation(forecastProc.requestLocation, root.location)
        forecastProc.responseAccepted = parsed !== null && !forecastProc.superseded
        if (forecastProc.responseAccepted) root.schedule = parsed
      }
    }
    onRunningChanged: if (running) { responseAccepted = false; superseded = false; requestLocation = root.location }
    onExited: function(exitCode) {
      if (superseded) { Qt.callLater(root.maybeStartNetwork); return }
      if (exitCode !== 0 || !responseAccepted) root.handleNetworkFailure("Offline: using configured fixed times", "forecast")
      else {
        root.networkRetryCount = 0
        root.networkRetryAction = ""
        networkRetryTimer.stop()
        root.lastError = ""
        root.saveCache()
        root.evaluate()
      }
    }
  }

  Timer {
    id: weatherLocationReloadTimer
    interval: 1500
    repeat: false
    onTriggered: if (root.config.scheduleMode === "automatic") weatherLocationFile.reload()
  }

  Timer {
    id: networkRetryTimer
    repeat: false
    onTriggered: {
      var action = root.networkRetryAction
      root.networkRetryAction = ""
      if (action === "forecast") root.fetchForecast()
      else if (action === "location") root.maybeStartNetwork()
    }
  }

  Timer { interval: 60 * 1000; running: true; repeat: true; onTriggered: root.evaluate() }
  Timer { interval: 5 * 60 * 1000; running: true; repeat: true; onTriggered: if (!preferenceProbe.running && !setPreferenceProc.running) preferenceProbe.running = true }
  Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.refreshSchedule() }

  Component.onCompleted: {
    ensureDirProc.running = true
    preferenceProbe.running = true
  }

  IpcHandler {
    target: "codefriendly.nightman"

    function status(): string { return JSON.stringify(root.statusObject()) }
    function toggle(): string { return root.toggleManual() }
    function light(): string { return root.setManual("light") }
    function dark(): string { return root.setManual("dark") }
    function auto(): string { root.clearOverride(true); return root.scheduledMode }
  }
}
