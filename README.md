# ThemeSync (macOS)

A tiny menu bar app that runs shell scripts when macOS switches between Light and Dark mode.

## Features

- Automatically detects macOS appearance changes
- Supports separate scripts for Light and Dark modes
- Optional command-line arguments for each script
- Sets `THEME_MODE=dark` or `THEME_MODE=light` environment variable for scripts
- Remembers the last theme state — scripts only run on actual changes, not on every app launch
- Menu bar icon reflects the current mode (☀️ / 🌙)
- "Run Dark Script" / "Run Light Script" menu items for quick testing
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

This creates `build/ThemeSync.app`.

## Usage

1. Launch the app (double-click the `.app`).
2. Click the menu bar item (shows as "TS" with a sun or moon icon).
3. Click **Open Settings** to configure your scripts:
   - `Script on Dark` - path to script that runs when switching to Dark mode
   - `Args on Dark` - optional command-line arguments for the dark mode script
   - `Script on Light` - path to script that runs when switching to Light mode
   - `Args on Light` - optional command-line arguments for the light mode script
   - `Launch at Login` - automatically start ThemeSync when you log in
4. Use the **Choose…** buttons to browse for script files.
5. Use **Run Dark Script** / **Run Light Script** from the menu to test without toggling system appearance.

## Releasing

```bash
make release VERSION=1.1.0
```

This tags `v1.1.0` and pushes the tag, which triggers a GitHub Actions workflow that builds the app and publishes a release.

## Notes

- Scripts are executed directly, so use full paths to executables
- Scripts receive `THEME_MODE=dark` or `THEME_MODE=light` as an environment variable
- Arguments support whitespace splitting, quoted values, and backslash escaping; shell expansion and command chaining are not evaluated
- Scripts must be executable (`chmod +x your_script.sh`)
- Script execution times out after 30 seconds for safety
- The app validates script paths and logs errors if scripts are missing or not executable
- The app is a menu bar accessory and will not show in the Dock
- Minimum supported macOS version is 13.0 (Apple Silicon)

## Troubleshooting

- Check Console.app for log messages from "com.themeScriptRunner" if scripts aren't running
- Ensure your scripts have execute permissions: `chmod +x /path/to/your/script`
- Test your scripts manually first to ensure they work correctly
