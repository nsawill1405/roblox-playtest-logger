# roblox-playtest-logger

Roblox Studio plugin for logging bugs, UI feedback and gameplay notes with screenshots, pins and console snapshots while playtesting. It is the Roblox Studio version of [unity-playtest-logger](https://github.com/nsawill1405/unity-playtest-logger).

## Features

- Dockable **Playtest Logger** window with **+ New Entry** and **Saved Entries** tabs.
- Captures the current Studio view with `CaptureService` (works in Edit and Play mode). If a capture isn't available, it renders a 3D snapshot of the scene from the saved camera instead.
- Numbered pins on the screenshot: click to add, drag to move, right-click to remove. Each pin labels what it points at automatically, for example `UI: ScreenGui/HUD/HealthBar` or `3D: Workspace.Map.Door`. You can edit the labels.
- Categories: UI & HUD, Todo, Bug, Physics & Controls, Camera, Visuals & Shaders, Level & Map.
- Captures context: mode, place, player position and speed, or the camera position in Edit mode.
- Console snapshot of the last 80 Output lines for each entry.
- Saved entries let you mark items done, hide done items, edit the description, category and pins, retake the screenshot, jump the camera to the saved view, open the console log, and delete entries.
- **Quick Screenshot** saves an entry right away. **F1** in the viewport opens the logger and captures a fresh frame. The optional **Pause on quick capture** setting pauses the playtest.

## Where logs go

Roblox plugins can't write files to disk, so logs are saved in the place under `ServerStorage/PlaytestLogs`:

| Item | Purpose |
| --- | --- |
| `changes.md` (ModuleScript) | Markdown checklist of every entry, the same format as the Unity `changes.md` |
| `entries.json` (ModuleScript) | All entry data as JSON |
| `Screenshots/<id>` (StringValue) | Compressed screenshot pixels |
| `ConsoleLogs/<id>` (ModuleScript) | Console snapshot text |

Entries are also kept in plugin settings for each place. That way, anything logged during Play mode is kept after you press Stop and is written into `ServerStorage` once you're back in Edit mode. Save or publish the place to keep the logs. To copy the Markdown, open it with `••• > Copy Markdown...` or open the `changes.md` script.

## Install

1. Install the tools with [Aftman](https://github.com/LPGhatguy/aftman): `aftman install`.
2. Build the plugin: `rojo build -o PlaytestLogger.rbxm`.
3. Copy `PlaytestLogger.rbxm` to your Studio plugins folder, or open Studio and use **Plugins > Plugins Folder**.

Or download the `PlaytestLogger.rbxm` artifact from the latest CI run.

The first capture can trigger a Studio permission prompt for screenshots. You can bind keyboard shortcuts for **Open Playtest Logger** and **Playtest Logger Quick Capture** under **File > Customize Shortcuts**.

## Development

```sh
selene src tests
stylua --check src tests
lune run tests/run.luau
rojo build -o PlaytestLogger.rbxm
```
