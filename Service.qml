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
  property string themeMode: ""
  property bool followThemeApplied: false
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
  property string preferenceTarget: ""
  property string verificationPreference: ""
  property bool probeAfterWrite: false
  property bool preferenceRetryExhausted: false
  property int preferenceRetryCount: 0
  property bool themeApplyPending: false

  readonly property int maximumNetworkRetries: 3
  readonly property int maximumPreferenceRetries: 4
  readonly property bool stateReady: root.initialized && root.cacheLoaded && root.overrideLoaded && root.settingsLoaded
  readonly property string appearanceMode: root.config.appearanceMode
  readonly property bool scheduleActive: root.appearanceMode === "auto"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/nightman"
  readonly property string cachePath: stateDir + "/schedule.json"
  readonly property string overridePath: stateDir + "/override.json"
  readonly property string settingsPath: stateDir + "/settings.json"
  readonly property string weatherLocationPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
  readonly property string activeLocationName: root.location ? (root.location.name || root.location.latitude + ", " + root.location.longitude) : "Fallback"

  function now() { return new Date() }

  function statusObject() {
    return {
      appearanceMode: root.appearanceMode,
      mode: root.mode,
      preference: root.currentPreference,
      scheduledMode: root.scheduledMode,
      temporaryOverride: root.overrideActive,
      overrideMode: root.overrideMode,
      overrideExpiresAt: root.overrideExpiresAt,
      source: root.scheduleSource,
      scheduleBehavior: root.config.scheduleMode,
      scheduleActive: root.scheduleActive,
      nextTransition: root.nextTransition,
      location: root.activeLocationName,
      locationSource: root.locationSource,
      settings: root.config,
      ready: root.stateReady,
      lastError: root.lastError
    }
  }

  function desiredMode() {
    return NightMan.enforcedMode(root.appearanceMode, root.scheduledMode, root.overrideActive ? root.overrideMode : "")
  }

  function statusText() {
    if (root.appearanceMode === "follow") return "Following Omarchy theme · " + (root.mode === "light" ? "Light" : "Dark")
    if (root.appearanceMode === "day") return "Day pinned · Light"
    if (root.appearanceMode === "night") return "Night pinned · Dark"
    if (root.overrideActive) return "Temporary " + (root.overrideMode === "light" ? "Day" : "Night") + " · until " + transitionLabel(root.overrideExpiresAt)
    return "Auto · Scheduled " + (root.scheduledMode === "light" ? "Day" : "Night")
  }

  function transitionLabel(value) {
    var date = new Date(value)
    return isNaN(date.getTime()) ? "next transition" : Qt.formatDateTime(date, "ddd h:mm AP")
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
    root.armTransitionTimer()

    if (root.appearanceMode !== "auto" && root.overrideActive) clearOverride(false)
    if (root.appearanceMode === "auto" && root.overrideActive && NightMan.shouldExpireOverride(
        root.cacheLoaded && root.settingsLoaded, root.overrideLoaded, root.overrideExpiresAt, currentTime)) clearOverride(false)

    var desired = root.desiredMode()
    if (desired !== "") applyMode(desired)
    else {
      var observed = NightMan.preferenceToMode(root.currentPreference)
      root.mode = observed || root.themeMode || "light"
      if (root.stateReady && !root.followThemeApplied && !root.themeApplyPending) applyCurrentThemePreference()
    }
  }

  function armTransitionTimer() {
    var delay = NightMan.transitionDelay(root.nextTransition, root.now())
    transitionTimer.stop()
    if (delay > 0) {
      transitionTimer.interval = delay
      transitionTimer.start()
    }
  }

  function scheduleStillUsable(nowDate) {
    return root.config.scheduleMode !== "fixed" && NightMan.scheduleState(root.schedule, nowDate).source === "sun"
  }

  function applyMode(value) {
    if (value !== "light" && value !== "dark") return
    root.mode = value
    if (!root.initialized || !root.cacheLoaded || !root.overrideLoaded || !root.settingsLoaded) return
    requestPreference(NightMan.modeToPreference(value))
  }

  function requestPreference(preference) {
    if (preference !== "prefer-light" && preference !== "prefer-dark" || !root.stateReady) return
    var newTarget = root.preferenceTarget !== preference
    if (newTarget) {
      root.preferenceTarget = preference
      root.preferenceRetryCount = 0
      root.preferenceRetryExhausted = false
      preferenceRetryTimer.stop()
    }
    if (root.currentPreference === preference && !root.probeAfterWrite) {
      root.preferenceTarget = ""
      root.preferenceRetryCount = 0
      root.preferenceRetryExhausted = false
      if (root.appearanceMode === "follow") {
        root.followThemeApplied = true
        root.themeApplyPending = false
      }
      return
    }
    if (root.preferenceRetryExhausted || preferenceRetryTimer.running && !newTarget) return
    if (setPreferenceProc.running || root.probeAfterWrite || preferenceProbe.running) {
      root.pendingPreference = preference === root.activePreference ? "" : preference
      return
    }
    startPreferenceWrite(preference)
  }

  function startPreferenceWrite(preference) {
    if (!root.stateReady || root.preferenceRetryExhausted) return
    root.activePreference = preference
    root.pendingPreference = ""
    setPreferenceProc.command = ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", preference]
    setPreferenceProc.running = true
  }

  function schedulePreferenceRetry(preference) {
    var delay = NightMan.preferenceRetryDelay(root.preferenceRetryCount, root.maximumPreferenceRetries)
    if (delay < 0) {
      root.preferenceRetryExhausted = true
      root.themeApplyPending = false
      root.lastError = "Unable to confirm org.gnome.desktop.interface color-scheme"
      return
    }
    root.preferenceRetryCount += 1
    root.preferenceTarget = preference
    preferenceRetryTimer.interval = delay
    preferenceRetryTimer.restart()
  }

  function probePreference() {
    if (!preferenceProbe.running && !setPreferenceProc.running) preferenceProbe.running = true
  }

  function handlePreferenceProbe(exitCode, observed) {
    var validObservation = exitCode === 0 && observed !== ""
    if (validObservation) root.currentPreference = observed
    else root.lastError = "Unable to read org.gnome.desktop.interface color-scheme"
    root.initialized = true

    if (root.probeAfterWrite) {
      var completed = root.verificationPreference
      var queued = root.pendingPreference
      root.probeAfterWrite = false
      root.verificationPreference = ""
      root.pendingPreference = ""
      if (validObservation && observed === completed) {
        root.preferenceTarget = ""
        root.preferenceRetryCount = 0
        root.preferenceRetryExhausted = false
        root.lastError = ""
        if (root.appearanceMode === "follow" && NightMan.modeToPreference(root.themeMode) === completed) {
          root.followThemeApplied = true
          root.themeApplyPending = false
        }
      } else if (queued === "") {
        root.schedulePreferenceRetry(completed)
      }
      if (queued !== "" && queued !== observed) root.requestPreference(queued)
      else if (root.appearanceMode !== "follow") {
        var desiredAfterProbe = NightMan.modeToPreference(root.desiredMode())
        if (desiredAfterProbe !== "" && desiredAfterProbe !== observed) root.requestPreference(desiredAfterProbe)
      }
    } else {
      // A periodic successful probe is the recovery boundary after a bounded retry sequence.
      if (validObservation && root.preferenceRetryExhausted) {
        root.preferenceTarget = ""
        root.preferenceRetryCount = 0
        root.preferenceRetryExhausted = false
      }
      if (validObservation) root.correctExternalPreference(observed)
      root.evaluate()
    }
  }

  function correctExternalPreference(preference) {
    if (preference === "") return
    root.currentPreference = preference
    if (root.appearanceMode === "follow") {
      root.mode = NightMan.preferenceToMode(preference) || root.mode
      if (root.themeApplyPending && root.themeMode !== "" && preference !== NightMan.modeToPreference(root.themeMode))
        root.requestPreference(NightMan.modeToPreference(root.themeMode))
      return
    }
    var desired = NightMan.modeToPreference(root.desiredMode())
    if (desired !== "" && desired !== preference) root.requestPreference(desired)
  }

  function applyCurrentThemePreference() {
    if (themeModeProc.running || root.themeApplyPending || !root.stateReady) return
    root.themeMode = ""
    root.themeApplyPending = true
    themeModeProc.running = true
  }

  function setManual(value) {
    if (!root.stateReady) return "not ready"
    if (value !== "light" && value !== "dark") return "invalid"
    if (root.appearanceMode !== "auto") return "unavailable outside Auto"
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
    if (!root.stateReady) return "not ready"
    if (root.appearanceMode !== "auto") return "unavailable outside Auto"
    var current = root.mode || calculatedState().mode
    return setManual(current === "light" ? "dark" : "light")
  }

  function setAppearanceMode(value) {
    if (!root.stateReady || !NightMan.validAppearanceMode(value)) return false
    if (value !== root.appearanceMode) {
      // A mode change is a new enforcement intent and may recover immediately after exhaustion.
      root.preferenceTarget = ""
      root.preferenceRetryCount = 0
      root.preferenceRetryExhausted = false
      preferenceRetryTimer.stop()
    }
    if (value === root.appearanceMode) {
      if (value === "follow") { root.followThemeApplied = false; applyCurrentThemePreference() }
      return true
    }
    if (value !== "auto") clearOverride(false)
    var updated = updateSettings({
      appearanceMode: value,
      scheduleMode: root.config.scheduleMode,
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: root.config.location
    })
    if (updated && value === "follow") {
      root.followThemeApplied = false
      applyCurrentThemePreference()
    } else evaluate()
    return updated
  }

  function useOppositeUntilTransition() {
    if (!root.stateReady) return "not ready"
    if (root.appearanceMode !== "auto") return "unavailable outside Auto"
    return setManual(root.scheduledMode === "light" ? "dark" : "light")
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
    if (text !== root.settingsLastWritten) {
      root.pendingSettingsText = root.settingsLastWritten
      settingsFile.setText(root.settingsLastWritten)
    }
    if (loaded.appearanceMode !== "auto" && root.overrideActive) root.clearOverride(false)
    if (firstLoad) root.followThemeApplied = loaded.appearanceMode !== "follow"
    else if (previous.appearanceMode !== loaded.appearanceMode) root.followThemeApplied = loaded.appearanceMode !== "follow"
    var scheduleChanged = NightMan.scheduleSettingsChanged(previous, loaded)
    if (!firstLoad && scheduleChanged) {
      if (loaded.appearanceMode === "auto") root.clearOverride(false)
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
    if (!root.stateReady) return false
    var normalized = NightMan.normalizeSettings(next)
    var text = JSON.stringify(normalized, null, 2) + "\n"
    if (text === root.settingsLastWritten) return true
    var scheduleChanged = NightMan.scheduleSettingsChanged(root.config, normalized)
    if (scheduleChanged && root.appearanceMode === "auto") root.clearOverride(false)
    root.config = normalized
    root.settingsLastWritten = text
    root.pendingSettingsText = text
    settingsFile.setText(text)
    if (scheduleChanged) {
      root.location = normalized.scheduleMode === "location" ? normalized.location : null
      root.locationSource = normalized.scheduleMode === "location" ? "explicit" : (normalized.scheduleMode === "fixed" ? "fixed" : "fallback")
      root.schedule = null
    }
    root.evaluate()
    if (scheduleChanged) root.refreshSchedule()
    return true
  }

  function setScheduleBehavior(value) {
    if (!root.stateReady) return false
    if (value !== "automatic" && value !== "location" && value !== "fixed") return false
    if (value === "location" && !root.config.location) return false
    return updateSettings({
      appearanceMode: root.appearanceMode,
      scheduleMode: value,
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: root.config.location
    })
  }

  function setFixedTimes(dayStart, nightStart) {
    if (!root.stateReady) return false
    var times = NightMan.normalizedFixedTimes(dayStart, nightStart)
    if (!times) return false
    return updateSettings({ appearanceMode: root.appearanceMode, scheduleMode: "fixed", dayStart: times.dayStart, nightStart: times.nightStart, location: root.config.location })
  }

  function setExplicitLocation(value) {
    if (!root.stateReady) return false
    var locationValue = NightMan.normalizedLocation(value)
    if (!locationValue) return false
    return updateSettings({
      appearanceMode: root.appearanceMode,
      scheduleMode: "location",
      dayStart: root.config.dayStart,
      nightStart: root.config.nightStart,
      location: locationValue
    })
  }

  function clearExplicitLocation() {
    if (!root.stateReady) return false
    return updateSettings({
      appearanceMode: root.appearanceMode,
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
    onSaveFailed: function() { root.pendingSettingsText = ""; root.settingsLastWritten = ""; root.lastError = "Unable to save NightMan settings" }
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
    onSaveFailed: function() { root.lastError = "Unable to save NightMan schedule cache" }
  }

  FileView {
    id: overrideFile
    path: root.overridePath
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadOverride(text())
    onLoadFailed: root.loadOverride("")
    onSaveFailed: function() { root.lastError = "Unable to save NightMan temporary override" }
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
    property string observedPreference: ""
    command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: preferenceProbe.observedPreference = NightMan.parseGsettingsOutput(text) }
    onRunningChanged: if (running) observedPreference = ""
    onExited: function(exitCode) { root.handlePreferenceProbe(exitCode, observedPreference) }
  }

  Process {
    id: preferenceMonitor
    command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function(data) {
        var observed = NightMan.parseGsettingsOutput(data)
        if (observed !== "") root.correctExternalPreference(observed)
      }
    }
    onExited: function() { preferenceMonitorRestart.restart() }
  }

  Process {
    id: themeModeProc
    command: ["omarchy-theme-color", "mode"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.themeMode = NightMan.parseThemeMode(text)
    }
    onExited: function(exitCode) {
      if (root.appearanceMode !== "follow") { root.themeApplyPending = false; return }
      if (exitCode !== 0 || root.themeMode === "") {
        root.themeApplyPending = false
        root.lastError = "Unable to determine the current Omarchy theme mode"
        return
      }
      root.mode = root.themeMode
      root.requestPreference(NightMan.modeToPreference(root.themeMode))
    }
  }

  Process {
    id: setPreferenceProc
    onExited: function(exitCode) {
      var completed = root.activePreference
      var queued = root.pendingPreference
      root.activePreference = ""
      if (exitCode !== 0) {
        root.pendingPreference = ""
        if (queued !== "" && queued !== completed) Qt.callLater(function() { root.requestPreference(queued) })
        else root.schedulePreferenceRetry(completed)
        return
      }
      // Never assign optimistically: the probe captures the actual value after every write.
      root.verificationPreference = completed
      root.probeAfterWrite = true
      Qt.callLater(root.probePreference)
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
    id: preferenceRetryTimer
    repeat: false
    onTriggered: {
      var target = root.preferenceTarget
      if (target !== "" && root.stateReady) root.startPreferenceWrite(target)
    }
  }

  Timer {
    id: transitionTimer
    repeat: false
    onTriggered: root.evaluate()
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

  Timer { id: preferenceMonitorRestart; interval: 2000; onTriggered: if (!preferenceMonitor.running) preferenceMonitor.running = true }
  Timer { interval: 60 * 1000; running: true; repeat: true; onTriggered: root.evaluate() }
  Timer { interval: 5 * 60 * 1000; running: true; repeat: true; onTriggered: root.probePreference() }
  Timer { interval: 6 * 60 * 60 * 1000; running: true; repeat: true; onTriggered: root.refreshSchedule() }

  Component.onCompleted: {
    ensureDirProc.running = true
    preferenceProbe.running = true
    preferenceMonitor.running = true
  }

  IpcHandler {
    target: "codefriendly.nightman"

    function status(): string { return JSON.stringify(root.statusObject()) }
    // Compatibility actions: temporary overrides, available only in persistent Auto mode.
    function toggle(): string { return root.stateReady ? root.toggleManual() : "not ready" }
    function light(): string { return root.stateReady ? root.setManual("light") : "not ready" }
    function dark(): string { return root.stateReady ? root.setManual("dark") : "not ready" }
    function auto(): string { if (!root.stateReady) return "not ready"; if (root.appearanceMode !== "auto") return "unavailable outside Auto"; root.clearOverride(true); return root.scheduledMode }
    function modeFollowTheme(): string { if (!root.stateReady) return "not ready"; root.setAppearanceMode("follow"); return root.appearanceMode }
    function modeAuto(): string { if (!root.stateReady) return "not ready"; root.setAppearanceMode("auto"); return root.appearanceMode }
    function modeDay(): string { if (!root.stateReady) return "not ready"; root.setAppearanceMode("day"); return root.appearanceMode }
    function modeNight(): string { if (!root.stateReady) return "not ready"; root.setAppearanceMode("night"); return root.appearanceMode }
  }
}
