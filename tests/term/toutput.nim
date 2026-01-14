import std/[unittest, streams, os, strutils]
import ../../src/player/tui/term/term

suite "Terminal Output Tests":

  test "Output Creation":
    let s = newStringStream()
    let output = initOutput(s, Profile.TrueColor, true)
    check:
      output.profile == Profile.TrueColor
      output.isTTY == true

  test "Stdout/Stderr Output":
    let stdout = newStdoutOutput()
    let stderr = newStderrOutput()
    # Just check they don't crash
    check true

  test "Profile Detection":
    # Save original environment
    let origTerm = getEnv("TERM")
    let origColorterm = getEnv("COLORTERM")
    
    # Test TrueColor detection
    putEnv("TERM", "xterm-256color")
    putEnv("COLORTERM", "truecolor")
    check detectProfile() == Profile.TrueColor

    # Test ANSI256 (non-truecolor term)
    delEnv("COLORTERM")
    putEnv("TERM", "screen-256color")
    check detectProfile() == Profile.Ansi256

    # Test ANSI
    putEnv("TERM", "xterm-color")
    check detectProfile() == Profile.Ansi

    # Test Ascii (NO_COLOR)
    putEnv("NO_COLOR", "1")
    check detectProfile() == Profile.Ascii

    # Restore
    delEnv("NO_COLOR")
    if origColorterm != "":
      putEnv("COLORTERM", origColorterm)
    else:
      delEnv("COLORTERM")
    if origTerm != "":
      putEnv("TERM", origTerm)

  test "Output Writing":
    let s = newStringStream()
    var output = initOutput(s)

    output.write("test")
    check s.getPosition == 4
    s.setPosition(0)
    check s.readAll() == "test"

  test "Output Convenience Methods":
    let s = newStringStream()
    var output = initOutput(s)

    output.clearScreen()
    output.moveCursor(10, 5)
    output.showCursor()

    s.setPosition(0)
    let result = s.readAll()
    check:
      "\x1b[2J\x1b[1;1H" in result  # clearScreen
      "\x1b[10;5H" in result        # moveCursor
      "\x1b[?25h" in result         # showCursor

  test "Style Creation":
    let s = newStringStream()
    var output = initOutput(s, Profile.TrueColor)

    let style = output.newStyle("test").bold().fg("#ff0000")
    check:
      style.text == "test"
      style.attrs == {StyleAttr.Bold}
      style.fg.kind == ColorKind.Rgb
      style.fg.rgb == RgbColor(r: 255, g: 0, b: 0)

  test "Hyperlink Generation":
    let s = newStringStream()
    var output = initOutput(s)

    let link = output.hyperlink("http://example.com", "click me")
    check link == "\x1b]8;;http://example.com\x1b\\click me\x1b]8;;\x1b\\"

  test "Notification Generation":
    let s = newStringStream()
    var output = initOutput(s)

    output.notify("Title", "Body")
    s.setPosition(0)
    check s.readAll() == "\x1b]777;notify;Title;Body\a"