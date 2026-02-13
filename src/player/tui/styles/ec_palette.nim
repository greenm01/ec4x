## EC4X TUI Color Palette
##
## Tokyo Night Night palette for the TUI.
## TrueColor-first with ANSI 256 fallback via term color conversion.

import ../term/types/[core, style]
import ../buffer

export core, style, buffer

# =============================================================================
# Tokyo Night Night Palette
# =============================================================================

# HUD Colors (Tokyo Night)
const
  HudBgColor* = RgbColor(r: 26, g: 27, b: 38)   ## #1a1b26
  HudFgColor* = RgbColor(r: 192, g: 202, b: 245) ## #c0caf5
  HudBorderColor* = RgbColor(r: 65, g: 72, b: 104) ## #414868

# Main Canvas Colors
const
  CanvasBgColor* = RgbColor(r: 26, g: 27, b: 38)   ## #1a1b26
  CanvasFgColor* = RgbColor(r: 192, g: 202, b: 245) ## #c0caf5
  CanvasDimColor* = RgbColor(r: 86, g: 95, b: 137)  ## #565f89
  CanvasFogColor* = RgbColor(r: 65, g: 72, b: 104)  ## #414868
  TrueBlackColor* = RgbColor(r: 22, g: 22, b: 30)   ## #16161e
  ModalDimBgColor* = RgbColor(r: 10, g: 10, b: 14)   ## #0a0a0e

# Status Colors
const
  AlertColor* = RgbColor(r: 247, g: 118, b: 142)    ## #f7768e
  SelectedBgColor* = RgbColor(r: 122, g: 162, b: 247) ## #7aa2f7
  SelectedFgColor* = RgbColor(r: 26, g: 27, b: 38)  ## #1a1b26
  DisabledColor* = RgbColor(r: 86, g: 95, b: 137)   ## #565f89

# Delta/Change Colors
const
  PositiveColor* = RgbColor(r: 158, g: 206, b: 106) ## #9ece6a
  NegativeColor* = RgbColor(r: 247, g: 118, b: 142) ## #f7768e
  NeutralColor* = RgbColor(r: 192, g: 202, b: 245)  ## #c0caf5

# Special Status Colors
const
  PrestigeColor* = RgbColor(r: 224, g: 175, b: 104) ## #e0af68
  TreasuryColor* = RgbColor(r: 224, g: 175, b: 104) ## #e0af68
  ProductionColor* = RgbColor(r: 125, g: 207, b: 255) ## #7dcfff

# Diplomatic Status Colors
const
  NeutralStatusColor* = RgbColor(r: 192, g: 202, b: 245) ## #c0caf5
  HostileStatusColor* = RgbColor(r: 224, g: 175, b: 104) ## #e0af68
  EnemyStatusColor* = RgbColor(r: 247, g: 118, b: 142)   ## #f7768e
  EliminatedColor* = RgbColor(r: 86, g: 95, b: 137)      ## #565f89

# Command Dock Colors
const
  DockBgColor* = RgbColor(r: 26, g: 27, b: 38)   ## #1a1b26
  DockFgColor* = RgbColor(r: 192, g: 202, b: 245) ## #c0caf5
  DockKeyColor* = RgbColor(r: 125, g: 207, b: 255) ## #7dcfff
  DockSeparatorColor* = RgbColor(r: 65, g: 72, b: 104) ## #414868

# Breadcrumb Colors
const
  BreadcrumbFgColor* = RgbColor(r: 86, g: 95, b: 137)    ## #565f89
  BreadcrumbActiveColor* = RgbColor(r: 192, g: 202, b: 245) ## #c0caf5
  BreadcrumbSeparatorColor* = RgbColor(r: 86, g: 95, b: 137) ## #565f89

# =============================================================================
# CellStyle Presets
# =============================================================================

proc hudStyle*(): CellStyle =
  ## HUD strip style (amber on navy)
  CellStyle(
    fg: color(HudFgColor),
    bg: color(HudBgColor),
    attrs: {}
  )

proc hudBoldStyle*(): CellStyle =
  ## HUD strip bold style
  CellStyle(
    fg: color(HudFgColor),
    bg: color(HudBgColor),
    attrs: {StyleAttr.Bold}
  )

proc hudDimStyle*(): CellStyle =
  ## HUD strip dim style for labels
  CellStyle(
    fg: color(CanvasDimColor),
    bg: color(HudBgColor),
    attrs: {}
  )

proc hudAlertStyle*(): CellStyle =
  ## HUD alert indicator style
  CellStyle(
    fg: color(AlertColor),
    bg: color(HudBgColor),
    attrs: {StyleAttr.Bold}
  )

proc hudPrestigeStyle*(): CellStyle =
  ## HUD prestige display style
  CellStyle(
    fg: color(PrestigeColor),
    bg: color(HudBgColor),
    attrs: {StyleAttr.Bold}
  )

proc canvasStyle*(): CellStyle =
  ## Main canvas default style
  CellStyle(
    fg: color(CanvasFgColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )

proc canvasDimStyle*(): CellStyle =
  ## Canvas dim/secondary text
  CellStyle(
    fg: color(CanvasDimColor),
    bg: color(CanvasBgColor),
    attrs: {}
  )

proc modalBgStyle*(): CellStyle =
  ## Modal background style (Tokyo Night darker bg)
  CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )

