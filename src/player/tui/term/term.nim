## Terminal environment library for Nim.
##
## A port of the Go termenv library providing:
## - Terminal color profile detection
## - ANSI color support (16, 256, and true color)
## - Text styling (bold, italic, underline, etc.)
## - Screen and cursor operations
## - Mouse tracking
## - Clipboard (osc 52)
## - Hyperlinks (osc 8)
##
## Usage:
##   import term
##
##   # Create styled text
##   let style = newStyle().bold().fg("#ff0000")
##   echo style.styled("Hello, World!")
##
##   # Use output for terminal operations
##   var out = newStdoutOutput()
##   out.clearScreen()
##   out.moveCursor(10, 5)
##   out.write(style.styled("Centered text"))

# Re-export types
import types/core
export core.Profile, core.TermError, core.StatusReportError, core.InvalidColorError
export core.NoColor, core.AnsiColor, core.Ansi256Color, core.RgbColor
export core.ColorKind, core.Color
export core.noColor, core.color, core.isNone
export core.name, core.supportsColor, core.supports256, core.supportsTrueColor
export core.isBright, core.isStandard, core.isCube, core.isGrayscale
export core.rgb, core.fromStdColor, core.toStdColor

import types/style
export style.StyleAttr, style.Style
export style.initStyle, style.hasForeground, style.hasBackground
export style.hasAttrs, style.isEmpty

import types/screen
export screen.EraseMode, screen.MouseMode, screen.CursorStyle
export screen.BracketedPasteState

# Re-export constants
import constants/escape
export escape.esc, escape.bel, escape.csi, escape.osc, escape.st
export escape.resetSeq
export escape.sgrForeground, escape.sgrBackground
export escape.sgrReset, escape.sgrBold, escape.sgrFaint, escape.sgrItalic
export escape.sgrUnderline, escape.sgrBlink, escape.sgrReverse
export escape.sgrCrossOut, escape.sgrOverline

import constants/ansi
export ansi.Black, ansi.Red, ansi.Green, ansi.Yellow
export ansi.Blue, ansi.Magenta, ansi.Cyan, ansi.White
export ansi.BrightBlack, ansi.BrightRed, ansi.BrightGreen, ansi.BrightYellow
export ansi.BrightBlue, ansi.BrightMagenta, ansi.BrightCyan, ansi.BrightWhite
export ansi.Gray, ansi.Grey, ansi.DarkGray, ansi.DarkGrey
export ansi.LightGray, ansi.LightGrey
export ansi.AnsiHexTable, ansi.toHex, ansi.toRgb

# Re-export color operations
import color
export color.sequence, color.parseColor, color.colorDistance
export color.toAnsi256, color.toAnsi, color.convert

# Re-export style builder
import style as stylemod
export stylemod.withText, stylemod.foreground, stylemod.background
export stylemod.fg, stylemod.bg
export stylemod.bold, stylemod.faint, stylemod.italic, stylemod.underline
export stylemod.blink, stylemod.reverse, stylemod.crossOut, stylemod.overline
export stylemod.strikethrough
export stylemod.renderSequence, stylemod.render, stylemod.styled
export stylemod.styledText, stylemod.newStyle, stylemod.width
export stylemod.`$`

# Re-export screen operations
import screen as screenmod
export screenmod.cursorUp, screenmod.cursorDown
export screenmod.cursorForward, screenmod.cursorBack
export screenmod.cursorNextLine, screenmod.cursorPrevLine
export screenmod.cursorColumn, screenmod.cursorPosition, screenmod.moveCursor
export screenmod.cursorHome
export screenmod.saveCursorPosition, screenmod.restoreCursorPosition
export screenmod.saveCursorPositionDEC, screenmod.restoreCursorPositionDEC
export screenmod.showCursor, screenmod.hideCursor, screenmod.setCursorStyle
export screenmod.eraseDisplay, screenmod.clearScreen
export screenmod.clearToEnd, screenmod.clearToStart, screenmod.clearScrollback
export screenmod.eraseLine, screenmod.clearLine
export screenmod.clearLineRight, screenmod.clearLineLeft, screenmod.clearLines
export screenmod.scrollUp, screenmod.scrollDown
export screenmod.setScrollRegion, screenmod.resetScrollRegion
export screenmod.insertLines, screenmod.deleteLines
export screenmod.insertChars, screenmod.deleteChars
export screenmod.altScreen, screenmod.exitAltScreen
export screenmod.enableKittyKeys, screenmod.disableKittyKeys
export screenmod.saveScreen, screenmod.restoreScreen
export screenmod.enableMousePress, screenmod.disableMousePress
export screenmod.enableMouse, screenmod.disableMouse
export screenmod.enableMouseHilite, screenmod.disableMouseHilite
export screenmod.enableMouseCellMotion, screenmod.disableMouseCellMotion
export screenmod.enableMouseAllMotion, screenmod.disableMouseAllMotion
export screenmod.enableMouseSgr, screenmod.disableMouseSgr
export screenmod.enableMousePixels, screenmod.disableMousePixels
export screenmod.enableBracketedPaste, screenmod.disableBracketedPaste
export screenmod.enableFocusEvents, screenmod.disableFocusEvents
export screenmod.setWindowTitle, screenmod.setIconName
export screenmod.setWindowTitleAndIcon
export screenmod.setTermForeground, screenmod.setTermBackground
export screenmod.setTermCursorColor
export screenmod.queryTermForeground, screenmod.queryTermBackground
export screenmod.queryTermCursorColor
export screenmod.reset, screenmod.softReset, screenmod.hardReset

# Re-export output
import output as outputMod
export outputMod.Output, outputMod.initOutput, outputMod.newOutput
export outputMod.newStdoutOutput, outputMod.newStderrOutput
export outputMod.colorProfile, outputMod.write, outputMod.writeLine, outputMod.flush
export outputMod.clearScreen, outputMod.moveCursor, outputMod.showCursor
export outputMod.newStyle, outputMod.hyperlink, outputMod.notify
# Note: Other Output methods are not re-exported; use Output object directly

# Re-export platform detection
import platform
export platform.envNoColor, platform.envForceColor, platform.envCliColor
export platform.detectProfile, platform.envColorProfile
