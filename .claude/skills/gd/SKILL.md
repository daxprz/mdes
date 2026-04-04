---
name: gd
description: GDScript code intelligence — diagnostics, hover, go-to-definition, references, and symbols via Godot's built-in LSP. Use when inspecting GDScript types, checking for errors, or navigating code. Also activates automatically when working with .gd files.
argument-hint: <diagnostics|hover|symbols|definition|references> <file> [line] [char]
allowed-tools: Bash Read
---

# GDScript Code Intelligence

Query Godot's built-in LSP for type info, diagnostics, and navigation.

## Usage

- `/gd diagnostics <file>` — Show errors and warnings
- `/gd hover <file> <line> [char]` — Type info at position (line is 1-based)
- `/gd symbols <file>` — List all classes, methods, variables, constants
- `/gd definition <file> <line> [char]` — Find where a symbol is defined
- `/gd references <file> <line> [char]` — Find all references to a symbol

## Arguments

$ARGUMENTS

## How to Run

```bash
python3 .claude/scripts/gdscript-lsp.py $ARGUMENTS
```

The script talks directly to Godot's LSP on port 6005. If Godot's LSP isn't running, it starts a headless instance automatically.

## Examples

```bash
# Check a file for errors
python3 .claude/scripts/gdscript-lsp.py diagnostics scripts/systems/shackle_entity.gd

# Get type info for a function
python3 .claude/scripts/gdscript-lsp.py hover scripts/ui/hud.gd 36 6

# List all symbols in a file
python3 .claude/scripts/gdscript-lsp.py symbols scripts/enemies/quadruped_monster.gd

# Find definition
python3 .claude/scripts/gdscript-lsp.py definition scripts/ui/hud.gd 40 10
```

## When to Use Automatically

When working on `.gd` files:
- Run `diagnostics` after making edits to check for errors
- Run `hover` when you need type information for a variable or function
- Run `symbols` to understand a file's structure before editing
- Run `definition` to navigate to where something is declared
