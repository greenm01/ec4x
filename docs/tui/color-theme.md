# Player TUI Color Theme

This document defines the player TUI color contract.

## Source of Truth

- Theme family: **Tokyo Night**
- Variant: **Night**
- Canonical palette module: `src/player/tui/styles/ec_palette.nim`

## Core Tokens

- `CanvasBgColor` = `#1a1b26` (main background)
- `TrueBlackColor` = `#16161e` (modal/deeper background)
- `CanvasFgColor` = `#c0caf5` (primary text)
- `CanvasDimColor` = `#565f89` (secondary text)
- `HudBorderColor` = `#292e42` (primary borders)
- `SelectedBgColor` = `#82aaff` (selected row background)
- `AccentColor` = `#c099ff` (secondary accent)
- `PrestigeColor` = `#e0af68` (primary focus highlight)
- `WarningColor` = `#ff9e64` (warning)
- `AlertColor` = `#f7768e` (error/critical)
- `PositiveColor` = `#9ece6a` (success)
- `InfoColor` = `#86e1fc` (informational)

## Focus Hierarchy

- Primary focus (panel focus): `focusBorderStyle()` (yellow)
- Secondary focus (nested focus): `accentBorderStyle()` (purple)
- Error/danger states: `alertStyle()` (red)

## Usage Rules

- Use semantic styles from `ec_palette.nim`.
- Do not hardcode `Ansi256Color(...)` in player TUI widgets.
- Do not hardcode ad-hoc `RgbColor(...)` in player TUI widgets.
- If a new color role is needed, add a semantic token in `ec_palette.nim`
  first.

## Widget Checklist

When adding or updating a widget:

- Use `canvasStyle()` / `canvasDimStyle()` for normal text hierarchy.
- Use `selectedStyle()` for selected rows/items.
- Use `focusBorderStyle()` and `accentBorderStyle()` for focus state.
- Use `warningStyle()` and `alertStyle()` for warning/error semantics.
- Verify in both TrueColor and ANSI256 terminals.
