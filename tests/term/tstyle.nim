import std/[unittest, strutils]
import ../../src/player/tui/term/term

suite "Terminal Style Tests":

  test "Style Width":
    let s = initStyle("Hello World")
    check width(s) == 11

    let styled = s.bold()
    check width(styled) == 11

    let colored = styled.fg("#abcdef")
    check width(colored) == 11

  test "Unicode Width":
    let s = initStyle("🚀")  # Rocket emoji (1 rune)
    check width(s) == 1  # runeLen counts runes

    let ascii = initStyle("ab")
    check width(ascii) == 2

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
      "38;2;171;205;239" in rendered  # FG RGB
      "48;5;69" in rendered           # BG ANSI256
      "1" in rendered                  # Bold
      "3" in rendered                  # Italic
      "2" in rendered                  # Faint
      "4" in rendered                  # Underline
      "5" in rendered                  # Blink

  test "Ascii Profile Strips Color":
    let s = initStyle("foobar", Profile.Ascii).fg("#abcdef").bg("69")
    let rendered = $s
    check rendered == "foobar"  # Ascii profile should strip all color styling