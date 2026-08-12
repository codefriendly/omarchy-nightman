# NightMan

NightMan is a pure [Omarchy Quattro](https://omarchy.org/) plugin that schedules the standard GNOME desktop color-scheme preference. It sets only:

```text
org.gnome.desktop.interface color-scheme
```

It does **not** switch the Omarchy theme, wallpaper, `gtk-theme`, or Night Light, and it installs no systemd unit.

## Install

```bash
omarchy plugin add https://github.com/codefriendly/omarchy-nightman.git --enable
```

The plugin contains a Quattro service and a panel-capable bar widget. Under Quattro's current enablement contract, removing the third-party widget from the bar also disables its service.

## Panel and modes

Click the sun/moon bar widget to open or close its popup. The popup provides:

- **Day** — apply light mode as a manual override until the next scheduled transition.
- **Night** — apply dark mode as a manual override until the next scheduled transition.
- **Auto** — clear the manual override and immediately apply the schedule.

The widget has no click shortcuts that alter mode. Its sun/moon shows the applied state and its small accent dot shows an active manual override. The panel also shows the schedule source, active location, and next transition.

## Schedule and location settings

Settings are saved atomically to `~/.local/state/nightman/settings.json` and watched for external edits. Three practical behaviors are available:

1. **Automatic solar** — immediately uses valid coordinates saved by Omarchy Weather in `~/.local/state/omarchy/settings/weather.json`, then approximate IP geolocation from ipapi.co. No location search is shown in this tab. If solar data is unavailable it falls back to the configured fixed times.
2. **Location solar** — opens a city search without changing the active schedule until a result is selected. Selecting a result switches to that explicit location. Choose **Automatic** to clear it and return to automatic location selection.
3. **Fixed custom times** — enter distinct 24-hour `HH:MM` day and night start values. Overnight day ranges are supported.

The time fields and all loaded settings are validated. Coordinates must be finite and within latitude `-90..90` and longitude `-180..180`. Search and forecast values are passed to `curl` as argument arrays rather than shell-interpolated commands.

Open-Meteo supplies seven days of sunrise/sunset data. Solar schedules and locations are cached in `~/.local/state/nightman/schedule.json`; manual override state is stored in `override.json`. Requests time out, use bounded retries, and the service refreshes every six hours. Automatic location can disclose your IP to ipapi.co and sends coordinates to Open-Meteo. Typing two or more characters in the location search sends the search text to Open-Meteo after a short debounce.

## IPC

Compatibility commands remain available on target `codefriendly.nightman`:

```bash
omarchy-shell codefriendly.nightman status
omarchy-shell codefriendly.nightman toggle
omarchy-shell codefriendly.nightman light
omarchy-shell codefriendly.nightman dark
omarchy-shell codefriendly.nightman auto
```

`light`, `dark`, and `toggle` create manual overrides; `auto` clears one. `status` returns JSON including applied and scheduled mode, override state, schedule behavior/source, active location/source, next transition, validated settings, and the last error.

## Requirements and development

NightMan depends only on standard Omarchy components: Quattro/Quickshell, `curl`, `gsettings`, and core utilities. It uses schema version 1 and the installed `service` plus `bar-widget` entry-point contract. The popup is loaded by the bar widget using the same nested `Panel`/`KeyboardPanel` contract as Omarchy Weather.

```bash
omarchy plugin validate .
node tests/nightman.test.js
qmllint BarWidget.qml Panel.qml Service.qml
```
