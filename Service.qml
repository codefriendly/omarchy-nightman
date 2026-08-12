import QtQuick
import Quickshell
import Quickshell.Io
import "NightMan.js" as NightMan

Item {
  id: root

  property var shell: null
  property var schedule: null
  property var location: null
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
  property bool stateLoadStarted: false
  property string pendingPreference: ""
  property string activePreference: ""
  property int networkRetryCount: 0
  property string networkRetryAction: ""

  readonly property int maximumNetworkRetries: 3

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/nightman"
  readonly property string cachePath: stateDir + "/schedule.json"
  readonly property string overridePath: stateDir + "/override.json"

  function now() { return new Date() }

  function statusObject() {
    return {
      mode: root.mode,
      preference: NightMan.modeToPreference(root.mode),
      scheduledMode: root.scheduledMode,
      override: root.overrideActive,
      source: root.scheduleSource,
      nextTransition: root.nextTransition,
      location: root.location ? root.location.name : "",
      lastError: root.lastError
    }
  }

  function evaluate() {
    var currentTime = root.now()
    var calculated = NightMan.stateAt(root.schedule, currentTime)
    root.scheduledMode = calculated.mode
    root.scheduleSource = calculated.source
    root.nextTransition = calculated.nextTransition

    if (root.overrideActive && NightMan.shouldExpireOverride(
        root.cacheLoaded, root.overrideLoaded, root.overrideExpiresAt, currentTime)) clearOverride(false)
    var desired = root.overrideActive ? root.overrideMode : calculated.mode
    applyMode(desired)
  }

  function scheduleStillUsable(nowDate) {
    return NightMan.scheduleState(root.schedule, nowDate).source === "sun"
  }

  function applyMode(value) {
    if (value !== "light" && value !== "dark") return
    root.mode = value
    if (!root.initialized || !root.cacheLoaded || !root.overrideLoaded) return
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
    var calculated = NightMan.stateAt(root.schedule, root.now())
    root.overrideActive = true
    root.overrideMode = value
    root.overrideExpiresAt = calculated.nextTransition
    overrideFile.setText(JSON.stringify({ mode: value, expiresAt: root.overrideExpiresAt }, null, 2) + "\n")
    applyMode(value)
    return value
  }

  function toggleManual() {
    var current = root.mode || NightMan.stateAt(root.schedule, root.now()).mode
    return setManual(current === "light" ? "dark" : "light")
  }

  function clearOverride(applyImmediately) {
    root.overrideActive = false
    root.overrideMode = ""
    root.overrideExpiresAt = ""
    overrideFile.setText("{}\n")
    if (applyImmediately !== false) evaluate()
  }

  function loadOverride(raw) {
    if (!root.stateLoadStarted) return
    var saved = NightMan.parseOverride(raw)
    if (saved) {
      root.overrideActive = true
      root.overrideMode = saved.mode
      root.overrideExpiresAt = saved.expiresAt
    } else {
      root.overrideActive = false
      root.overrideMode = ""
      root.overrideExpiresAt = ""
    }
    root.overrideLoaded = true
    evaluate()
  }

  function finishCacheLoad(raw) {
    if (!root.stateLoadStarted) return
    var cache = NightMan.parseCache(raw)
    if (cache) {
      root.location = cache.location
      root.schedule = cache.schedule
    }
    root.cacheLoaded = true
    evaluate()
    root.maybeStartNetwork()
  }

  function saveCache() {
    if (!root.location || !root.schedule) return
    cacheFile.setText(JSON.stringify({ location: root.location, schedule: root.schedule }, null, 2) + "\n")
  }

  function maybeStartNetwork() {
    if (!root.stateLoadStarted || !root.cacheLoaded || locationProc.running || forecastProc.running) return
    locationProc.running = true
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
    if (!root.location || forecastProc.running) return
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + encodeURIComponent(String(root.location.latitude))
      + "&longitude=" + encodeURIComponent(String(root.location.longitude))
      + "&daily=sunrise,sunset"
      + "&forecast_days=7"
      + "&timeformat=unixtime"
      + "&timezone=auto"
    forecastProc.command = ["curl", "-fsS", "--max-time", "8", url]
    forecastProc.running = true
  }

  FileView {
    id: cacheFile
    path: root.cachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.finishCacheLoad(text())
    onLoadFailed: root.finishCacheLoad("")
  }

  FileView {
    id: overrideFile
    path: root.overridePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadOverride(text())
    onLoadFailed: root.loadOverride("")
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(exitCode) {
      root.stateLoadStarted = true
      if (exitCode !== 0) root.lastError = "Unable to create NightMan state directory"
      cacheFile.reload()
      overrideFile.reload()
    }
  }

  Process {
    id: preferenceProbe
    command: ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentPreference = NightMan.parseGsettingsOutput(text)
    }
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
      } else {
        root.lastError = "Unable to set org.gnome.desktop.interface color-scheme"
      }
      root.activePreference = ""
      root.pendingPreference = ""
      Qt.callLater(function() {
        var desired = NightMan.modeToPreference(root.mode)
        if (!setPreferenceProc.running && desired !== root.currentPreference)
          root.startPreferenceWrite(desired)
      })
    }
  }

  Process {
    id: locationProc
    property bool responseAccepted: false
    command: ["curl", "-fsS", "--max-time", "6", "https://ipapi.co/json/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightMan.parseLocationResponse(text)
        locationProc.responseAccepted = parsed !== null
        if (!parsed) return
        root.location = parsed
      }
    }
    onRunningChanged: if (running) responseAccepted = false
    onExited: function(exitCode) {
      if (exitCode !== 0 || !responseAccepted) {
        root.handleNetworkFailure("Offline: using fixed 07:00/19:00 schedule", "location")
      } else {
        root.networkRetryCount = 0
        root.fetchForecast()
      }
    }
  }

  Process {
    id: forecastProc
    property bool responseAccepted: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = NightMan.parseForecastResponse(text)
        forecastProc.responseAccepted = parsed !== null
        if (!parsed) return
        root.schedule = parsed
      }
    }
    onRunningChanged: if (running) responseAccepted = false
    onExited: function(exitCode) {
      if (exitCode !== 0 || !responseAccepted) {
        root.handleNetworkFailure("Offline: using fixed 07:00/19:00 schedule", "forecast")
      } else {
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
    id: networkRetryTimer
    repeat: false
    onTriggered: {
      var action = root.networkRetryAction
      root.networkRetryAction = ""
      if (action === "forecast") root.fetchForecast()
      else if (action === "location") root.maybeStartNetwork()
    }
  }

  Timer {
    interval: 60 * 1000
    running: true
    repeat: true
    onTriggered: root.evaluate()
  }

  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    onTriggered: if (!preferenceProbe.running && !setPreferenceProc.running) preferenceProbe.running = true
  }

  Timer {
    interval: 6 * 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.refreshSchedule()
  }

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
