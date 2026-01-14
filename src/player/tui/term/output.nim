## Terminal output type and operations.
##
## Output represents a terminal output stream with color profile detection
## and convenience methods for screen/cursor operations.

import std/streams
import std/terminal
import types/core
import types/style as styleTypes
import constants/escape
import color
import style as stylemod
import screen as screenmod

type
  Output* = object
    ## Terminal output with profile and writer.
    profile*: Profile
    writer: Stream
    isTTY*: bool
    unsafe: bool  # Allow unsafe operations
    fgColor: Color  # Cached foreground color
    bgColor: Color  # Cached background color
    fgQueried: bool
    bgQueried: bool


# =============================================================================
# Constructors
# =============================================================================

proc initOutput*(writer: Stream,
                 profile: Profile = Profile.TrueColor,
                 isTTY: bool = false,
                 unsafe: bool = false): Output =
  ## Create a new Output with explicit settings.
  Output(
    writer: writer,
    profile: profile,
    isTTY: isTTY,
    unsafe: unsafe,
    fgColor: noColor(),
    bgColor: noColor(),
    fgQueried: false,
    bgQueried: false
  )

proc newOutput*(writer: Stream): Output =
  ## Create Output with auto-detected profile.
  ## Profile detection is deferred to platform module.
  initOutput(writer, Profile.TrueColor, false)

proc newStdoutOutput*(): Output =
  ## Create Output for stdout with TTY detection.
  let tty = isatty(stdout)
  var s = newFileStream(stdout)
  initOutput(s, Profile.TrueColor, tty)

proc newStderrOutput*(): Output =
  ## Create Output for stderr with TTY detection.
  let tty = isatty(stderr)
  var s = newFileStream(stderr)
  initOutput(s, Profile.TrueColor, tty)


# =============================================================================
# Output Properties
# =============================================================================

proc colorProfile*(o: Output): Profile {.inline.} =
  ## Get color profile.
  o.profile

proc supportsColor*(o: Output): bool {.inline.} =
  o.profile != Profile.Ascii

proc supports256*(o: Output): bool {.inline.} =
  o.profile <= Profile.Ansi256

proc supportsTrueColor*(o: Output): bool {.inline.} =
  o.profile == Profile.TrueColor


# =============================================================================
# Writing
# =============================================================================

proc write*(o: var Output, s: string) =
  ## Write string to output.
  if o.writer != nil:
    o.writer.write(s)

proc writeLine*(o: var Output, s: string) =
  ## Write string with newline.
  o.write(s & "\n")

proc flush*(o: var Output) =
  ## Flush output stream.
  if o.writer != nil:
    o.writer.flush()


# =============================================================================
# Color/Style Methods
# =============================================================================

proc color*(o: Output, s: string): Color =
  ## Parse color string respecting profile.
  color(o.profile, s)

proc newStyle*(o: Output): styleTypes.Style =
  ## Create new style with output's profile.
  initStyle(o.profile)

proc newStyle*(o: Output, text: string): styleTypes.Style =
  ## Create styled text with output's profile.
  initStyle(text, o.profile)

proc styledText*(o: Output, text: string): styleTypes.Style {.inline.} =
  ## Alias for newStyle with text.
  o.newStyle(text)


# =============================================================================
# Screen Operations (write directly)
# =============================================================================

proc reset*(o: var Output) =
  ## Reset terminal attributes.
  o.write(screenmod.reset())

proc clearScreen*(o: var Output) =
  ## Clear screen and move cursor home.
  o.write(screenmod.clearScreen())

proc clearLine*(o: var Output) =
  ## Clear entire current line.
  o.write(screenmod.clearLine())

proc clearLineLeft*(o: var Output) =
  ## Clear from cursor to start of line.
  o.write(screenmod.clearLineLeft())

proc clearLineRight*(o: var Output) =
  ## Clear from cursor to end of line.
  o.write(screenmod.clearLineRight())

proc clearLines*(o: var Output, n: int) =
  ## Clear N lines starting from current, moving up.
  o.write(screenmod.clearLines(n))


# =============================================================================
# Cursor Operations (write directly)
# =============================================================================

proc moveCursor*(o: var Output, row, col: int) =
  ## Move cursor to position.
  o.write(screenmod.cursorPosition(row, col))

proc cursorUp*(o: var Output, n: int = 1) =
  ## Move cursor up.
  o.write(screenmod.cursorUp(n))

proc cursorDown*(o: var Output, n: int = 1) =
  ## Move cursor down.
  o.write(screenmod.cursorDown(n))

proc cursorForward*(o: var Output, n: int = 1) =
  ## Move cursor forward.
  o.write(screenmod.cursorForward(n))

proc cursorBack*(o: var Output, n: int = 1) =
  ## Move cursor back.
  o.write(screenmod.cursorBack(n))

proc cursorNextLine*(o: var Output, n: int = 1) =
  ## Move to next line.
  o.write(screenmod.cursorNextLine(n))

proc cursorPrevLine*(o: var Output, n: int = 1) =
  ## Move to previous line.
  o.write(screenmod.cursorPrevLine(n))

proc saveCursorPosition*(o: var Output) =
  ## Save cursor position.
  o.write(screenmod.saveCursorPosition())

proc restoreCursorPosition*(o: var Output) =
  ## Restore cursor position.
  o.write(screenmod.restoreCursorPosition())

proc showCursor*(o: var Output) =
  ## Show cursor.
  o.write(screenmod.showCursor())

proc hideCursor*(o: var Output) =
  ## Hide cursor.
  o.write(screenmod.hideCursor())

