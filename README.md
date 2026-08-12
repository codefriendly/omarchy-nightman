# NightMan

NightMan helps manage light and dark mode on Omarchy. It can follow sunrise and sunset, use a location you choose, or switch at fixed times. Apps set to follow the system appearance will update automatically.

It only changes this GNOME preference:

```text
org.gnome.desktop.interface color-scheme
```

Your Omarchy theme, wallpaper, GTK theme, and Night Light stay untouched. NightMan runs as an Omarchy Quattro plugin—there are no systemd services to install.

## Install

```bash
omarchy plugin add https://github.com/codefriendly/omarchy-nightman.git --enable
```

NightMan adds a sun/moon icon to the bar. Click it to open the panel.

## Using NightMan

The controls at the top temporarily override the schedule:

- **Day** switches to light mode until the next scheduled change.
- **Night** switches to dark mode until the next scheduled change.
- **Auto** returns control to the schedule.

A small dot on the bar icon means a manual override is active. The panel also shows the location and time of the next scheduled change.

## Choosing a schedule

NightMan offers three schedule options:

### Automatic

Uses sunrise and sunset for your current location. NightMan first checks for a location you selected in Omarchy Weather. If there isn't one, it estimates your location from your IP address.

IP-based location may be inaccurate when you use a VPN. Selecting a city in Omarchy Weather or NightMan avoids that problem.

### Location

Search for a city and select it from the results. NightMan will use that city's sunrise and sunset times until you switch back to **Automatic** or choose another schedule.

### Fixed times

Choose exactly when day mode and night mode begin. Times use the 24-hour `HH:MM` format.

If NightMan cannot retrieve solar times, it temporarily falls back to the configured fixed times. The defaults are 07:00 and 19:00.

## Privacy and stored data

Automatic IP location contacts [ipapi.co](https://ipapi.co/). Solar times and city search are provided by [Open-Meteo](https://open-meteo.com/).

Typing at least two characters in the city search sends that text to Open-Meteo. When IP location is used, your approximate coordinates are also sent to Open-Meteo to retrieve sunrise and sunset times.

NightMan stores its settings and cached schedule under:

```text
~/.local/state/nightman/
```

## Command-line controls

The panel should cover normal use, but the same controls are available over Quattro IPC:

```bash
omarchy-shell codefriendly.nightman status
omarchy-shell codefriendly.nightman toggle
omarchy-shell codefriendly.nightman light
omarchy-shell codefriendly.nightman dark
omarchy-shell codefriendly.nightman auto
```

`status` returns the current mode, schedule, location source, next transition, and any recent error as JSON.

## Development

```bash
omarchy plugin validate .
node tests/nightman.test.js
qmllint BarWidget.qml Panel.qml Service.qml
```
