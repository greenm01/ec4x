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
- `PrimaryBorderColor` = `#1f3b8a` (outer double borders)
- `SecondaryBorderColor` = `#565f89` (overlay + nested idle borders)
- `TableBorderColor` = `#737aa2` (table grid/separators)
- `OuterBorderColor` = `#1f3b8a` (outer modal/frame borders)
- `InnerBorderColor` = `#565f89` (inner panel borders)
- `PanelTitleColor` = `#c0caf5` (inner panel titles)
- `ModalTitleColor` = `#c0caf5` (modal titles)
- `TableGridColor` = `#737aa2` (table grid/separators)
- `TableHeaderColor` = `#c0caf5` (table headers)
- `HudBorderColor` = `#414868` (HUD borders)
- `SelectedBgColor` = `#82aaff` (selected row background)
- `AccentColor` = `#c099ff` (secondary accent)
- `PrestigeColor` = `#e0af68` (primary focus highlight)
- `WarningColor` = `#ff9e64` (warning)
- `AlertColor` = `#f7768e` (error/critical)
- `PositiveColor` = `#9ece6a` (success)
- `InfoColor` = `#86e1fc` (informational)

## Recent Update

- `PrimaryBorderColor` (outer double borders) was adjusted from `#0000af`
  to `#1f3b8a` to reduce saturation and soften dominant panel framing.

## Focus Hierarchy

- Primary focus (panel focus): `focusBorderStyle()` (yellow)
- Secondary focus (nested focus): `accentBorderStyle()` (purple)
- Error/danger states: `alertStyle()` (red)

## Border Roles

- Top-level focusable panels: `panelBorderStyle(focused)`
  - focused: `focusBorderStyle()`
  - idle: `outerBorderStyle()`
- Top-level focusable panels inside modals: `modalPanelBorderStyle(focused)`
  - focused: `focusBorderStyle()`
  - idle: `modalBorderStyle()` / `SecondaryBorderColor`
- Nested controls/cards inside focused panels: `nestedPanelBorderStyle(active)`
  - active: `accentBorderStyle()`
  - idle: `modalBorderStyle()` / `SecondaryBorderColor`
- Table separators/grid lines: `tableGridStyle()`
  - default: `TableBorderColor`
- Overlay/dialog borders (single-line): `dialogBorderStyle()`
  - default: `SecondaryBorderColor`
- Modal outer frames (double-line): `newModal()` default
  - default: `outerBorderStyle()`

## Foreground Role Matrix

- Outer frame border fg: `outerBorderStyle()` / `OuterBorderColor`
- Inner panel border fg: `innerBorderStyle()` / `InnerBorderColor`
- Modal title fg: `modalTitleStyle()` / `ModalTitleColor`
- Panel title fg: `panelTitleStyle()` / `PanelTitleColor`
- Table grid/separator fg: `tableGridStyle()` / `TableGridColor`
- Table header fg: `tableHeaderStyle()` / `TableHeaderColor`

## Backdrop Focus

- For stacked in-game overlays, use modal backdrop dimming:
  - Configure modal with `.showBackdrop(true)`.
  - Default backdrop style is `modalDimOverlayStyle()`.
- Applies to overlays that cover existing in-game text (help, editors, popups).
- Do not force backdrop on base view modals that represent the active screen.

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
- Use `.showBackdrop(true)` for stacked overlays.
- Verify in both TrueColor and ANSI256 terminals.
- Verify ANSI fallback preserves role separation when possible.
