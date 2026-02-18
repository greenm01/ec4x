## Theme and style guardrails for player TUI palette consistency.

import std/[unittest, os, strutils]

import ../../src/player/tui/styles/ec_palette

suite "TUI Palette":
  test "core Tokyo Night Night tokens are canonical":
    check CanvasBgColor == RgbColor(r: 26, g: 27, b: 38)     # #1a1b26
    check TrueBlackColor == RgbColor(r: 22, g: 22, b: 30)    # #16161e
    check CanvasFgColor == RgbColor(r: 192, g: 202, b: 245)  # #c0caf5
    check CanvasDimColor == RgbColor(r: 86, g: 95, b: 137)   # #565f89
    check HudBorderColor == RgbColor(r: 41, g: 46, b: 66)    # #292e42
    check SelectedBgColor == RgbColor(r: 130, g: 170, b: 255) # #82aaff
    check AccentColor == RgbColor(r: 192, g: 153, b: 255)    # #c099ff
    check PrestigeColor == RgbColor(r: 224, g: 175, b: 104)  # #e0af68
    check WarningColor == RgbColor(r: 255, g: 158, b: 100)   # #ff9e64
    check AlertColor == RgbColor(r: 247, g: 118, b: 142)     # #f7768e
    check PositiveColor == RgbColor(r: 158, g: 206, b: 106)  # #9ece6a
    check InfoColor == RgbColor(r: 134, g: 225, b: 252)      # #86e1fc

  test "player tui widgets avoid direct ansi color literals":
    for file in walkDirRec("src/player/tui/widget"):
      if not file.endsWith(".nim"):
        continue
      let content = readFile(file)
      check not content.contains("Ansi256Color(")
      check not content.contains("colorAnsi(")
      check not content.contains("RgbColor(r:")
