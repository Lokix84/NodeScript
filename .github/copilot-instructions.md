# NodeScript Plugin - AI Agent Coding Instructions

## Project Overview

**NodeScript** is a Godot 4.5+ plugin that provides a **visual, node-based editor** for creating GDScript classes, functions, variables, signals, and enums without writing code directly. The plugin converts a hierarchical data structure (`NodeScriptResource`) into valid GDScript source code.

### Core Architecture

The plugin works in **two main domains**:

1. **Data Domain** (`NodeScriptResource`): Stores all script metadata as structured dictionaries (classes, functions, variables, signals, enums, regions with order information).
2. **Generation Domain** (`NodeScriptSync`): Converts data → GDScript text bidirectionally. Parses existing GDScript to extract structure; emits GDScript from the data model.

## Critical Workflows & Commands

### Running Tests

```bash
# From Godot editor, run (in Script tab):
# Tools > NodeScript > Run Tests
# Or use:
godot --script res://tests/run_tests.gd
```

Tests scan `res://tests/unit/` for scripts matching `test_*.gd` and execute all methods starting with `test_`. The test runner is in [tests/run_tests.gd](tests/run_tests.gd).

### Key File Locations

| Purpose                  | Path                                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------------------------------------- |
| **Main Panel & UI**      | [addons/nodescript/editor/nodescript_panel.gd](addons/nodescript/editor/nodescript_panel.gd) (4700+ lines) |
| **Data ↔ GDScript Sync** | [addons/nodescript/editor/nodescript_sync.gd](addons/nodescript/editor/nodescript_sync.gd) (2158 lines)    |
| **Data Structure**       | [addons/nodescript/core/nodescript_resource.gd](addons/nodescript/core/nodescript_resource.gd)             |
| **Configuration**        | [addons/nodescript/config.gd](addons/nodescript/config.gd)                                                 |
| **Utilities**            | [addons/nodescript/utils/](addons/nodescript/utils/)                                                       |

## Project-Specific Conventions

### The "Order Map" Pattern

**Critical**: The plugin maintains an **explicit order map** separate from data arrays. This is NOT just sorting—it's the source-of-truth for generating GDScript.

```gdscript
# Data structure in NodeScriptResource.body:
{
  "functions": [{...}, {...}],  # Unordered array
  "order": {
    "ClassName|RegionName": [
      {"type": "function", "name": "foo", "line": 5, "indent": 1},
      {"type": "variable", "name": "bar", "line": 10, "indent": 1},
      {"type": "blank", "name": "blank_1"}
    ]
  }
}
```

**When modifying functions/variables/signals:**

