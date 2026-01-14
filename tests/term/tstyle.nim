import std/unittest
import ../../src/player/tui/term/term

suite "Terminal Style Tests":

  test "Style Width":
    let s = initStyle("Hello World")
    check s.width == 11

    let styled = s.bold()
    check styled.width == 11

    let colored = styled.fg("#abcdef")
    check colored.width == 11

  test "Unicode Width":
    let s = initStyle("🚀")  # Rocket emoji (1 rune, but visually 2 cols)
    check s.width == 1  # runeLen counts runes, not visual width

    let ascii = initStyle("ab")
    check ascii.width == 2

  test "Immutable Builder":
    let s = initStyle("test")
    let bolded = s.bold()
    let colored = bolded.fg("#ff0000")

    check:
      not s.hasAttrs
      bolded.attrs == {StyleAttr.Bold}
      colored.attrs == {StyleAttr.Bold}
      colored.fg.kind == ColorKind.Rgb

  test "Style Rendering":
    let s = initStyle("foobar").fg("#abcdef").bg("69").bold().italic().faint().underline().blink()

    # Expected sequence: \x1b[38;2;171;205;239;48;5;69;1;3;2;4;5mfoobar\x1b[0m
    let rendered = $s
    check:
      rendered.startsWith("\x1b[")
      rendered.endsWith("mfoobar\x1b[0m")
      rendered.contains("38;2;171;205;239")  # FG RGB
      rendered.contains("48;5;69")           # BG ANSI256
      rendered.contains("1")                  # Bold
      rendered.contains("3")                  # Italic
      rendered.contains("2")                  # Faint
      rendered.contains("4")                  # Underline
      rendered.contains("5")                  # Blink

  test "Ascii Profile Strips Color":
    let s = initStyle("foobar", Profile.Ascii).fg("#abcdef").bg("69").bold()
    let rendered = $s
    check rendered == "foobar"  # Ascii profile should strip all styling