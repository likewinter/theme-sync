# Theme Script Runner (macOS)

A tiny menu bar app that runs shell scripts when macOS switches between Light and Dark mode.

## Build

```bash
make app
```

This creates `build/ThemeScriptRunner.app`.

## Usage

1. Launch the app (double-click the `.app`).
2. Open **Open Settings** from the menu bar item.
3. Set:
   - `Script on Dark` to the script that should run when macOS becomes dark.
   - `Script on Light` to the script that should run when macOS becomes light.

Notes:
- Scripts are executed via `/bin/zsh -lc`, so you can point directly to a script path.
- The app is a menu bar accessory and will not show in the Dock.
- Minimum supported macOS version is 13.0 because it uses `MenuBarExtra`.
