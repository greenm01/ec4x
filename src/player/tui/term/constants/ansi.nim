## ANSI color definitions and 256-color palette.
##
## Defines named constants for the 16 standard ANSI colors and provides
## the complete 256-color hex lookup table.

import ../types/core

# Standard ANSI color names (0-15)
const
  Black* = AnsiColor(0)
  Red* = AnsiColor(1)
  Green* = AnsiColor(2)
  Yellow* = AnsiColor(3)
  Blue* = AnsiColor(4)
  Magenta* = AnsiColor(5)
  Cyan* = AnsiColor(6)
  White* = AnsiColor(7)
  BrightBlack* = AnsiColor(8)
  BrightRed* = AnsiColor(9)
  BrightGreen* = AnsiColor(10)
  BrightYellow* = AnsiColor(11)
  BrightBlue* = AnsiColor(12)
  BrightMagenta* = AnsiColor(13)
  BrightCyan* = AnsiColor(14)
  BrightWhite* = AnsiColor(15)

# Aliases for common alternative names
const
  Gray* = BrightBlack
  Grey* = BrightBlack
  DarkGray* = BrightBlack
  DarkGrey* = BrightBlack
  LightGray* = White
  LightGrey* = White

# Full 256-color hex table
# 0-15: Standard ANSI colors (terminal-defined, these are common defaults)
# 16-231: 6x6x6 color cube
# 232-255: Grayscale ramp
const AnsiHexTable*: array[256, string] = [
  # Standard colors (0-7)
  "#000000",  # 0: Black
  "#800000",  # 1: Red
  "#008000",  # 2: Green
  "#808000",  # 3: Yellow
  "#000080",  # 4: Blue
  "#800080",  # 5: Magenta
  "#008080",  # 6: Cyan
  "#c0c0c0",  # 7: White

  # Bright colors (8-15)
  "#808080",  # 8: Bright Black (Gray)
  "#ff0000",  # 9: Bright Red
  "#00ff00",  # 10: Bright Green
  "#ffff00",  # 11: Bright Yellow
  "#0000ff",  # 12: Bright Blue
  "#ff00ff",  # 13: Bright Magenta
  "#00ffff",  # 14: Bright Cyan
  "#ffffff",  # 15: Bright White

  # 6x6x6 color cube (16-231)
  # Each component: 0, 95, 135, 175, 215, 255 (indices 0-5)
  "#000000", "#00005f", "#000087", "#0000af", "#0000d7", "#0000ff",
  "#005f00", "#005f5f", "#005f87", "#005faf", "#005fd7", "#005fff",
  "#008700", "#00875f", "#008787", "#0087af", "#0087d7", "#0087ff",
  "#00af00", "#00af5f", "#00af87", "#00afaf", "#00afd7", "#00afff",
  "#00d700", "#00d75f", "#00d787", "#00d7af", "#00d7d7", "#00d7ff",
  "#00ff00", "#00ff5f", "#00ff87", "#00ffaf", "#00ffd7", "#00ffff",
  "#5f0000", "#5f005f", "#5f0087", "#5f00af", "#5f00d7", "#5f00ff",
  "#5f5f00", "#5f5f5f", "#5f5f87", "#5f5faf", "#5f5fd7", "#5f5fff",
  "#5f8700", "#5f875f", "#5f8787", "#5f87af", "#5f87d7", "#5f87ff",
  "#5faf00", "#5faf5f", "#5faf87", "#5fafaf", "#5fafd7", "#5fafff",
  "#5fd700", "#5fd75f", "#5fd787", "#5fd7af", "#5fd7d7", "#5fd7ff",
  "#5fff00", "#5fff5f", "#5fff87", "#5fffaf", "#5fffd7", "#5fffff",
  "#870000", "#87005f", "#870087", "#8700af", "#8700d7", "#8700ff",
  "#875f00", "#875f5f", "#875f87", "#875faf", "#875fd7", "#875fff",
  "#878700", "#87875f", "#878787", "#8787af", "#8787d7", "#8787ff",
  "#87af00", "#87af5f", "#87af87", "#87afaf", "#87afd7", "#87afff",
  "#87d700", "#87d75f", "#87d787", "#87d7af", "#87d7d7", "#87d7ff",
  "#87ff00", "#87ff5f", "#87ff87", "#87ffaf", "#87ffd7", "#87ffff",
  "#af0000", "#af005f", "#af0087", "#af00af", "#af00d7", "#af00ff",
  "#af5f00", "#af5f5f", "#af5f87", "#af5faf", "#af5fd7", "#af5fff",
  "#af8700", "#af875f", "#af8787", "#af87af", "#af87d7", "#af87ff",
  "#afaf00", "#afaf5f", "#afaf87", "#afafaf", "#afafd7", "#afafff",
  "#afd700", "#afd75f", "#afd787", "#afd7af", "#afd7d7", "#afd7ff",
  "#afff00", "#afff5f", "#afff87", "#afffaf", "#afffd7", "#afffff",
  "#d70000", "#d7005f", "#d70087", "#d700af", "#d700d7", "#d700ff",
  "#d75f00", "#d75f5f", "#d75f87", "#d75faf", "#d75fd7", "#d75fff",
  "#d78700", "#d7875f", "#d78787", "#d787af", "#d787d7", "#d787ff",
  "#d7af00", "#d7af5f", "#d7af87", "#d7afaf", "#d7afd7", "#d7afff",
  "#d7d700", "#d7d75f", "#d7d787", "#d7d7af", "#d7d7d7", "#d7d7ff",
  "#d7ff00", "#d7ff5f", "#d7ff87", "#d7ffaf", "#d7ffd7", "#d7ffff",
  "#ff0000", "#ff005f", "#ff0087", "#ff00af", "#ff00d7", "#ff00ff",
  "#ff5f00", "#ff5f5f", "#ff5f87", "#ff5faf", "#ff5fd7", "#ff5fff",
  "#ff8700", "#ff875f", "#ff8787", "#ff87af", "#ff87d7", "#ff87ff",
  "#ffaf00", "#ffaf5f", "#ffaf87", "#ffafaf", "#ffafd7", "#ffafff",
  "#ffd700", "#ffd75f", "#ffd787", "#ffd7af", "#ffd7d7", "#ffd7ff",
  "#ffff00", "#ffff5f", "#ffff87", "#ffffaf", "#ffffd7", "#ffffff",

  # Grayscale ramp (232-255)
  "#080808", "#121212", "#1c1c1c", "#262626", "#303030", "#3a3a3a",
  "#444444", "#4e4e4e", "#585858", "#626262", "#6c6c6c", "#767676",
  "#808080", "#8a8a8a", "#949494", "#9e9e9e", "#a8a8a8", "#b2b2b2",
  "#bcbcbc", "#c6c6c6", "#d0d0d0", "#dadada", "#e4e4e4", "#eeeeee"
]


proc toHex*(c: AnsiColor): string {.inline.} =
  ## Get hex color string for ANSI color.
  AnsiHexTable[int(c)]

proc toHex*(c: Ansi256Color): string {.inline.} =
  ## Get hex color string for 256-color palette.
  AnsiHexTable[int(c)]

proc toRgb*(c: AnsiColor): RgbColor =
  ## Convert ANSI color to RGB.
  rgb(AnsiHexTable[int(c)])

proc toRgb*(c: Ansi256Color): RgbColor =
  ## Convert 256-color to RGB.
  rgb(AnsiHexTable[int(c)])
