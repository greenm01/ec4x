## Borders - Border types and character sets for Block widget
##
## Defines which borders to show and what characters to use for drawing them.
## Inspired by ratatui's border system.

type
  Border* {.pure.} = enum
    ## Individual border sides.
    Top
    Right
    Bottom
    Left

  Borders* = set[Border]
    ## Set of borders to display.

  BorderType* {.pure.} = enum
    ## Predefined border character styles.
    Plain           ## ┌─┐ (default)
    Rounded         ## ╭─╮
    Double          ## ╔═╗
    Thick           ## ┏━┓
    QuadrantInside  ## ▗▄▖
    QuadrantOutside ## ▛▀▜

  BorderSet* = object
    ## Character set for drawing borders.
    ## Each field is a UTF-8 string (typically 1 grapheme).
    topLeft*: string
    topRight*: string
    bottomLeft*: string
    bottomRight*: string
    horizontal*: string  ## Top and bottom edges
    vertical*: string    ## Left and right edges

# -----------------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------------

const
  NoBorders*: Borders = {}
  AllBorders*: Borders = {Border.Top, Border.Right, Border.Bottom, Border.Left}

# Predefined border sets
const
  PlainBorderSet* = BorderSet(
    topLeft: "┌",
    topRight: "┐",
    bottomLeft: "└",
    bottomRight: "┘",
    horizontal: "─",
    vertical: "│"
  )

  RoundedBorderSet* = BorderSet(
    topLeft: "╭",
    topRight: "╮",
    bottomLeft: "╰",
    bottomRight: "╯",
    horizontal: "─",
    vertical: "│"
  )

  DoubleBorderSet* = BorderSet(
    topLeft: "╔",
    topRight: "╗",
    bottomLeft: "╚",
    bottomRight: "╝",
    horizontal: "═",
    vertical: "║"
  )

  ThickBorderSet* = BorderSet(
    topLeft: "┏",
    topRight: "┓",
    bottomLeft: "┗",
    bottomRight: "┛",
    horizontal: "━",
    vertical: "┃"
  )

  QuadrantInsideBorderSet* = BorderSet(
    topLeft: "▗",
    topRight: "▖",
    bottomLeft: "▝",
    bottomRight: "▘",
    horizontal: "▄",
    vertical: "▌"
  )

  QuadrantOutsideBorderSet* = BorderSet(
    topLeft: "▛",
    topRight: "▜",
    bottomLeft: "▙",
    bottomRight: "▟",
    horizontal: "▀",
    vertical: "▐"
  )

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------

proc borderSet*(bt: BorderType): BorderSet =
  ## Get the character set for a border type.
  case bt
  of BorderType.Plain: PlainBorderSet
  of BorderType.Rounded: RoundedBorderSet
  of BorderType.Double: DoubleBorderSet
  of BorderType.Thick: ThickBorderSet
  of BorderType.QuadrantInside: QuadrantInsideBorderSet
  of BorderType.QuadrantOutside: QuadrantOutsideBorderSet

proc custom*(topLeft, topRight, bottomLeft, bottomRight, 
             horizontal, vertical: string): BorderSet =
  ## Create a custom border character set.
  BorderSet(
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
    horizontal: horizontal,
    vertical: vertical
  )

proc hasTop*(b: Borders): bool {.inline.} =
  Border.Top in b

proc hasRight*(b: Borders): bool {.inline.} =
  Border.Right in b

proc hasBottom*(b: Borders): bool {.inline.} =
  Border.Bottom in b

proc hasLeft*(b: Borders): bool {.inline.} =
  Border.Left in b

proc isEmpty*(b: Borders): bool {.inline.} =
  b == NoBorders

proc isFull*(b: Borders): bool {.inline.} =
  b == AllBorders

# String representation
proc `$`*(bt: BorderType): string =
  case bt
  of BorderType.Plain: "Plain"
  of BorderType.Rounded: "Rounded"
  of BorderType.Double: "Double"
  of BorderType.Thick: "Thick"
  of BorderType.QuadrantInside: "QuadrantInside"
  of BorderType.QuadrantOutside: "QuadrantOutside"

proc `$`*(b: Borders): string =
  if b.isEmpty:
    return "NoBorders"
  if b.isFull:
    return "AllBorders"
  
  result = "Borders{"
  var first = true
  if b.hasTop:
    result.add("Top")
    first = false
  if b.hasRight:
    if not first: result.add(", ")
    result.add("Right")
    first = false
  if b.hasBottom:
    if not first: result.add(", ")
    result.add("Bottom")
    first = false
  if b.hasLeft:
    if not first: result.add(", ")
    result.add("Left")
  result.add("}")
