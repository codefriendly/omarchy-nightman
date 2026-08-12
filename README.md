# NightMan

NightMan is a pure [Omarchy Quattro](https://omarchy.org/) plugin that switches the standard GNOME desktop color-scheme preference at local sunrise and sunset. It sets only:

```text
org.gnome.desktop.interface color-scheme
```

It does **not** switch the Omarchy theme, wallpaper, `gtk-theme`, or Night Light. Applications that honor the standard preference—including many browsers and other desktop apps—can follow it independently.

## Install

```bash
omarchy plugin add https://github.com/codefriendly/omarchy-nightman.git --enable
```

The plugin contains a background Quattro service and an optional bar widget. Enabling it places the widget in the bar; removing the widget from the bar also disables the third-party service under Quattro's current plugin enablement contract. No systemd unit is installed or used.

## Controls

- **Left click the widget:** toggle light/dark and keep that manual override until the next scheduled sunrise or sunset.
- **Right click the widget:** return to automatic mode immediately.
- Sun/moon shows the current state. A small accent dot indicates a manual override.

IPC uses the target `codefriendly.nightman`:

```bash
omarchy-shell codefriendly.nightman status
omarchy-shell codefriendly.nightman toggle
omarchy-shell codefriendly.nightman light
omarchy-shell codefriendly.nightman dark
omarchy-shell codefriendly.nightman auto
```

`status` returns JSON with the applied mode, scheduled mode, override state, schedule source, next transition, coarse location label, and last error. `light` and `dark`, like `toggle`, are manual overrides. `auto` clears the override and immediately applies the scheduled state.

## Scheduling, privacy, and offline behavior

On startup NightMan obtains approximate coordinates from `https://ipapi.co/json/` without an API key, then requests seven days of sunrise/sunset data from Open-Meteo's forecast API. It refreshes that coarse location every six hours so travel and timezone changes recover without excessive location requests. Failed startup or refresh requests receive three bounded short retries before normal periodic refresh resumes. Requests use `curl` argument arrays, time out, and never interpolate data into a shell command. Approximate coordinates, a location label, and the sunrise/sunset schedule are cached in:

```text
~/.local/state/nightman/schedule.json
```

The cache lets NightMan schedule normally through short outages. If there is no usable cache or it has aged beyond its forecast window, NightMan falls back to local **07:00 light / 19:00 dark** times. It refreshes the schedule every six hours and evaluates the desired state every minute, including at startup and resume-like clock jumps.

Using automatic location discloses your IP address to ipapi.co and sends the resulting approximate coordinates to Open-Meteo. No API key or precise device location service is used. Manual override state is stored in `~/.local/state/nightman/override.json` so it survives a shell restart but still expires at the next transition.

## Requirements and assumptions

NightMan depends only on tools present in standard Omarchy: Quattro/Quickshell, `curl`, `gsettings`, and core utilities. It follows the installed Quattro plugin contracts: schema version 1, `service` plus `bar-widget` entry points, service lookup through `bar.shell.serviceFor(id)`, and IPC through `IpcHandler`.

## Development

```bash
omarchy plugin validate .
node tests/nightman.test.js
```
