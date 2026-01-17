## EC4X TUI Color Palette
##
## Classic Esterian Conquest (EC) ANSI color palette for the TUI.
## Navy-on-black foundations with amber accents, reminiscent of BBS terminals.
##
## Reference: ec-style-layout.md Section 3 "Visual Language"

import ../term/types/[core, style]
import ../buffer

export core, style, buffer

# =============================================================================
# ANSI 256-Color Definitions
# =============================================================================
#
# The EC palette uses ANSI 256 colors for maximum terminal compatibility.
# These map to the classic EC color scheme from the spec.

# HUD Colors (Tokyo Night)
const
  HudBgColor* = Ansi256Color(17)      ## Tokyo Night background (#1a1b26)
  HudFgColor* = Ansi256Color(251)     ## Tokyo Night foreground (#c0caf5)
  HudBorderColor* = Ansi256Color(60)  ## Tokyo Night border (#414868)

# Main Canvas Colors
const
  CanvasBgColor* = Ansi256Color(17)   ## Tokyo Night background
  CanvasFgColor* = Ansi256Color(251)  ## Tokyo Night foreground
  CanvasDimColor* = Ansi256Color(60)  ## Muted text (#414868)
  CanvasFogColor* = Ansi256Color(60)  ## Fog of war
  TrueBlackColor* = Ansi256Color(16)  ## True black for modals

# Status Colors
const
  AlertColor* = Ansi256Color(203)     ## Red (#f7768e)
  SelectedBgColor* = Ansi256Color(75) ## Bright accent (#7aa2f7)
  SelectedFgColor* = Ansi256Color(17) ## Background text
  DisabledColor* = Ansi256Color(60)   ## Muted

# Delta/Change Colors
const
  PositiveColor* = Ansi256Color(115)  ## Green (#9ece6a)
  NegativeColor* = Ansi256Color(203)  ## Red (#f7768e)
  NeutralColor* = Ansi256Color(251)   ## Foreground

# Special Status Colors
const
  PrestigeColor* = Ansi256Color(223)  ## Yellow (#e0af68)
  TreasuryColor* = Ansi256Color(223)  ## Yellow
  ProductionColor* = Ansi256Color(110) ## Cyan (#7dcfff)

# Diplomatic Status Colors
const
  NeutralStatusColor* = Ansi256Color(251)  ## Foreground
  HostileStatusColor* = Ansi256Color(223)  ## Yellow
  EnemyStatusColor* = Ansi256Color(203)    ## Red
  EliminatedColor* = Ansi256Color(60)      ## Muted

# Command Dock Colors
const
  DockBgColor* = Ansi256Color(17)     ## Background
  DockFgColor* = Ansi256Color(251)    ## Foreground
  DockKeyColor* = Ansi256Color(110)   ## Cyan accent
  DockSeparatorColor* = Ansi256Color(60) ## Muted

# Breadcrumb Colors
const
  BreadcrumbFgColor* = Ansi256Color(60)  ## Muted
  BreadcrumbActiveColor* = Ansi256Color(251) ## Foreground
  BreadcrumbSeparatorColor* = Ansi256Color(60)

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
    fg: color(Ansi256Color(180)),  ## Dimmer amber
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
  ## Modal background style (true black)
  CellStyle(
    fg: color(CanvasFgColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )

proc modalDimStyle*(): CellStyle =
  ## Modal dim/secondary text (true black bg)
  CellStyle(
    fg: color(CanvasDimColor),
    bg: color(TrueBlackColor),
    attrs: {}
  )

proc modalBorderStyle*(): CellStyle =
  ## Modal border style (true black bg)
  CellStyle(
    fg: color(HudBorderColor),
    bg: color(TrueBlackColor),
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
    fg: color(Ansi256Color(117)),  ## Light cyan/blue
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
    fg: color(Ansi256Color(240)),
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
    fg: color(Ansi256Color(240)),
    attrs: {}
  )

proc dialogBorderStyle*(): CellStyle =
  ## Dialog/overlay border (single-line)
  CellStyle(
    fg: color(Ansi256Color(245)),
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
