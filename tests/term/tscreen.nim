import std/unittest
import ../../src/player/tui/term/term

suite "Terminal Screen Operations":

  test "Cursor Movement":
    check:
      cursorUp(8) == "\x1b[8A"
      cursorDown(8) == "\x1b[8B"
      cursorForward(8) == "\x1b[8C"
      cursorBack(8) == "\x1b[8D"
      cursorNextLine(8) == "\x1b[8E"
      cursorPrevLine(8) == "\x1b[8F"
      cursorColumn(16) == "\x1b[16G"
      cursorPosition(16, 8) == "\x1b[16;8H"

  test "Cursor Save/Restore":
    check:
      saveCursorPosition() == "\x1b[s"
      restoreCursorPosition() == "\x1b[u"

  test "Cursor Visibility":
    check:
      showCursor() == "\x1b[?25h"
      hideCursor() == "\x1b[?25l"

  test "Screen Clearing":
    check:
      clearScreen() == "\x1b[2J\x1b[1;1H"
      clearToEnd() == "\x1b[0J"
      clearToStart() == "\x1b[1J"
      clearScrollback() == "\x1b[3J"
      clearLine() == "\x1b[2K"
      clearLineRight() == "\x1b[0K"
      clearLineLeft() == "\x1b[1K"

  test "Scrolling":
    check:
      scrollUp(8) == "\x1b[8S"
      scrollDown(8) == "\x1b[8T"
      setScrollRegion(16, 8) == "\x1b[16;8r"
      resetScrollRegion() == "\x1b[r"

  test "Line Operations":
    check:
      insertLines(8) == "\x1b[8L"
      deleteLines(8) == "\x1b[8M"

  test "Alternate Screen":
    check:
      altScreen() == "\x1b[?1049h"
      exitAltScreen() == "\x1b[?1049l"

  test "Mouse Tracking":
    check:
      enableMousePress() == "\x1b[?9h"
      disableMousePress() == "\x1b[?9l"
      enableMouse() == "\x1b[?1000h"
      disableMouse() == "\x1b[?1000l"
      enableMouseHilite() == "\x1b[?1001h"
      disableMouseHilite() == "\x1b[?1001l"
      enableMouseCellMotion() == "\x1b[?1002h"
      disableMouseCellMotion() == "\x1b[?1002l"
      enableMouseAllMotion() == "\x1b[?1003h"
      disableMouseAllMotion() == "\x1b[?1003l"
      enableMouseSgr() == "\x1b[?1006h"
      disableMouseSgr() == "\x1b[?1006l"
      enableMousePixels() == "\x1b[?1016h"
      disableMousePixels() == "\x1b[?1016l"

  test "Bracketed Paste":
    check:
      enableBracketedPaste() == "\x1b[?2004h"
      disableBracketedPaste() == "\x1b[?2004l"

  test "Focus Events":
    check:
      enableFocusEvents() == "\x1b[?1004h"
      disableFocusEvents() == "\x1b[?1004l"

  test "Window Properties":
    check:
      setWindowTitle("test") == "\x1b]2;test\a"
      setIconName("test") == "\x1b]1;test\a"
      setWindowTitleAndIcon("test") == "\x1b]0;test\a"

  test "Terminal Colors":
    check:
      setTermForeground("#fafafa") == "\x1b]10;#fafafa\a"
      setTermBackground("#fafafa") == "\x1b]11;#fafafa\a"
      setTermCursorColor("#fafafa") == "\x1b]12;#fafafa\a"

  test "Reset":
    check:
      reset() == "\x1b[0m"