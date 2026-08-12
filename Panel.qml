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
  readonly property var barIdentity: hostWidget || root
  property var suggestions: []
  property int suggestionIndex: 0
  property string geocodePendingQuery: ""
  property string geocodeActiveQuery: ""
  property string formError: ""
  readonly property bool controlFocused: modeDay.activeFocus || modeNight.activeFocus || modeAuto.activeFocus
    || behaviorAutomatic.activeFocus || behaviorLocation.activeFocus || behaviorFixed.activeFocus
    || saveTimesButton.activeFocus || autoButton.activeFocus

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function open() {
    controller.show()
    syncFields()
  }

  function syncFields() {
    if (!nightMan) return
    dayField.text = nightMan.config.dayStart
    nightField.text = nightMan.config.nightStart
    formError = ""
  }

  function chooseMode(value) {
    if (!nightMan) return
    if (value === "auto") nightMan.clearOverride(true)
    else nightMan.setManual(value)
  }

  function chooseBehavior(value) {
    if (!nightMan) return
    if (value === "automatic") nightMan.clearExplicitLocation()
    else if (value === "location") nightMan.setScheduleBehavior("location")
    else if (value === "fixed") {
      if (!nightMan.setFixedTimes(dayField.text, nightField.text)) formError = "Enter two different valid 24-hour times"
      else formError = ""
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
    if (!nightMan || !nightMan.setExplicitLocation(location)) return
    suggestions = []
    locationField.text = ""
    geocodePendingQuery = ""
    geocodeActiveQuery = ""
    formError = ""
  }

  function formatTransition(value) {
    if (!value) return "Pending schedule"
    var date = new Date(value)
    if (isNaN(date.getTime())) return "Pending schedule"
    return Qt.formatDateTime(date, "ddd h:mm AP")
  }

  function sourceLabel() {
    if (!nightMan) return "Starting"
    if (nightMan.config.scheduleMode === "fixed") return "Fixed custom times"
    if (nightMan.scheduleSource !== "sun") return "Solar unavailable · fixed-time fallback"
    if (nightMan.locationSource === "explicit") return "Solar · chosen location"
    if (nightMan.locationSource === "weather") return "Solar · Weather location"
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
      blocked: dayField.activeFocus || nightField.activeFocus || locationField.activeFocus || root.controlFocused
      onMoveRequested: function() { modeDay.forceActiveFocus() }
      onActivateRequested: modeDay.forceActiveFocus()
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (direction > 0) modeDay.forceActiveFocus()
        else root.switchPanel(direction)
      }

      Flickable {
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

          Item {
            width: parent.width
            implicitHeight: Math.max(heroGlyph.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroGlyph
              text: root.nightMan && root.nightMan.mode === "light" ? "☀" : "☾"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.displayLarge
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroGlyph.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: root.nightMan ? (root.nightMan.mode === "light" ? "Day mode" : "Night mode") : "NightMan"
                color: root.bar.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                width: parent.width
                text: root.nightMan && root.nightMan.overrideActive ? "MANUAL UNTIL NEXT TRANSITION" : "FOLLOWING SCHEDULE"
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.1
              }
            }
          }

          Row {
            id: modeRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            ModeButton { id: modeDay; label: "Day"; glyph: "☀"; value: "light"; width: modeRow.cellWidth }
            ModeButton { id: modeNight; label: "Night"; glyph: "☾"; value: "dark"; width: modeRow.cellWidth }
            ModeButton { id: modeAuto; label: "Auto"; glyph: "◌"; value: "auto"; width: modeRow.cellWidth }
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap
            InfoRow { label: "Schedule"; value: root.sourceLabel() }
            InfoRow { label: "Location"; value: root.nightMan ? root.nightMan.activeLocationName : "—" }
            InfoRow { label: "Next"; value: root.nightMan ? root.formatTransition(root.nightMan.nextTransition) : "—" }
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "SCHEDULE"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
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

          Column {
            visible: root.nightMan && root.nightMan.config.scheduleMode === "fixed"
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
              onClicked: root.saveTimes()
            }
          }

          Column {
            visible: root.nightMan && root.nightMan.config.scheduleMode !== "fixed"
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: root.nightMan && root.nightMan.config.scheduleMode === "automatic"
                ? "Automatic prefers coordinates saved by Omarchy Weather, then IP location."
                : "Search to replace the chosen solar location."
              wrapMode: Text.WordWrap
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: locationField
                width: parent.width - autoButton.width - parent.spacing
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

              Button {
                id: autoButton
                text: "Use auto"
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.nightMan && root.nightMan.config.scheduleMode === "automatic"
                focusable: true
                Keys.onEscapePressed: root.close()
                onClicked: root.chooseBehavior("automatic")
              }
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
    active: root.nightMan && (value === "auto" ? !root.nightMan.overrideActive : root.nightMan.overrideActive && root.nightMan.overrideMode === value)
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
    active: root.nightMan && root.nightMan.config.scheduleMode === value
    enabled: value !== "location" || (root.nightMan && root.nightMan.config.location)
    tooltipText: enabled ? "" : "Search for a location below"
    onClicked: root.chooseBehavior(value)
  }

  component InfoRow: Row {
    required property string label
    required property string value
    width: parent.width
    spacing: Style.space(8)
    Text {
      text: label
      color: root.bar.foreground
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    Text {
      text: value
      color: root.bar.foreground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideLeft
    }
  }

  component TimeField: Column {
    required property string label
    property alias text: input.text
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
