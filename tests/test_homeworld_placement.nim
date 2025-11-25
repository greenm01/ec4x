import ../src/engine/starmap
import std/[options, tables, math, strformat]

let map = starMap(4)

echo "=== 4-Player StarMap Homeworld Validation ==="
echo "Total systems: ", map.systems.len()
echo "Player count: ", map.playerCount
echo "Number of rings: ", map.numRings
echo "Hub ID: ", map.hubId
echo ""

# Check homeworld placement
echo "Player homeworlds:"
for i, systemId in map.playerSystemIds:
  let system = map.systems[systemId]
  echo "  Player ", i, ": System ", systemId
  echo "    Coordinates: (q=", system.coords.q, ", r=", system.coords.r, ")"
  echo "    Ring: ", system.ring
  echo "    Player field: ", system.player
  echo "    Neighbors: ", map.getAdjacentSystems(systemId).len
  echo ""

# Validate outer ring
var outerRingCount = 0
for system in map.systems.values:
  if system.ring == map.numRings:
    outerRingCount += 1

echo "Outer ring systems: ", outerRingCount
echo ""

# Check if all players were assigned
if map.playerSystemIds.len != 4:
  echo "ERROR: Expected 4 player systems, got ", map.playerSystemIds.len
else:
  echo "✓ All 4 players have homeworlds"

# Check if homeworlds are on outer ring
var allOnOuterRing = true
for systemId in map.playerSystemIds:
  let system = map.systems[systemId]
  if system.ring != map.numRings:
    echo "ERROR: Player homeworld ", systemId, " is on ring ", system.ring, " (expected ", map.numRings, ")"
    allOnOuterRing = false

if allOnOuterRing:
  echo "✓ All homeworlds are on outer ring"

# Check angular distribution (homeworlds should be evenly spaced)
echo ""
echo "Homeworld angular distribution:"
var angles: seq[float] = @[]
for i, systemId in map.playerSystemIds:
  let system = map.systems[systemId]
  let angle = arctan2(system.coords.r.float, system.coords.q.float) * 180.0 / PI
  angles.add(angle)
  echo "  Player ", i, fmt": angle = {angle:.1f}° (q={system.coords.q}, r={system.coords.r})"

# Check if homeworlds are in different "sectors" (90° quadrants)
echo ""
var sectors: array[4, int] = [0, 0, 0, 0]
for angle in angles:
  let normalizedAngle = if angle < 0: angle + 360.0 else: angle
  let sector = int(normalizedAngle / 90.0) mod 4
  sectors[sector] += 1

echo "Sector distribution (0-90°, 90-180°, 180-270°, 270-360°):"
for i in 0..3:
  echo "  Sector ", i, ": ", sectors[i], " homeworld(s)"

var allDifferentSectors = true
for count in sectors:
  if count > 1:
    allDifferentSectors = false
    echo "⚠  Multiple homeworlds in same sector!"
    break

if allDifferentSectors:
  echo "✓ All homeworlds in different sectors"