proc setCursorStyle*(o: var Output, style: CursorStyle) =
  ## Set cursor style.
  o.write(screenmod.setCursorStyle(style))


# =============================================================================
# Scrolling Operations
# =============================================================================

proc setScrollRegion*(o: var Output, top, bottom: int) =
  ## Set scrolling region.
  o.write(screenmod.setScrollRegion(top, bottom))

proc resetScrollRegion*(o: var Output) =
  ## Reset scrolling region.
  o.write(screenmod.resetScrollRegion())

proc scrollUp*(o: var Output, n: int = 1) =
  ## Scroll up.
  o.write(screenmod.scrollUp(n))

proc scrollDown*(o: var Output, n: int = 1) =
  ## Scroll down.
  o.write(screenmod.scrollDown(n))

proc insertLines*(o: var Output, n: int = 1) =
  ## Insert lines.
  o.write(screenmod.insertLines(n))

proc deleteLines*(o: var Output, n: int = 1) =
  ## Delete lines.
  o.write(screenmod.deleteLines(n))


# =============================================================================
# Alternate Screen
# =============================================================================

proc altScreen*(o: var Output) =
  ## Enter alternate screen.
  o.write(screenmod.altScreen())

proc exitAltScreen*(o: var Output) =
  ## Exit alternate screen.
  o.write(screenmod.exitAltScreen())

proc saveScreen*(o: var Output) =
  ## Save screen (legacy).
  o.write(screenmod.saveScreen())

proc restoreScreen*(o: var Output) =
  ## Restore screen (legacy).
  o.write(screenmod.restoreScreen())


# =============================================================================
# Mouse Tracking
# =============================================================================

proc enableMousePress*(o: var Output) =
  o.write(screenmod.enableMousePress())

proc disableMousePress*(o: var Output) =
  o.write(screenmod.disableMousePress())

proc enableMouse*(o: var Output) =
  o.write(screenmod.enableMouse())

proc disableMouse*(o: var Output) =
  o.write(screenmod.disableMouse())

proc enableMouseHilite*(o: var Output) =
  o.write(screenmod.enableMouseHilite())

proc disableMouseHilite*(o: var Output) =
  o.write(screenmod.disableMouseHilite())

proc enableMouseCellMotion*(o: var Output) =
  o.write(screenmod.enableMouseCellMotion())

proc disableMouseCellMotion*(o: var Output) =
  o.write(screenmod.disableMouseCellMotion())

proc enableMouseAllMotion*(o: var Output) =
  o.write(screenmod.enableMouseAllMotion())

proc disableMouseAllMotion*(o: var Output) =
  o.write(screenmod.disableMouseAllMotion())

proc enableMouseSgr*(o: var Output) =
  o.write(screenmod.enableMouseSgr())

proc disableMouseSgr*(o: var Output) =
  o.write(screenmod.disableMouseSgr())

proc enableMousePixels*(o: var Output) =
  o.write(screenmod.enableMousePixels())

proc disableMousePixels*(o: var Output) =
  o.write(screenmod.disableMousePixels())


# =============================================================================
# Bracketed Paste & Focus
# =============================================================================

proc enableBracketedPaste*(o: var Output) =
  o.write(screenmod.enableBracketedPaste())

proc disableBracketedPaste*(o: var Output) =
  o.write(screenmod.disableBracketedPaste())

proc enableFocusEvents*(o: var Output) =
  o.write(screenmod.enableFocusEvents())

proc disableFocusEvents*(o: var Output) =
  o.write(screenmod.disableFocusEvents())


# =============================================================================
# Window Properties
# =============================================================================

proc setWindowTitle*(o: var Output, title: string) =
  o.write(screenmod.setWindowTitle(title))

proc setTermForeground*(o: var Output, color: string) =
  o.write(screenmod.setTermForeground(color))

proc setTermBackground*(o: var Output, color: string) =
  o.write(screenmod.setTermBackground(color))

proc setTermCursorColor*(o: var Output, color: string) =
  o.write(screenmod.setTermCursorColor(color))


# =============================================================================
# OSC Features (Stubs - Need platform-specific implementation)
# =============================================================================

proc copy*(o: var Output, text: string) =
  ## Copy text to clipboard via OSC 52.
  ## TODO: Implement OSC 52 clipboard support.
  discard

proc copyPrimary*(o: var Output, text: string) =
  ## Copy text to primary selection via OSC 52.
  ## TODO: Implement OSC 52 clipboard support.
  discard

proc hyperlink*(o: Output, url, text: string): string =
  ## Create OSC 8 hyperlink.
  OSC & "8;;" & url & $BEL & text & OSC & "8;;" & $BEL

proc notify*(o: var Output, title, body: string) =
  ## Send notification via OSC 777.
  o.write(OSC & "777;notify;" & title & ";" & body & $BEL)


# =============================================================================
# Terminal Color Queries (Stubs - Need platform-specific implementation)
# =============================================================================

proc foregroundColor*(o: var Output): Color =
  ## Get terminal foreground color.
  ## TODO: Implement terminal color query.
  if not o.fgQueried:
    o.fgQueried = true
    # Query would go here
  o.fgColor

proc backgroundColor*(o: var Output): Color =
  ## Get terminal background color.
  ## TODO: Implement terminal color query.
  if not o.bgQueried:
    o.bgQueried = true
    # Query would go here
  o.bgColor

proc hasDarkBackground*(o: var Output): bool =
  ## Check if terminal has dark background.
  ## TODO: Implement based on background color query.
  true  # Default assumption
