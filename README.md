# ThemeSync (macOS)

A tiny menu bar app that runs shell scripts when macOS switches between Light and Dark mode.

## Features

- Automatically detects macOS appearance changes
- Supports separate scripts for Light and Dark modes
- Optional command-line arguments for each script
- 30-second execution timeout for safety
- Script validation (checks if file exists and is executable)
- Menu bar icon shows "TS" with a half-filled circle

## Build

```bash
make app
```

This creates `build/ThemeSync.app`.

## Usage

1. Launch the app (double-click the `.app`).
2. Click **Open Settings** from the menu bar item (shows as "TS" with a half-filled circle icon).
3. Configure your scripts:
   - `Script on Dark` - path to script that runs when switching to Dark mode
   - `Args on Dark` - optional command-line arguments for the dark mode script
   - `Script on Light` - path to script that runs when switching to Light mode  
   - `Args on Light` - optional command-line arguments for the light mode script
4. Use the **Choose…** buttons to browse for script files.

## Notes

- Scripts are executed directly, so use full paths to executables
- Arguments support whitespace splitting, quoted values, and backslash escaping; shell expansion and command chaining are not evaluated
- Scripts must be executable (`chmod +x your_script.sh`)
- Script execution times out after 30 seconds for safety
- The app validates script paths and logs errors if scripts are missing or not executable
- The app is a menu bar accessory and will not show in the Dock
- Minimum supported macOS version is 13.0

## Troubleshooting

- Check Console.app for log messages from "com.themeScriptRunner" if scripts aren't running
- Ensure your scripts have execute permissions: `chmod +x /path/to/your/script`
- Test your scripts manually first to ensure they work correctly
