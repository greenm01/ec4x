## Theme and style guardrails for player TUI palette consistency.

import std/[unittest, os, strutils]

import ../../src/player/tui/styles/ec_palette
import ../../src/player/tui/widget/modal
import ../../src/player/tui/widget/table
import ../../src/player/tui/widget/frame
import ../../src/player/tui/widget/text/text_pkg
import ../../src/player/tui/layout/rect
import ../../src/player/tui/buffer
import ../../src/player/tui/term/color

suite "TUI Palette":
  test "core Tokyo Night Night tokens are canonical":
    check CanvasBgColor == RgbColor(r: 26, g: 27, b: 38)     # #1a1b26
    check TrueBlackColor == RgbColor(r: 22, g: 22, b: 30)    # #16161e
    check CanvasFgColor == RgbColor(r: 192, g: 202, b: 245)  # #c0caf5
    check CanvasDimColor == RgbColor(r: 86, g: 95, b: 137)   # #565f89
    check PrimaryBorderColor == RgbColor(r: 31, g: 59, b: 138) # #1f3b8a
    check OuterBorderColor == RgbColor(r: 31, g: 59, b: 138) # #1f3b8a
    check SecondaryBorderColor == RgbColor(r: 86, g: 95, b: 137) # #565f89
    check InnerBorderColor == RgbColor(r: 86, g: 95, b: 137) # #565f89
    check TableBorderColor == RgbColor(r: 115, g: 122, b: 162) # #737aa2
    check TableGridColor == RgbColor(r: 115, g: 122, b: 162) # #737aa2
    check PanelTitleColor == RgbColor(r: 192, g: 202, b: 245) # #c0caf5
    check ModalTitleColor == RgbColor(r: 192, g: 202, b: 245) # #c0caf5
    check TableHeaderColor == RgbColor(r: 192, g: 202, b: 245) # #c0caf5
    check HudBorderColor == RgbColor(r: 65, g: 72, b: 104) # #414868
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

  test "modal backdrop fills surrounding area when enabled":
    var buf = initBuffer(24, 12)
    buf.fillArea(rect(0, 0, 24, 12), " ", canvasStyle())
    let m = newModal()
      .showBackdrop(true)
      .backdropMargin(1)
      .bgStyle(modalBgStyle())
    let area = rect(8, 4, 8, 4)
    m.render(area, buf)
    let outside = buf.get(7, 3)
    check outside.style.bg == color(ModalDimBgColor)

  test "modal default border uses primary border color":
    var buf = initBuffer(24, 12)
    buf.fillArea(rect(0, 0, 24, 12), " ", canvasStyle())
    let m = newModal().bgStyle(modalBgStyle())
    let area = rect(8, 4, 8, 4)
    m.render(area, buf)
    let corner = buf.get(8, 4)
    check corner.style.fg == color(OuterBorderColor)

  test "border role helpers map focus states to semantic styles":
    check panelBorderStyle(false) == outerBorderStyle()
    check panelBorderStyle(true) == focusBorderStyle()
    check modalPanelBorderStyle(false) == modalBorderStyle()
    check modalPanelBorderStyle(true) == focusBorderStyle()
    check nestedPanelBorderStyle(false) == modalBorderStyle()
    check nestedPanelBorderStyle(true) == accentBorderStyle()
    check tableGridStyle().fg == color(TableGridColor)
    check innerBorderStyle().fg == color(InnerBorderColor)
    check panelTitleStyle().fg == color(PanelTitleColor)
    check modalTitleStyle().fg == color(ModalTitleColor)
    check tableHeaderStyle().fg == color(TableHeaderColor)

  test "table default separators use table grid style":
    let t = table([tableColumn("A", 4)])
    check t.separatorStyle == tableGridStyle()
    check t.headerStyle == tableHeaderStyle()

  test "frame titles can use fg distinct from border fg":
    var buf = initBuffer(24, 8)
    buf.fillArea(rect(0, 0, 24, 8), " ", canvasStyle())
    let f = bordered()
      .title("TITLE")
      .titleStyle(panelTitleStyle())
      .borderStyle(outerBorderStyle())
    let area = rect(2, 1, 20, 6)
    f.render(area, buf)
    let corner = buf.get(area.x, area.y)
    let title = buf.get(area.x + 1, area.y)
    check corner.style.fg == color(OuterBorderColor)
    check title.style.fg == color(PanelTitleColor)
    check corner.style.fg != title.style.fg

  test "frame title style precedence is titles then line then span":
    var buf = initBuffer(24, 8)
    buf.fillArea(rect(0, 0, 24, 8), " ", canvasStyle())
    var titleLine = line("X")
    titleLine = titleLine.style(CellStyle(fg: color(InfoColor), attrs: {}))
    let f1 = bordered()
      .title(titleLine)
      .titleStyle(panelTitleStyle())
      .borderStyle(outerBorderStyle())
    let area1 = rect(1, 1, 10, 5)
    f1.render(area1, buf)
    check buf.get(area1.x + 1, area1.y).style.fg == color(InfoColor)

    let spanStyle = CellStyle(fg: color(AlertColor), attrs: {})
    let f2 = bordered()
      .title(line(span("Y", spanStyle)).style(
        CellStyle(fg: color(InfoColor), attrs: {})
      ))
      .titleStyle(panelTitleStyle())
      .borderStyle(outerBorderStyle())
    let area2 = rect(12, 1, 10, 5)
    f2.render(area2, buf)
    check buf.get(area2.x + 1, area2.y).style.fg == color(AlertColor)

  test "border roles remain distinct in ansi256 conversion":
    let p = int(toAnsi256(PrimaryBorderColor))
    let s = int(toAnsi256(SecondaryBorderColor))
    let tb = int(toAnsi256(TableBorderColor))
    check p != s
    check p != tb
    check s != tb
