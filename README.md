# NightMan

NightMan manages the standard light/dark appearance preference on Omarchy. It can leave that preference with your Omarchy theme, follow sunrise and sunset, or stay pinned to day or night. Apps that follow the system appearance update automatically.

NightMan changes only:

```text
org.gnome.desktop.interface color-scheme
```

It does not change your Omarchy theme, wallpaper, GTK theme, icons, or Night Light. It runs entirely as an Omarchy Quattro plugin; there is no systemd service.

## Install

```bash
omarchy plugin add https://github.com/codefriendly/omarchy-nightman.git --enable
```

Click the sun/moon bar icon to open the panel. The header always shows NightMan's current state.

## Appearance modes

The selected mode is saved across shell restarts and Omarchy theme changes:

- **Theme** (Follow theme) lets Omarchy control the appearance. When selected, NightMan reads the active Omarchy theme's light/dark mode, applies its matching color-scheme preference, and confirms the result. Later external changes are observed but not corrected. GNOME's `default` observation is displayed as Light because it expresses no dark preference.
- **Auto** follows the saved schedule without any extra override controls.
- **Day** selects light mode. It is permanent by default, but can instead last until the next scheduled change.
- **Night** selects dark mode. It is permanent by default, but can instead last until the next scheduled change.

After selecting Day or Night, choose **Permanent** or **Until _next schedule time_**. A temporary choice survives a shell restart and expires at the displayed solar or fixed-time transition. Selecting Day or Night itself always defaults to Permanent.

NightMan continuously watches `color-scheme`. In Auto, pinned Day or Night, and a temporary Day or Night, changes made by a theme switch or another program are corrected immediately. Follow theme never corrects them. NightMan never writes `gtk-theme`.

Existing installations migrate to **Auto** and keep their schedule and location settings. The schedule stays editable in Theme, Day, and Night, but is labelled saved and inactive until Auto—or a temporary Day/Night choice—uses it again.

## Choosing a schedule

The schedule tabs remain **Automatic**, **Location**, and **Fixed times**.

### Automatic

Uses sunrise and sunset for your current location. NightMan first checks for a location selected in Omarchy Weather. Otherwise it estimates your location from your IP address.

IP location can be inaccurate with a VPN. Selecting a city in Omarchy Weather or NightMan avoids that problem.

### Location

Search for a city and select a result. NightMan uses that city's sunrise and sunset until you choose another schedule.

### Fixed times

Choose exact day and night start times in 24-hour `HH:MM` format. These times also serve as the fallback if solar times are unavailable. Defaults are 07:00 and 19:00.

## Privacy and stored data

Automatic IP location contacts [ipapi.co](https://ipapi.co/). Solar times and city search use [Open-Meteo](https://open-meteo.com/). A city search is sent after at least two characters are entered. Approximate coordinates are sent to Open-Meteo when IP location is used.

Settings, schedule cache, and any active temporary override are stored under:

```text
~/.local/state/nightman/
```

## Command-line controls

```bash
omarchy-shell codefriendly.nightman status
omarchy-shell codefriendly.nightman modeFollowTheme
omarchy-shell codefriendly.nightman modeAuto
omarchy-shell codefriendly.nightman modeDay
omarchy-shell codefriendly.nightman modeNight
```

These unambiguous `mode…` commands select persistent modes. `status` returns the persistent mode, effective preference, schedule state, temporary override, next transition, location source, and recent error as JSON.

The older commands remain for compatibility:

```bash
omarchy-shell codefriendly.nightman toggle
omarchy-shell codefriendly.nightman light
omarchy-shell codefriendly.nightman dark
omarchy-shell codefriendly.nightman auto
```

They are available only while Auto is active. `light`, `dark`, and `toggle` create the same temporary Day or Night choice shown in the panel. `auto` clears that temporary choice and returns to the schedule; it does not select Auto from another persistent mode. Mutating commands return `not ready` until saved state has loaded.

Removing or disabling the NightMan widget stops its plugin service, so it no longer monitors or changes the preference.

## Development

```bash
omarchy plugin validate .
node tests/nightman.test.js
qmllint BarWidget.qml Panel.qml Service.qml
```
