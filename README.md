# ThemeSync (macOS)

A tiny menu bar app that runs shell scripts when macOS switches between Light and Dark mode.

## Features

- Automatically detects macOS appearance changes
- Supports separate scripts for Light and Dark modes
- Optional command-line arguments for each script
- Sets `THEME_MODE=dark` or `THEME_MODE=light` environment variable for scripts
- Remembers the last theme state — scripts only run on actual changes, not on every app launch
- Recovers unfinished theme changes on the next launch
- Menu bar icon reflects the current mode (☀️ / 🌙)
- "Run Dark Script" / "Run Light Script" menu items for quick testing
- Test buttons in Settings with inline progress, success, and error feedback
- Last-run status in the menu, with details and script output available on click
- Opens Settings on first launch when no scripts are configured
- Optional Launch at Login
- 30-second execution timeout for safety
- Script validation (checks if file exists and is executable)

## Install

Download the latest `ThemeSync.app.zip` from [GitHub Releases](https://github.com/likewinter/theme-sync/releases), unzip, and drag `ThemeSync.app` to `/Applications`.

> The app is ad-hoc signed (no Apple Developer ID). On first launch, right-click → **Open** to bypass Gatekeeper.

## Build from source

```bash
make app
```

This creates `build/ThemeSync.app`. The bundle is stamped with the latest git tag's version (`0.0.0` if no tags exist); override with `make app VERSION=x.y.z`.

## Usage

1. Launch the app (double-click the `.app`). Settings opens automatically on the first launch if no scripts are configured.
2. Click the menu bar item (shows as "TS" with a sun or moon icon).
3. Click **Open Settings** to configure your scripts:
   - `Script on Dark` - path to script that runs when switching to Dark mode
   - `Args on Dark` - optional command-line arguments for the dark mode script
   - `Script on Light` - path to script that runs when switching to Light mode
   - `Args on Light` - optional command-line arguments for the light mode script
   - `Launch at Login` - automatically start ThemeSync when you log in
4. Use the **Choose…** buttons to browse for script files.
5. Click **Test** beside either script to run it without toggling system appearance. The result appears below its arguments. You can also use **Run Dark Script** / **Run Light Script** from the menu.
6. Click the menu's **Last run** entry to inspect the result, time, script path, arguments, and output. Only the most recent execution is saved.

## Releasing

```bash
make release VERSION=1.1.0
```

An explicit `VERSION` is required. This tags `v1.1.0` and pushes the tag, which triggers a GitHub Actions workflow that builds the app and publishes a release.

## Notes

- Scripts are executed directly, so use full paths to executables
- Scripts receive `THEME_MODE=dark` or `THEME_MODE=light` as an environment variable
- Arguments support whitespace splitting, quoted values, and backslash escaping; shell expansion and command chaining are not evaluated
- Script output includes stdout and stderr; details retain the last 64 KiB and indicate when earlier output was omitted
- Tests use the path and arguments configured when you click **Test**; editing those fields hides a result for the old configuration
- Scripts must be executable (`chmod +x your_script.sh`)
- If the app quits with an automatic theme change queued or running, it runs the current mode's script again on the next launch
- Script execution times out after 30 seconds for safety; the timeout terminates the script and any processes it started
- The app validates script paths and logs errors if scripts are missing or not executable
- The app is a menu bar accessory and will not show in the Dock
- Minimum supported macOS version is 13.0 (Apple Silicon)

## Troubleshooting

- Check **Last run** in the menu for the latest result and script output
- Check Console.app for log messages from "com.likewinter.theme-sync" if scripts aren't running
- Ensure your scripts have execute permissions: `chmod +x /path/to/your/script`
- Test your scripts manually first to ensure they work correctly

## Tests

```bash
make test
```

GitHub Actions runs the tests and builds the app on pushes to `main` and pull requests. Release builds also run the tests before packaging the app.
