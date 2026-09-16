import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Lights popup. All Home Assistant traffic goes through the bundled
// `ha-lights` script, so the access token never enters the shell process.
Panel {
  id: root
  moduleName: "vscarpenter.ha-lights"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string script: decodeURIComponent(Qt.resolvedUrl("ha-lights").toString().replace(/^file:\/\//, ""))

  // Settings from this widget's entry in ~/.config/omarchy/shell.json.
  readonly property bool demo: setting("demo", "Off") === "On"
  readonly property var baseCommand: {
    var args = [script,
      "--url", String(setting("url", "http://homeassistant.local:8123")),
      "--token-file", String(setting("tokenFile", "~/.config/homeassistant/token"))]
    if (demo) args.push("--demo")
    return args
  }
  // Compared as a string: settings are re-injected as new objects, which would
  // otherwise look like a change every time.
  readonly property string connectionKey: baseCommand.join("\n")
  readonly property int refreshMs: Math.max(10, Number(setting("refreshIntervalSec", 45)) || 45) * 1000

  // New connection settings: forget the old home and read the new one. The
  // seq bump also discards a read that was already in flight.
  onConnectionKeyChanged: {
    actionSeq++
    reported = []
    rooms = []
    desired = ({})
    loaded = false
    error = ""
    Qt.callLater(refresh)
  }

  // Last status from Home Assistant, before pending clicks are laid over it.
  property var reported: []
  property var rooms: []
  property int onCount: 0
  property string error: ""
  property bool loaded: false
  property var expanded: ({})

  // What the user last asked for, keyed by "area:<id>" or light entity id.
  // Hue reports new state a second or more after a command, so a click is
  // held on screen until Home Assistant agrees or the hold expires.
  readonly property int holdMs: 8000
  property var desired: ({})
  property var lastBrightness: ({})

  // Bumped on every command. A status read that started before the latest
  // command is discarded, so an in-flight poll can't undo a click.
  property int actionSeq: 0
  property int statusSeq: -1
  property bool refreshQueued: false
  property int settleRuns: 0

  readonly property string tooltip: error !== "" ? "Lights: " + error
    : (loaded ? onCount + (onCount === 1 ? " light on" : " lights on") : "Lights")

  function open() {
    root.controller.show()
    refresh()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    root.opened ? close() : open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function refresh() {
    if (statusProc.running) {
      refreshQueued = true
      return
    }
    statusSeq = actionSeq
    statusProc.running = true
  }

  function run(args) {
    actionSeq++
    Quickshell.execDetached(root.baseCommand.concat(args))
    // Re-read a few times while Hue settles rather than once.
    settleRuns = 4
    settleTimer.restart()
  }

  // changes: key -> true/false for on/off, or { on, brightness }.
  function hold(changes) {
    var next = Object.assign({}, desired)
    var until = Date.now() + holdMs
    for (var key in changes) {
      var c = changes[key]
      next[key] = typeof c === "object" ? Object.assign({ until: until }, c) : { on: c, until: until }
    }
    desired = next
    rooms = overlay(reported)
  }

  function setRoomOn(room, on) {
    var changes = {}
    changes["area:" + room.id] = on
    for (var i = 0; i < room.lights.length; i++)
      if (room.lights[i].available) changes[room.lights[i].id] = on
    hold(changes)
    run([on ? "on" : "off", "area:" + room.id])
  }

  function setLightOn(light, on) {
    var changes = {}
    changes[light.id] = on
    hold(changes)
    run([on ? "on" : "off", light.id])
  }

  function setAll(on) {
    var changes = {}
    for (var i = 0; i < reported.length; i++) {
      changes["area:" + reported[i].id] = on
      for (var j = 0; j < reported[i].lights.length; j++)
        if (reported[i].lights[j].available) changes[reported[i].lights[j].id] = on
    }
    hold(changes)
    run([on ? "all-on" : "all-off"])
  }

  function allOff() { setAll(false) }
  function allOn() { setAll(true) }

  function setBrightness(target, pct) {
    pct = Math.max(1, Math.round(pct))
    var changes = {}
    changes[target] = { on: true, brightness: pct }
    hold(changes)
    pendingBrightness = { target: target, pct: pct }
    brightnessDebounce.restart()
  }

  // Lay held clicks over reported state. A hold ends once Home Assistant
  // reports the same value, or when it expires.
  function overlay(source) {
    var now = Date.now()
    var holds = Object.assign({}, desired)
    var holdsChanged = false
    var remembered = Object.assign({}, lastBrightness)
    var next = JSON.parse(JSON.stringify(source))
    var count = 0

    function apply(key, item) {
      if (item.on && item.brightness > 0) remembered[key] = item.brightness
      var d = holds[key]
      var matches = d && item.on === d.on
        && (d.brightness === undefined || Math.abs(item.brightness - d.brightness) <= 2)
      if (d && (now > d.until || matches)) {
        delete holds[key]
        holdsChanged = true
      } else if (d) {
        item.on = d.on
        if (d.brightness !== undefined) item.brightness = d.brightness
      }
      if (item.on && !(item.brightness > 0)) item.brightness = remembered[key] || 0
    }

    for (var i = 0; i < next.length; i++) {
      var room = next[i]
      var anyBulbOn = false
      for (var j = 0; j < room.lights.length; j++) {
        apply(room.lights[j].id, room.lights[j])
        if (room.lights[j].on) { anyBulbOn = true; count++ }
      }
      var roomHeld = holds["area:" + room.id] !== undefined
      apply("area:" + room.id, room)
      // Without a pending room click, a bulb held on keeps its room on.
      if (!roomHeld && anyBulbOn) room.on = true
    }

    if (holdsChanged) desired = holds
    lastBrightness = remembered
    onCount = count
    return next
  }

  property var pendingBrightness: null

  Timer {
    id: brightnessDebounce
    interval: 250
    onTriggered: {
      if (!root.pendingBrightness) return
      root.run(["brightness", root.pendingBrightness.target, String(root.pendingBrightness.pct)])
      root.pendingBrightness = null
    }
  }

  Timer {
    id: settleTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.refresh()
      if (--root.settleRuns <= 0) stop()
    }
  }

  // Faster while the panel is open so changes from other apps show up.
  Timer {
    interval: root.opened ? 5000 : root.refreshMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Also expires holds when no status read would otherwise do it.
  Timer {
    interval: 1000
    running: Object.keys(root.desired).length > 0
    repeat: true
    onTriggered: root.rooms = root.overlay(root.reported)
  }

  Process {
    id: statusProc
    command: root.baseCommand.concat(["status"])
    onExited: {
      if (!root.refreshQueued) return
      root.refreshQueued = false
      Qt.callLater(root.refresh)
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        // Read started before the latest command: drop it and read again.
        // callLater lands after the process has exited either way.
        if (root.statusSeq !== root.actionSeq) {
          Qt.callLater(root.refresh)
          return
        }
        try {
          var parsed = JSON.parse(raw)
          if (parsed.error) {
            root.error = parsed.error
            return
          }
          root.reported = parsed.rooms || []
          // A slider mid-drag would jump if we replaced the model under it.
          if (!brightnessDebounce.running) root.rooms = root.overlay(root.reported)
          root.error = ""
          root.loaded = true
        } catch (e) {
          root.error = raw === "" ? "No response" : "Bad response"
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "r") root.refresh() }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: content
          width: scroller.width
          spacing: Style.space(10)

          PanelHero {
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            title: root.demo ? "Lights (demo)" : "Lights"
            meta: root.error !== "" ? "Not connected"
              : (root.loaded ? root.onCount + " on" : "Loading…")
            iconComponent: Text {
              textFormat: Text.PlainText
              text: root.onCount > 0 ? "󰌵" : "󰌶"
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.display
            }
            trailingControl: Row {
              spacing: Style.space(4)

              PanelActionButton {
                iconText: "\uDB80\uDF35"
                tooltipText: "All on"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                onClicked: root.allOn()
              }

              PanelActionButton {
                iconText: "\uDB81\uDC25"
                tooltipText: "All off"
                foreground: root.bar ? root.bar.foreground : Color.foreground
                hoverColor: root.bar ? root.bar.urgent : Color.urgent
                enabled: root.onCount > 0
                onClicked: root.allOff()
              }
            }
          }

          PanelSeparator {
            foreground: root.bar ? root.bar.foreground : Color.foreground
          }

          Text {
            readonly property string hint: root.error !== ""
              ? root.error + ". Check the URL and token file in the widget settings."
              : (root.loaded && root.rooms.length === 0
                ? "No lights found. Assign your lights to areas in Home Assistant."
                : "")
            visible: hint !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: hint
            wrapMode: Text.Wrap
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.rooms

            delegate: Column {
              id: roomItem
              required property var modelData
              readonly property var room: modelData
              readonly property bool isExpanded: root.expanded[room.id] === true
              readonly property color fg: root.bar ? root.bar.foreground : Color.foreground

              width: content.width
              spacing: Style.space(4)
              opacity: room.available ? 1 : 0.5

              Item {
                width: parent.width
                height: roomSwitch.implicitHeight

                PanelActionButton {
                  id: chevron
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  visible: roomItem.room.lights.length > 1
                  iconText: roomItem.isExpanded ? "󰅀" : "󰅂"
                  tooltipText: roomItem.isExpanded ? "Hide bulbs" : "Show bulbs"
                  foreground: roomItem.fg
                  onClicked: root.toggleExpanded(roomItem.room.id)
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: chevron.right
                  anchors.leftMargin: Style.space(6)
                  anchors.right: roomBrightness.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: roomItem.room.name
                  color: roomItem.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  id: roomBrightness
                  textFormat: Text.PlainText
                  anchors.right: roomSwitch.left
                  anchors.rightMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  visible: roomItem.room.on && roomItem.room.brightness > 0
                  text: roomItem.room.brightness + "%"
                  color: Qt.darker(roomItem.fg, 1.4)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                ToggleSwitch {
                  id: roomSwitch
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  checked: roomItem.room.on
                  enabled: roomItem.room.available
                  foreground: roomItem.fg
                  onToggled: root.setRoomOn(roomItem.room, !roomItem.room.on)
                }
              }

              PanelSlider {
                visible: roomItem.room.on
                bar: root.bar
                x: chevron.width + Style.space(6)
                width: parent.width - x - Style.space(8)
                minimum: 1
                maximum: 100
                step: 5
                integer: true
                value: roomItem.room.brightness
                onReleased: function(v) { root.setBrightness("area:" + roomItem.room.id, v) }
              }

              Repeater {
                model: roomItem.isExpanded ? roomItem.room.lights : []

                delegate: Column {
                  id: bulbItem
                  required property var modelData
                  readonly property var light: modelData

                  x: Style.space(28)
                  width: roomItem.width - x
                  spacing: Style.space(2)
                  opacity: light.available ? 1 : 0.5

                  Item {
                    width: parent.width
                    height: bulbSwitch.implicitHeight

                    Text {
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.right: bulbSwitch.left
                      anchors.verticalCenter: parent.verticalCenter
                      text: bulbItem.light.name + (bulbItem.light.available ? "" : " (unavailable)")
                      color: roomItem.fg
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    ToggleSwitch {
                      id: bulbSwitch
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      trackHeight: 16
                      checked: bulbItem.light.on
                      enabled: bulbItem.light.available
                      foreground: roomItem.fg
                      onToggled: root.setLightOn(bulbItem.light, !bulbItem.light.on)
                    }
                  }

                  PanelSlider {
                    visible: bulbItem.light.on
                    bar: root.bar
                    width: parent.width - Style.space(8)
                    minimum: 1
                    maximum: 100
                    step: 5
                    integer: true
                    value: bulbItem.light.brightness
                    onReleased: function(v) { root.setBrightness(bulbItem.light.id, v) }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
