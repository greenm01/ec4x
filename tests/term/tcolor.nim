import std/unittest
import ../../src/player/tui/term/term
import ../../src/player/tui/term/color as colorMod

suite "Terminal Color Tests":

  test "Hex Color Parsing":
    check:
      parseColor("#fafafa").kind == ColorKind.Rgb
      parseColor("#fafafa").rgb == RgbColor(r: 250, g: 250, b: 250)
      parseColor("fafafa").rgb == RgbColor(r: 250, g: 250, b: 250)
      parseColor("#abc").rgb == RgbColor(r: 170, g: 187, b: 204)
      parseColor("abc").rgb == RgbColor(r: 170, g: 187, b: 204)

  test "ANSI Color Parsing":
    check:
      parseColor("7").kind == ColorKind.Ansi
      int(parseColor("7").ansi) == 7
      int(parseColor("15").ansi) == 15
      parseColor("16").kind == ColorKind.Ansi256
      int(parseColor("16").ansi256) == 16
      int(parseColor("255").ansi256) == 255

  test "Empty Color Parsing":
    check:
      parseColor("").kind == ColorKind.None

  # TODO: Fix exception catching in unittest
  # test "Invalid Color Parsing":
  #   expect InvalidColorError:
  #     discard parseColor("invalid")

  #   expect InvalidColorError:
  #     discard parseColor("#abcd")

  #   expect InvalidColorError:
  #     discard parseColor("256")

  test "Color Sequence Generation":
    let c_ansi = color(AnsiColor(1))
    let c_256 = color(Ansi256Color(91))
    let c_rgb = color(171, 205, 239)

    check:
      sequence(c_ansi, false) == "31"
      sequence(c_ansi, true) == "41"
      sequence(color(AnsiColor(9)), false) == "91"
      sequence(c_256, false) == "38;5;91"
      sequence(c_256, true) == "48;5;91"
      sequence(c_rgb, false) == "38;2;171;205;239"
      sequence(c_rgb, true) == "48;2;171;205;239"

  test "Color Conversion (Profile Downgrade)":
    let c_rgb = color(171, 205, 239) # #abcdef

    # TrueColor -> TrueColor (No change)
    let c_true = convert(c_rgb, Profile.TrueColor)
    check c_true.kind == ColorKind.Rgb
    check c_true.rgb.r == 171
    check c_true.rgb.g == 205
    check c_true.rgb.b == 239

    # TrueColor -> Ansi256 (approximates to closest 256-color)
    let c_256 = convert(c_rgb, Profile.Ansi256)
    check c_256.kind == ColorKind.Ansi256
    check int(c_256.ansi256) == 153  # #abcdef is closest to ANSI256 index 153 (#afafff)

    # TrueColor -> Ansi (approximates to closest 16-color)
    let c_ansi = convert(c_rgb, Profile.Ansi)
    check c_ansi.kind == ColorKind.Ansi
    check int(c_ansi.ansi) == 7  # White is the closest

    # TrueColor -> Ascii
    check convert(c_rgb, Profile.Ascii).isNone

  test "ANSI Profile Logic":
    let p = Profile.Ansi
    check:
      colorMod.color(p, "#e88388").kind == ColorKind.Ansi
      int(colorMod.color(p, "#e88388").ansi) == 7 # White (closest to #e88388)
      int(colorMod.color(p, "82").ansi) == 10     # Bright Green
      int(colorMod.color(p, "2").ansi) == 2       # Green