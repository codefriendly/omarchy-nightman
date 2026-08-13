# NightMan

*Fighter of the Day Man*

NightMan manages light and dark appearance on Omarchy. It can follow your Omarchy theme, switch with sunrise and sunset, or stay pinned to day or night. Apps that use the standard system preference update automatically.

NightMan changes only the following setting:

```text
org.gnome.desktop.interface color-scheme
```

It does not change your Omarchy theme, wallpaper, GTK theme, icons, or Night Light. Everything runs inside the Omarchy shell as a Quattro plugin—there is no systemd service.

## Install

```bash
omarchy plugin add https://github.com/codefriendly/omarchy-nightman.git --enable
```

Click the sun/moon icon in the bar to open NightMan.

## Appearance modes

Your selected mode is saved across shell restarts and theme changes.

- **Theme** matches the light or dark mode of your current Omarchy theme.
- **Auto** follows your saved schedule.
- **Day** uses light mode.
- **Night** uses dark mode.

Day and Night are permanent by default. You can instead keep either one active only until the next scheduled transition. Temporary choices survive shell restarts.

NightMan watches `color-scheme` for external changes. Auto, Day, and Night enforce their selected appearance; Theme leaves later changes alone.

## Schedule

### Automatic

Uses sunrise and sunset for your current location. NightMan first checks Omarchy Weather and saved locations, then falls back to an approximate IP location when needed.

IP location can be inaccurate when using a VPN. Choose a city in Omarchy Weather or NightMan for more predictable results.

### Location

Search for a city and save it. NightMan remembers the location if you switch to another schedule.

### Fixed times

Set day and night start times in 24-hour `HH:MM` format. These times are also used when solar data is unavailable. The defaults are 07:00 and 19:00.

## Privacy and stored data

Automatic IP location contacts [IPWhois.io](https://ipwhois.io/) only when Omarchy Weather and saved locations have no usable location. Solar times and city search use [Open-Meteo](https://open-meteo.com/). Searches are sent after you enter at least two characters, and approximate coordinates are sent to Open-Meteo when IP location is used.

Settings, cached locations and schedules, and temporary overrides are stored in:

```text
~/.local/state/nightman/
```

NightMan is MIT-licensed, but third-party data and hosted services have their own terms. See [Third-party notices](THIRD_PARTY_NOTICES.md). Open-Meteo's free hosted API is limited to non-commercial use; commercial users should review its current [terms](https://open-meteo.com/en/terms) and [plans](https://open-meteo.com/en/pricing), or modify NightMan to use a compatible self-hosted service.

## Command line

```bash
omarchy-shell codefriendly.nightman status
omarchy-shell codefriendly.nightman modeFollowTheme
omarchy-shell codefriendly.nightman modeAuto
omarchy-shell codefriendly.nightman modeDay
omarchy-shell codefriendly.nightman modeNight
```

The four mode commands select persistent modes. `status` returns the current mode, preference, schedule, next transition, location source, and most recent error as JSON.

Temporary Auto-mode controls are also available:

```bash
omarchy-shell codefriendly.nightman toggle
omarchy-shell codefriendly.nightman light
omarchy-shell codefriendly.nightman dark
omarchy-shell codefriendly.nightman auto
```

`light`, `dark`, and `toggle` last until the next scheduled transition. `auto` clears the temporary choice and returns to the schedule. These commands work only while Auto is active.

## Development

```bash
omarchy plugin validate .
node tests/nightman.test.js
qmllint BarWidget.qml Panel.qml Service.qml
```