proc modalDimStyle*(): CellStyle =
  ## Modal dim/secondary text (darker bg)
  CellStyle(
    fg: color(CanvasDimColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )

proc modalBorderStyle*(): CellStyle =
  ## Modal border style (darker bg)
  CellStyle(
    fg: color(HudBorderColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )

proc modalDimOverlayStyle*(): CellStyle =
  ## Dim overlay for behind modals
  CellStyle(
    fg: color(ModalDimBgColor),
    bg: color(ModalDimBgColor),
    attrs: {}
  )

proc canvasBoldStyle*(): CellStyle =
  ## Canvas bold/header text
  CellStyle(
    fg: color(CanvasFgColor),
    bg: color(CanvasBgColor),
    attrs: {StyleAttr.Bold}
  )

proc canvasHeaderStyle*(): CellStyle =
  ## Canvas section header style
  CellStyle(
    fg: color(SelectedBgColor),
    bg: color(CanvasBgColor),
    attrs: {StyleAttr.Bold}
  )

proc selectedStyle*(): CellStyle =
  ## Selected item style (black on cyan)
  CellStyle(
    fg: color(SelectedFgColor),
    bg: color(SelectedBgColor),
    attrs: {StyleAttr.Bold}
  )

proc alertStyle*(): CellStyle =
  ## Alert/warning style
  CellStyle(
    fg: color(AlertColor),
    attrs: {StyleAttr.Bold}
  )

proc positiveStyle*(): CellStyle =
  ## Positive delta style (green)
  CellStyle(
    fg: color(PositiveColor),
    attrs: {}
  )

proc negativeStyle*(): CellStyle =
  ## Negative delta style (red)
  CellStyle(
    fg: color(NegativeColor),
    attrs: {}
  )

proc prestigeStyle*(): CellStyle =
  ## Prestige value style
  CellStyle(
    fg: color(PrestigeColor),
    attrs: {StyleAttr.Bold}
  )

proc dockStyle*(): CellStyle =
  ## Command dock default style
  CellStyle(
    fg: color(DockFgColor),
    bg: color(DockBgColor),
    attrs: {}
  )

proc dockKeyStyle*(): CellStyle =
  ## Command dock hotkey style
  CellStyle(
    fg: color(DockKeyColor),
    bg: color(DockBgColor),
    attrs: {StyleAttr.Bold}
  )

proc dockDimStyle*(): CellStyle =
  ## Command dock dim style for brackets
  CellStyle(
    fg: color(CanvasDimColor),
    bg: color(DockBgColor),
    attrs: {}
  )

proc breadcrumbStyle*(): CellStyle =
  ## Breadcrumb inactive segment
  CellStyle(
    fg: color(BreadcrumbFgColor),
    attrs: {}
  )

proc breadcrumbActiveStyle*(): CellStyle =
  ## Breadcrumb active/current segment
  CellStyle(
    fg: color(BreadcrumbActiveColor),
    attrs: {}
  )

proc breadcrumbSeparatorStyle*(): CellStyle =
  ## Breadcrumb separator (>)
  CellStyle(
    fg: color(BreadcrumbSeparatorColor),
    attrs: {}
  )

# =============================================================================
# Border Styles for EC Theme
# =============================================================================

proc hudBorderStyle*(): CellStyle =
  ## HUD double-border style
  CellStyle(
    fg: color(HudBorderColor),
    bg: color(HudBgColor),
    attrs: {}
  )

proc primaryBorderStyle*(): CellStyle =
  ## Primary panel border (double-line)
  CellStyle(
    fg: color(HudBorderColor),
    attrs: {}
  )

proc dialogBorderStyle*(): CellStyle =
  ## Dialog/overlay border (single-line)
  CellStyle(
    fg: color(CanvasDimColor),
    attrs: {}
  )

# =============================================================================
# Glyphs (from spec section 3)
# =============================================================================

const
  GlyphPrestige* = "★"        ## Prestige indicator
  GlyphOk* = "●"              ## OK / Neutral status
  GlyphWarning* = "⚠"         ## Needs Attention / Hostile
  GlyphEnemy* = "⚔"           ## Enemy diplomatic status
  GlyphEliminated* = "☠"      ## Eliminated house
  GlyphReserve* = "RSV"       ## Reserve status
  GlyphMothball* = "MTB"      ## Mothballed status
  GlyphTrendUp* = "▲"         ## Trend up
  GlyphTrendDown* = "▼"       ## Trend down
  GlyphUnread* = "✉"          ## Unread message/report
  GlyphProgressFull* = "▓"    ## Progress bar filled
  GlyphProgressEmpty* = "░"   ## Progress bar empty
  GlyphBreadcrumbSep* = ">"   ## Breadcrumb separator
  GlyphTurnMarker* = "▸"      ## Turn indicator

# =============================================================================
# Diplomatic Status Display
# =============================================================================

type
  DiplomaticDisplay* = object
    glyph*: string
    label*: string
    style*: CellStyle

proc neutralDisplay*(): DiplomaticDisplay =
  DiplomaticDisplay(
    glyph: GlyphOk,
    label: "NEU",
    style: CellStyle(fg: color(NeutralStatusColor), attrs: {})
  )

proc hostileDisplay*(): DiplomaticDisplay =
  DiplomaticDisplay(
    glyph: GlyphWarning,
    label: "HOS",
    style: CellStyle(fg: color(HostileStatusColor), attrs: {})
  )

proc enemyDisplay*(): DiplomaticDisplay =
  DiplomaticDisplay(
    glyph: GlyphEnemy,
    label: "ENM",
    style: CellStyle(fg: color(EnemyStatusColor), attrs: {StyleAttr.Bold})
  )

proc eliminatedDisplay*(): DiplomaticDisplay =
  DiplomaticDisplay(
    glyph: GlyphEliminated,
    label: "ELIM",
    style: CellStyle(fg: color(EliminatedColor), attrs: {})
  )

proc youDisplay*(): DiplomaticDisplay =
  DiplomaticDisplay(
    glyph: "",
    label: "YOU",
    style: CellStyle(fg: color(PrestigeColor), attrs: {StyleAttr.Bold})
  )
