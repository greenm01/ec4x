## Visual symbols and colors for hex map rendering
##
## Defines Unicode symbols for different hex states and associated colors.
## Designed for terminal display with fallback ASCII options.

import ../../term/term
import ../../term/types/core

# Helper to create Color from ANSI 256-color index
proc colorAnsi(n: int): Color {.inline.} =
  color(Ansi256Color(n))

type
  HexSymbol* {.pure.} = enum
    ## Visual representation of hex state
    Hub         ## Central hub system
    Homeworld   ## Player's homeworld
    Colony      ## Owned colony
    EnemyColony ## Enemy-controlled colony
    Neutral     ## Uncolonized system
    Unknown     ## Fog of war (unexplored)
    Empty       ## No system at this hex

const
  # ---------------------------------------------------------------------------
  # Unicode symbols (primary)
  # ---------------------------------------------------------------------------
  
  SymHub* = "◆"         ## Diamond - central hub
  SymHomeworld* = "★"   ## Star - homeworld
  SymColony* = "●"      ## Filled circle - owned colony
  SymEnemyColony* = "○" ## Empty circle - enemy colony
  SymNeutral* = "·"     ## Middle dot - neutral/uncolonized
  SymUnknown* = "?"     ## Question mark - fog of war
  SymEmpty* = " "       ## Space - no system

  # ---------------------------------------------------------------------------
  # ASCII fallback symbols
  # ---------------------------------------------------------------------------
  
  AsciiHub* = "#"
  AsciiHomeworld* = "*"
  AsciiColony* = "@"
  AsciiEnemyColony* = "o"
  AsciiNeutral* = "."
  AsciiUnknown* = "?"
  AsciiEmpty* = " "

  # ---------------------------------------------------------------------------
  # Selection indicator
  # ---------------------------------------------------------------------------
  
  SelectLeft* = "["
  SelectRight* = "]"

# -----------------------------------------------------------------------------
# Symbol lookup
# -----------------------------------------------------------------------------

proc symbol*(s: HexSymbol, ascii: bool = false): string =
  ## Get display string for hex symbol
  if ascii:
    case s
    of HexSymbol.Hub: AsciiHub
    of HexSymbol.Homeworld: AsciiHomeworld
    of HexSymbol.Colony: AsciiColony
    of HexSymbol.EnemyColony: AsciiEnemyColony
    of HexSymbol.Neutral: AsciiNeutral
    of HexSymbol.Unknown: AsciiUnknown
    of HexSymbol.Empty: AsciiEmpty
  else:
    case s
    of HexSymbol.Hub: SymHub
    of HexSymbol.Homeworld: SymHomeworld
    of HexSymbol.Colony: SymColony
    of HexSymbol.EnemyColony: SymEnemyColony
    of HexSymbol.Neutral: SymNeutral
    of HexSymbol.Unknown: SymUnknown
    of HexSymbol.Empty: SymEmpty

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------

type
  HexColors* = object
    ## Color scheme for hex map rendering
    hub*: Style
    homeworld*: Style
    colony*: Style
    enemyColony*: Style
    neutral*: Style
    unknown*: Style
    selected*: Style
    cursor*: Style
    jumpLaneMajor*: Style
    jumpLaneMinor*: Style
    jumpLaneRestricted*: Style

proc defaultColors*(): HexColors =
  ## Default color scheme for hex map
  HexColors(
    hub: newStyle().foreground(colorAnsi(226)),        # Bright yellow
    homeworld: newStyle().foreground(colorAnsi(46)),   # Bright green
    colony: newStyle().foreground(colorAnsi(39)),      # Cyan/blue
    enemyColony: newStyle().foreground(colorAnsi(196)),# Red
    neutral: newStyle().foreground(colorAnsi(250)),    # Light gray
    unknown: newStyle().foreground(colorAnsi(240)),    # Dark gray
    selected: newStyle().foreground(colorAnsi(231))    # White
                        .bold(),
    cursor: newStyle().foreground(colorAnsi(226))      # Yellow
                      .bold(),
    jumpLaneMajor: newStyle().foreground(colorAnsi(255)),    # White
    jumpLaneMinor: newStyle().foreground(colorAnsi(245)),    # Gray
    jumpLaneRestricted: newStyle().foreground(colorAnsi(88)) # Dark red
  )

proc styleFor*(colors: HexColors, sym: HexSymbol): Style =
  ## Get style for a hex symbol type
  case sym
  of HexSymbol.Hub: colors.hub
  of HexSymbol.Homeworld: colors.homeworld
  of HexSymbol.Colony: colors.colony
  of HexSymbol.EnemyColony: colors.enemyColony
  of HexSymbol.Neutral: colors.neutral
  of HexSymbol.Unknown: colors.unknown
  of HexSymbol.Empty: newStyle()

# -----------------------------------------------------------------------------
# House colors (for multiplayer differentiation)
# -----------------------------------------------------------------------------

const
  ## Color palette for up to 8 houses
  ## Index 0 is always the viewing player (highlighted)
  HouseColorPalette*: array[8, int] = [
    39,   # Cyan (player)
    196,  # Red
    208,  # Orange
    129,  # Purple
    226,  # Yellow
    46,   # Green
    201,  # Magenta
    245,  # Gray (neutral/unknown)
  ]

proc houseStyle*(houseIndex: int): Style =
  ## Get style for a specific house (0 = viewing player)
  let colorIdx = min(houseIndex, HouseColorPalette.high)
  newStyle().foreground(colorAnsi(HouseColorPalette[colorIdx]))

# -----------------------------------------------------------------------------
# Planet class display
# -----------------------------------------------------------------------------

const
  PlanetClassNames*: array[7, string] = [
    "Extreme",   # Level I
    "Desolate",  # Level II
    "Hostile",   # Level III
    "Harsh",     # Level IV
    "Benign",    # Level V
    "Lush",      # Level VI
    "Eden",      # Level VII
  ]

  PlanetClassLevels*: array[7, string] = [
    "I", "II", "III", "IV", "V", "VI", "VII"
  ]

proc planetClassStyle*(classOrd: int): Style =
  ## Get style for planet class (0=Extreme to 6=Eden)
  ## Colors range from red (harsh) to green (hospitable)
  let colors = [
    196,  # Extreme - Red
    208,  # Desolate - Orange
    220,  # Hostile - Gold
    226,  # Harsh - Yellow
    154,  # Benign - Yellow-green
    46,   # Lush - Green
    51,   # Eden - Cyan
  ]
  let idx = clamp(classOrd, 0, 6)
  newStyle().foreground(colorAnsi(colors[idx]))

# -----------------------------------------------------------------------------
# Resource rating display
# -----------------------------------------------------------------------------

const
  ResourceRatingNames*: array[5, string] = [
    "Very Poor",
    "Poor", 
    "Abundant",
    "Rich",
    "Very Rich",
  ]

proc resourceStyle*(ratingOrd: int): Style =
  ## Get style for resource rating
  let colors = [
    240,  # Very Poor - Dark gray
    245,  # Poor - Gray
    255,  # Abundant - White
    226,  # Rich - Yellow
    46,   # Very Rich - Green
  ]
  let idx = clamp(ratingOrd, 0, 4)
  newStyle().foreground(colorAnsi(colors[idx]))

# -----------------------------------------------------------------------------
# Jump lane display
# -----------------------------------------------------------------------------

const
  LaneClassSymbols*: array[3, string] = [
    "═",  # Major - double line
    "─",  # Minor - single line
    "┄",  # Restricted - dashed
  ]

  LaneClassNames*: array[3, string] = [
    "Major",
    "Minor",
    "Restricted",
  ]
