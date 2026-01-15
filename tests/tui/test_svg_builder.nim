## Unit Tests: SVG Builder
##
## Tests SVG generation utilities for starmap export.

import std/[unittest, strutils, math]
import ../../src/player/svg/svg_builder
import ../../src/player/svg/node_layout

suite "SVG Builder: Node Layout":

  test "hub at origin maps to center":
    let center = point(500.0, 500.0)
    let pos = hexToPixel(0, 0, 50.0, center.x, center.y)
    check pos.x == 500.0
    check pos.y == 500.0

  test "ring 1 positions are equidistant from center":
    let center = point(500.0, 500.0)
    let scale = 50.0
    
    let ring1Coords = [(0, -1), (1, -1), (1, 0), (0, 1), (-1, 1), (-1, 0)]
    var distances: seq[float] = @[]
    
    for (q, r) in ring1Coords:
      let pos = hexToPixel(q, r, scale, center.x, center.y)
      let dx = pos.x - center.x
      let dy = pos.y - center.y
      let dist = sqrt(dx * dx + dy * dy)
      distances.add(dist)
    
    # All ring 1 positions should be approximately the same distance
    let firstDist = distances[0]
    for d in distances:
      check abs(d - firstDist) < 0.1

  test "tuple overload works":
    let center = point(500.0, 500.0)
    let pos = hexToPixel((1, -1), 50.0, center)
    check pos.x != 500.0 or pos.y != 500.0  # Should be offset from center

suite "SVG Builder: Scale Calculation":

  test "scale for small map":
    let scale = calculateScale(2, 800.0)
    check scale > 0

  test "scale for large map":
    let scale = calculateScale(5, 1000.0)
    check scale > 0

  test "larger maps have smaller scale":
    let smallScale = calculateScale(2, 800.0)
    let largeScale = calculateScale(5, 800.0)
    check largeScale < smallScale

suite "SVG Builder: House Colors":

  test "house 0 has a color":
    let color = houseColor(0)
    check color.len > 0
    check color.startsWith("#")

  test "house colors are unique":
    var seen: seq[string] = @[]
    for i in 0 ..< 12:
      let color = houseColor(i)
      check color notin seen
      seen.add(color)

  test "out of range house gets fallback":
    let color = houseColor(999)
    check color == ColorWhite

suite "SVG Builder: Element Generation":

  test "svgLine generates valid element":
    let line = svgLine(0.0, 0.0, 100.0, 100.0, "lane lane-major")
    check "<line" in line
    check "x1=" in line
    check "y1=" in line
    check "x2=" in line
    check "y2=" in line
    check "lane-major" in line

  test "svgCircle generates valid element":
    let circle = svgCircle(50.0, 50.0, 10.0, "node-hub")
    check "<circle" in circle
    check "cx=" in circle
    check "cy=" in circle
    check "r=" in circle
    check "node-hub" in circle

  test "svgCircle with style":
    let circle = svgCircle(50.0, 50.0, 10.0, "node-own", "fill: #FF0000")
    check "style=" in circle
    check "#FF0000" in circle

  test "svgText escapes special characters":
    let text = svgText(100.0, 100.0, "Test & <more>", "label")
    check "&amp;" in text
    check "&lt;" in text
    check "&gt;" in text

  test "svgGroup wraps content":
    let group = svgGroup("test-group", "  <circle/>")
    check "<g id=\"test-group\">" in group
    check "</g>" in group

suite "SVG Builder: Lane Classes":

  test "major lane class":
    check laneClass(0) == "lane lane-major"

  test "minor lane class":
    check laneClass(1) == "lane lane-minor"

  test "restricted lane class":
    check laneClass(2) == "lane lane-restricted"

suite "SVG Builder: Node Types":

  test "hub node class":
    check nodeClass(NodeType.Hub) == "node-hub"

  test "own colony node class":
    check nodeClass(NodeType.OwnColony) == "node-own"

  test "hub radius is largest":
    let hubR = nodeRadius(NodeType.Hub)
    let ownR = nodeRadius(NodeType.OwnColony)
    let neutralR = nodeRadius(NodeType.Neutral)
    check hubR > ownR
    check ownR > neutralR

  test "homeworld is larger than regular colony":
    let homeR = nodeRadius(NodeType.OwnColony, isHomeworld = true)
    let regR = nodeRadius(NodeType.OwnColony, isHomeworld = false)
    check homeR > regR

suite "SVG Builder: Complete Build":

  test "builder creates valid SVG":
    var builder = initSvgBuilder(800, 600)
    builder.add(svgCircle(400.0, 300.0, 10.0, "node-hub"))
    let svg = builder.build()
    
    check "<?xml" in svg
    check "<svg" in svg
    check "</svg>" in svg
    check "<circle" in svg

  test "builder includes styles":
    var builder = initSvgBuilder(800, 600)
    let svg = builder.build()
    
    check "<style>" in svg
    check ".lane-major" in svg
    check ".node-hub" in svg
    check ".label" in svg

  test "builder includes explicit background rect":
    var builder = initSvgBuilder(800, 600)
    let svg = builder.build()
    
    # Background should be an explicit rect, not just CSS
    check "<rect id=\"background\"" in svg
    check "fill=\"#000000\"" in svg
