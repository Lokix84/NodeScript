# NodeScript

A lean, read-only Godot 4 editor plugin that mirrors a GDScript file into a navigable tree dock. It auto-creates a companion `.nodescript.tres` (structure-only) and lets you jump around your script faster than the built-in Methods list.

## Features

- Tree dock (left-side by default) showing signals, variables, enums, functions, regions, and classes.
- Three display modes: true order, alphabetical, grouped by type.
- Filter box with parent retention (matching children keep ancestors visible).
- Double-click or right-click → Jump to line in the script.
- Auto-creates `.nodescript.tres` when a script is selected and none exists.
- Bulk delete `.nodescript.tres` via the dock options menu (with confirmation).
- Example script in `addons/nodescript/examples/` to see the view in action.

## Installation

1. Download the latest zip from the `dist` folder: https://github.com/Lokix84/NodeScript/tree/main/dist and unzip it.
2. Copy the `nodescript` folder into your projects addons folder.
3. In Godot: Project Settings → Plugins → enable **NodeScript**.
4. Open a GDScript; the NodeScript dock appears and will auto-create its `.nodescript.tres`.

## Usage

- Use the filter to narrow items; parents stay visible if any child matches.
- Toggle display mode from the options (radio items).
- Right-click an item → Jump to Line.
- Options menu → “Delete all .nodescript.tres files…” to clean generated files.

## Notes

- The plugin is read-only; it does not mutate your scripts.
- All editor scripts are `@tool` and scoped to the dock; no autoloads are registered.
