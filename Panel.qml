import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui
import "NightMan.js" as NightMan

Panel {
  id: root
  moduleName: "codefriendly.nightman"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var nightMan: null
  property string clockFormat: "HH:mm"
  readonly property var barIdentity: hostWidget || root
  property var suggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""
  property string formError: ""
  property string selectedBehavior: "automatic"
  property var locationDraft: null
  readonly property bool controlFocused: modeFollow.activeFocus || modeAuto.activeFocus || modeDay.activeFocus || modeNight.activeFocus
    || durationPermanent.activeFocus || durationUntil.activeFocus || behaviorAutomatic.activeFocus || behaviorLocation.activeFocus || behaviorFixed.activeFocus
    || saveLocationButton.activeFocus || saveTimesButton.activeFocus
  readonly property var majorControls: [modeFollow, modeAuto, modeDay, modeNight, durationPermanent, durationUntil,
    behaviorAutomatic, behaviorLocation, behaviorFixed, saveLocationButton, saveTimesButton]
  readonly property string selectedDayNight: {
    if (!nightMan) return ""
    if (nightMan.appearanceMode === "day") return "light"
    if (nightMan.appearanceMode === "night") return "dark"
    return nightMan.overrideActive ? nightMan.overrideMode : ""
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function focusControl(control) {
    if (!control || !control.visible) return
    control.forceActiveFocus()
    Qt.callLater(function() { root.keepVisible(control) })
  }

  function focusedMajorControl() {
    for (var i = 0; i < majorControls.length; i++) if (majorControls[i].activeFocus) return majorControls[i]
    return null
  }

  function activateFocusedControl() {
    var control = focusedMajorControl()
    if (control && typeof control.clicked === "function") control.clicked()
  }

  function keepVisible(control) {
    if (!control || !panelFlick) return
    var point = control.mapToItem(content, 0, 0)
    var top = point.y
    var bottom = top + control.height
    if (top < panelFlick.contentY) panelFlick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height), bottom - panelFlick.height + Style.space(8))
  }

  function moveMode(value, dx, dy) {
    var controls = [modeFollow, modeAuto, modeDay, modeNight]
    var index = value === "follow" ? 0 : (value === "auto" ? 1 : (value === "day" ? 2 : 3))
    if (dx !== 0) focusControl(controls[Math.max(0, Math.min(controls.length - 1, index + dx))])
    else if (dy > 0) focusControl(durationSection.visible ? durationPermanent : selectedBehaviorControl())
  }

  function selectedBehaviorControl() {
    if (selectedBehavior === "location") return behaviorLocation
    if (selectedBehavior === "fixed") return behaviorFixed
    return behaviorAutomatic
  }

  function moveBehavior(value, dx, dy) {
    var controls = [behaviorAutomatic, behaviorLocation, behaviorFixed]
    var index = value === "automatic" ? 0 : (value === "location" ? 1 : 2)
    if (dx !== 0) focusControl(controls[Math.max(0, Math.min(controls.length - 1, index + dx))])
    else if (dy < 0) focusControl(durationSection.visible ? durationPermanent : modeAuto)
    else if (dy > 0) {
      if (selectedBehavior === "location") focusControl(locationField)
      else if (selectedBehavior === "fixed") focusControl(saveTimesButton)
    }
  }

  function open() {
    controller.show()
    syncFields()
  }

  function syncFields() {
    if (!nightMan) return
    dayField.text = nightMan.config.dayStart
    nightField.text = nightMan.config.nightStart
    locationDraft = nightMan.config.location
    selectedBehavior = nightMan.config.scheduleMode
    formError = ""
  }

  function chooseMode(value) {
    if (nightMan) nightMan.setAppearanceMode(value)
  }

  function chooseBehavior(value) {
    if (!nightMan) return
    selectedBehavior = value
    formError = ""
    if (value === "automatic") nightMan.setScheduleBehavior("automatic")
    else if (value === "location") {
      if (locationDraft) nightMan.setExplicitLocation(locationDraft)
      else formError = "Search for and select a location first"
    }
    else if (value === "fixed") {
      if (!nightMan.setFixedTimes(dayField.text, nightField.text)) formError = "Enter two different valid 24-hour times"
    }
  }

  function saveTimes() {
    if (!nightMan || !nightMan.setFixedTimes(dayField.text, nightField.text)) {
      formError = "Enter two different times in HH:MM format"
      return
    }
    formError = ""
  }

  function requestGeocode() {
    var query = locationField.text.trim()
    geocodePendingQuery = query
    if (query.length < 2) { suggestions = []; return }
    if (!geocodeProc.running) startGeocode()
  }

  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5",
      "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  function selectLocation(location) {
    var normalized = NightMan.normalizedLocation(location)
    if (!normalized) return
    locationDraft = normalized
    suggestions = []
    locationField.text = ""
    geocodePendingQuery = ""
    geocodeActiveQuery = ""
    formError = ""
  }

  function saveLocation() {
    if (!nightMan || !locationDraft || !nightMan.setExplicitLocation(locationDraft)) {
      formError = "Search for and select a location first"
      return
    }
    formError = ""
  }

  function formatTransition(value) {
    if (!value) return "Pending schedule"
    var date = new Date(value)
    if (isNaN(date.getTime())) return "Pending schedule"
    var timeFormat = /(?:AP|ap)/.test(clockFormat) ? "h:mm AP" : "HH:mm"
    return Qt.formatDateTime(date, "ddd " + timeFormat)
  }

  function nextTransitionLabel() {
    if (!nightMan || !nightMan.nextTransition) return "Pending schedule"
    var event = nightMan.scheduleSource === "sun"
      ? (nightMan.scheduledMode === "light" ? "Sunset" : "Sunrise")
      : (nightMan.scheduledMode === "light" ? "Night starts" : "Day starts")
    return event + " · " + formatTransition(nightMan.nextTransition)
  }

  function sourceLabel() {
    if (!nightMan) return "Starting"
    if (nightMan.config.scheduleMode === "fixed") return "Fixed custom times"
    if (nightMan.scheduleSource !== "sun") return "Solar unavailable · fixed-time fallback"
    if (nightMan.locationSource === "explicit") return "Solar · chosen location"
    if (nightMan.locationSource === "weather") return "Solar · Weather location"
    if (nightMan.locationSource === "cache") return "Automatic Location"
    if (nightMan.locationSource === "saved") return "Solar · saved location fallback"
    return "Solar · automatic IP location"
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var currentQuery = locationField.text.trim()
        if (root.geocodeActiveQuery === currentQuery && currentQuery.length >= 2) {
          root.suggestions = NightMan.parseGeocodingResults(text)
          root.suggestionIndex = 0
        }
        if (root.geocodePendingQuery.length >= 2 && root.geocodePendingQuery !== root.geocodeActiveQuery)
          Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer { id: geocodeDebounce; interval: 300; onTriggered: root.requestGeocode() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: dayField.activeFocus || nightField.activeFocus || locationField.activeFocus
      onMoveRequested: function(dx, dy) {
        var control = root.focusedMajorControl()
        if (!control) { root.focusControl(modeFollow); return }
        if (control === durationPermanent || control === durationUntil) {
          if (dx < 0) root.focusControl(durationPermanent)
          else if (dx > 0) root.focusControl(durationUntil)
          else if (dy < 0) root.focusControl(root.selectedDayNight === "light" ? modeDay : modeNight)
          else if (dy > 0) root.focusControl(root.selectedBehaviorControl())
          return
        }
        if (control === saveLocationButton || control === saveTimesButton) {
          if (dy < 0) root.focusControl(control === saveLocationButton ? locationField : dayField.inputControl)
          return
        }
        if (control.value === "follow" || control.value === "auto" || control.value === "day" || control.value === "night")
          root.moveMode(control.value, dx, dy)
        else root.moveBehavior(control.value, dx, dy)
      }
      onActivateRequested: {
        if (root.focusedMajorControl()) root.activateFocusedControl()
        else root.focusControl(modeFollow)
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (direction > 0) modeFollow.forceActiveFocus()
        else root.switchPanel(direction)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: parent.width
          spacing: Style.space(13)

          PanelHero {
            width: parent.width
            title: "NightMan"
            meta: root.nightMan ? root.nightMan.statusText() : "Starting"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            iconSize: Style.font.displayLarge
            iconComponent: Component {
              Text {
                text: root.nightMan && root.nightMan.mode === "light" ? "☀" : "☾"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }
          }

          Row {
            id: modeRow
            width: parent.width
            spacing: Style.space(5)
            readonly property real cellWidth: (width - spacing * 3) / 4

            ModeButton { id: modeFollow; label: "Theme"; glyph: ""; value: "follow"; width: modeRow.cellWidth }
            ModeButton { id: modeAuto; label: "Auto"; glyph: "◌"; value: "auto"; width: modeRow.cellWidth }
            ModeButton { id: modeDay; label: "Day"; glyph: "☀"; value: "day"; width: modeRow.cellWidth }
            ModeButton { id: modeNight; label: "Night"; glyph: "☾"; value: "night"; width: modeRow.cellWidth }
          }

          Column {
            id: durationSection
            visible: root.selectedDayNight !== ""
            width: parent.width
            spacing: Style.spacing.labelGap

            Text {
              text: root.selectedDayNight === "light" ? "DAY MODE" : "NIGHT MODE"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.letterSpacing: 1
            }

            Row {
              id: durationRow
              width: parent.width
              spacing: Style.space(6)
              readonly property real cellWidth: (width - spacing) / 2

              Button {
                id: durationPermanent
                width: durationRow.cellWidth
                text: "Permanent"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                focusable: true
                active: root.nightMan && (root.selectedDayNight === "light"
                  ? root.nightMan.appearanceMode === "day" : root.nightMan.appearanceMode === "night")
                Keys.onEscapePressed: root.close()
                Keys.onLeftPressed: root.focusControl(durationPermanent)
                Keys.onRightPressed: root.focusControl(durationUntil)
                Keys.onUpPressed: root.focusControl(root.selectedDayNight === "light" ? modeDay : modeNight)
                Keys.onDownPressed: root.focusControl(root.selectedBehaviorControl())
                onClicked: if (root.nightMan) root.nightMan.setAppearanceMode(root.selectedDayNight === "light" ? "day" : "night")
              }

              Button {
                id: durationUntil
                width: durationRow.cellWidth
                text: "Until " + (root.nightMan ? root.formatTransition(root.nightMan.nextTransition) : "next change")
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                bordered: true
                focusable: true
                active: root.nightMan && root.nightMan.appearanceMode === "auto" && root.nightMan.overrideActive
                Keys.onEscapePressed: root.close()
                Keys.onLeftPressed: root.focusControl(durationPermanent)
                Keys.onRightPressed: root.focusControl(durationUntil)
                Keys.onUpPressed: root.focusControl(root.selectedDayNight === "light" ? modeDay : modeNight)
                Keys.onDownPressed: root.focusControl(root.selectedBehaviorControl())
                onClicked: if (root.nightMan) root.nightMan.useUntilTransition(root.selectedDayNight)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoRow { label: "Schedule"; value: root.sourceLabel() }
            InfoRow { label: "Location"; value: root.nightMan ? root.nightMan.activeLocationName : "—" }
            InfoRow { label: "Next"; value: root.nextTransitionLabel() }
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "SCHEDULE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            visible: root.nightMan && !root.nightMan.scheduleActive
            width: parent.width
            text: "Used when Appearance is set to Auto."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Row {
            id: behaviorRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            BehaviorButton { id: behaviorAutomatic; label: "Automatic"; value: "automatic"; width: behaviorRow.cellWidth }
            BehaviorButton { id: behaviorLocation; label: "Location"; value: "location"; width: behaviorRow.cellWidth }
            BehaviorButton { id: behaviorFixed; label: "Fixed times"; value: "fixed"; width: behaviorRow.cellWidth }
          }

          Text {
            visible: root.selectedBehavior === "automatic"
            width: parent.width
            text: "Uses your Omarchy Weather location when set; otherwise uses approximate IP location."
            wrapMode: Text.WordWrap
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Column {
            visible: root.selectedBehavior === "location"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.locationDraft
                ? "Chosen location: " + root.locationDraft.name + ". Search below to replace it."
                : "Search for a city, then select a result to use its sunrise and sunset."
              wrapMode: Text.WordWrap
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: locationField
              width: parent.width
              placeholderText: "Search city"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              onTextChanged: {
                root.geocodePendingQuery = text.trim()
                if (root.geocodePendingQuery.length < 2) root.suggestions = []
                geocodeDebounce.restart()
              }
              Keys.onDownPressed: root.suggestionIndex = Math.min(root.suggestions.length - 1, root.suggestionIndex + 1)
              Keys.onUpPressed: root.suggestionIndex = Math.max(0, root.suggestionIndex - 1)
              Keys.onReturnPressed: if (root.suggestions.length > 0) root.selectLocation(root.suggestions[root.suggestionIndex])
              Keys.onEscapePressed: { text = ""; root.suggestions = []; keyCatcher.forceActiveFocus() }
            }

            Column {
              visible: root.suggestions.length > 0
              width: parent.width
              spacing: 0

              Repeater {
                model: root.suggestions
                Button {
                  required property var modelData
                  required property int index
                  width: parent.width
                  text: modelData.name
                  leftAlign: true
                  foreground: root.bar.foreground
                  fontFamily: root.bar.fontFamily
                  hasCursor: index === root.suggestionIndex
                  onHovered: function(on) { if (on) root.suggestionIndex = index }
                  onClicked: root.selectLocation(modelData)
                }
              }
            }

            Button {
              id: saveLocationButton
              width: parent.width
              text: "Save location"
              iconText: "✓"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              focusable: true
              Keys.onEscapePressed: root.close()
              Keys.onUpPressed: root.focusControl(locationField)
              onActiveFocusChanged: if (activeFocus) root.keepVisible(saveLocationButton)
              onClicked: root.saveLocation()
            }
          }

          Column {
            visible: root.selectedBehavior === "fixed"
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              TimeField { id: dayField; label: "Day start"; width: (parent.width - parent.spacing) / 2 }
              TimeField { id: nightField; label: "Night start"; width: (parent.width - parent.spacing) / 2 }
            }

            Button {
              id: saveTimesButton
              width: parent.width
              text: "Save fixed times"
              iconText: "✓"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              focusable: true
              Keys.onEscapePressed: root.close()
              Keys.onUpPressed: root.focusControl(dayField.inputControl)
              onActiveFocusChanged: if (activeFocus) root.keepVisible(saveTimesButton)
              onClicked: root.saveTimes()
            }
          }

          Text {
            visible: root.formError !== ""
            width: parent.width
            text: root.formError
            color: root.bar.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.nightMan && root.nightMan.lastError !== ""
            width: parent.width
            text: root.nightMan ? root.nightMan.lastError : ""
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component ModeButton: Button {
    required property string label
    required property string glyph
    required property string value
    text: label
    iconText: glyph
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    bordered: true
    focusable: true
    Keys.onEscapePressed: root.close()
    Keys.onLeftPressed: root.moveMode(value, -1, 0)
    Keys.onRightPressed: root.moveMode(value, 1, 0)
    Keys.onUpPressed: root.moveMode(value, 0, -1)
    Keys.onDownPressed: root.moveMode(value, 0, 1)
    onActiveFocusChanged: if (activeFocus) root.keepVisible(this)
    fontSize: Style.font.bodySmall
    active: root.nightMan && (value === "day" ? root.selectedDayNight === "light"
      : (value === "night" ? root.selectedDayNight === "dark"
      : root.nightMan.appearanceMode === value && !root.nightMan.overrideActive))
    onClicked: root.chooseMode(value)
  }

  component BehaviorButton: Button {
    required property string label
    required property string value
    text: label
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    fontSize: Style.font.bodySmall
    bordered: true
    focusable: true
    Keys.onEscapePressed: root.close()
    Keys.onLeftPressed: root.moveBehavior(value, -1, 0)
    Keys.onRightPressed: root.moveBehavior(value, 1, 0)
    Keys.onUpPressed: root.moveBehavior(value, 0, -1)
    Keys.onDownPressed: root.moveBehavior(value, 0, 1)
    onActiveFocusChanged: if (activeFocus) root.keepVisible(this)
    active: root.selectedBehavior === value
    onClicked: root.chooseBehavior(value)
  }

  component InfoRow: Row {
    required property string label
    required property string value
    width: parent.width
    spacing: Style.space(8)
    Text {
      id: infoLabel
      text: label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Style.space(4); height: 1 }
    Text {
      width: Math.max(0, parent.width - infoLabel.implicitWidth - parent.spacing * 2 - Style.space(4))
      text: value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
    }
  }

  component TimeField: Column {
    required property string label
    property alias text: input.text
    property alias inputControl: input
    spacing: Style.spacing.labelGap
    Text {
      text: label.toUpperCase()
      color: Qt.darker(root.bar.foreground, 1.4)
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1
    }
    TextField {
      id: input
      width: parent.width
      placeholderText: "HH:MM"
      inputMethodHints: Qt.ImhDigitsOnly
      maximumLength: 5
      validator: RegularExpressionValidator { regularExpression: /(?:[01][0-9]|2[0-3]):[0-5][0-9]/ }
      foreground: root.bar.foreground
      font.family: root.bar.fontFamily
      Keys.onEscapePressed: root.close()
    }
  }
}