1. Always update **both** the data array AND the order map
2. See [nodescript_sync.gd#L47](addons/nodescript/editor/nodescript_sync.gd#L47) (`append_order_entry`) as the canonical method
3. Direct array manipulation without updating `order` will break generation

### Scope Key Format

Scopes are identified as `"ClassName|RegionName"`:

- Root scope: `"|"` (empty class, empty region)
- Class scope: `"MyClass|"` (class, no region)
- Nested: `"MyClass|MyRegion"` (within region inside class)

Used throughout: `_scope_key()`, `_scope_order_for()`, `_entry_region()`, `_entry_class()` helpers.

### Function Body Structure

Function bodies are **arrays of statement dictionaries**:

```gdscript
# Example function entry:
{
  "name": "my_func",
  "parameters": [{"name": "arg", "type": "int"}],
  "return_type": "void",
  "region": "",
  "class": "MyClass",
  "body": [
    {"type": "comment", "text": "# Do something"},
    {"type": "assignment", "target": "x", "expr": "10"},
    {"type": "call", "target": "print", "arguments": "x"},
    {"type": "return", "expr": "x"}
  ]
}
```

Statement types: `comment`, `assignment`, `call`, `if`/`elif`/`else`, `match`/`case`, `for`, `while`, `return`, `pass`, `signal_emit`, `raw`, etc. Parsing is in [statement_classifier.gd](addons/nodescript/utils/statement_classifier.gd).

### UI Editor Pattern

All UI editors (`FunctionBodyEditor`, `VariableEditor`, `SignalEditor`, etc.) follow this pattern:

1. Emit a signal when data is committed (e.g., `variable_editor_submitted`)
2. Connect signal to panel's `_on_*_editor_submitted()` method
3. Handler updates `sync.nodescript.body`, calls `sync.save()`, then `_refresh_tree()` and `_apply_declarations_to_script()`

Example: [nodescript_panel.gd#L2070](addons/nodescript/editor/nodescript_panel.gd#L2070) `_on_variable_editor_submitted()`.

## Integration & Data Flow

### Panel → Sync → Script

```
User edits in UI
  ↓
_on_*_editor_submitted() called
  ↓
Update sync.nodescript.body data structures
  ↓
sync.save() (persists to .tres file)
  ↓
_apply_declarations_to_script()
  ↓
active_script.source_code = sync.emit_declarations()
  ↓
Godot recompiles GDScript
```

### Script → Panel (Reverse)

When switching to a script in the editor:

1. [nodescript_panel.gd#L51](addons/nodescript/editor/nodescript_panel.gd#L51) calls `set_target_script()`
2. Loads/creates associated `.nodescript.tres` resource
3. Reinitializes sync with `reset_nodescript()`
4. Refreshes tree UI from data

## Testing & Validation

### Test Structure

- **Unit tests** ([tests/unit/](tests/unit/)): Test individual utilities (`statement_classifier`, `nodescript_utils`)
- **Functional tests** ([tests/functional/](tests/functional/)): Test sync behavior, generation, parsing
- **Integration tests** ([tests/integration/](tests/integration/)): Test panel UI interactions with sync
- **Visual demo** ([tests/demo/](tests/demo/)): Demonstrates multi-step workflows; see `_hint_for_step()`

### Common Test Pattern

```gdscript
# Access the panel instance and its sync:
var panel_instance = _create_panel()
panel_instance._on_variable_editor_submitted({"name": "health", "type": "int"})
var generated = panel_instance.sync.emit_declarations()
assert_true(generated.find("var health: int") != -1)
```

## Key Gotchas & Patterns to Avoid

1. **Never mutate data arrays without updating order map** → Leads to missing code in output
2. **Always use scope key format** `"Class|Region"` when querying order maps
3. **Sync is @tool and RefCounted** → Must be reset when switching scripts; not persistent across scene changes
4. **Tree display modes** (grouped, true order, flat) → Controlled by [nodescript_panel.gd#L65](addons/nodescript/editor/nodescript_panel.gd#L65) flag; regenerates tree without changing data
5. **Drag-drop reordering** → Updates both arrays AND order maps; see `_move_function_payload()` pattern
6. **Configuration** → Read from `res://addons/nodescript/config.cfg` via [NodeScriptConfig](addons/nodescript/config.gd); defaults in `DEFAULTS` dict

## Configuration

Settings in `config.cfg` (under `[nodescript]` section):

- `auto_sort_tree`: Sort entries alphabetically
- `show_enum_values_in_tree`: Display enum members in tree
- `log_level`: 0 (silent), 1 (minimal), 2 (verbose)
- `tree_display_mode`: 0 (grouped), 1 (true order), 2 (flat sorted)
- `auto_space_strategy`: Blank line insertion strategy (see below)

### Auto-Spacing Strategies

Blank lines improve readability by separating declaration groups. Configure behavior in `config.cfg`:

**Strategies:**

- `"none"`: No automatic blank lines
- `"between_types"`: Insert blank after signals, enums, regions, classes
- `"after_groups"`: Insert blank between groups (variables, signals, enums, regions/classes, functions)

**How it works:**

1. Applied automatically in `NodeScriptSync._ensure_order_map()`
2. Scans each scope's order array and inserts blanks based on strategy
3. Respects manual blank entries (won't duplicate)
4. Right-click tree items → "Insert blank space after" to manually add blanks
5. Blanks appear greyed-out in tree (non-selectable) with separator visual

**Example with `"between_types"`:**

```gdscript
# Generated output
var health: int
var mana: int

signal died

enum State { IDLE, RUN }

class Data:
    pass

func take_damage(): pass
```

## Adding New Features

### Adding a New Item Type (e.g., "Constant")

1. Update `NodeScriptResource.body` structure to include `"constants": []`
2. Create UI editor (e.g., `constant_editor.gd/.tscn`)
3. Connect editor to `_on_constant_editor_submitted()` in panel
4. Update sync's generation logic to emit constant declarations
5. Update tree-building logic to display constants
6. Add order-map support if reordering is needed
7. Add tests for new type

### Modifying Generation Logic

- Entry point: `NodeScriptSync.emit_declarations()` → `_build_script_lines()` → `_build_scope_lines()` for each scope
- Statement generation: `_emit_statement()` for each statement type
- Reference: [nodescript_sync.gd#L203](addons/nodescript/editor/nodescript_sync.gd#L203) for method/class generation examples
