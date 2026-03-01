## submit_orders - Submit KDL orders to a game database
##
## Parses a KDL orders file and persists it to the per-game SQLite database.
## Designed for interactive debug play where you control one or both houses.
##
## Usage:
##   nim r tools/submit_orders.nim <game-slug> <orders.kdl>
##   nim r tools/submit_orders.nim <game-slug> <orders.kdl> --house N
##
## The --house flag overrides the house in the KDL file header, useful
## when controlling both houses in a debug session.
##
## Examples:
##   nim r tools/submit_orders.nim my-game orders/house1.kdl
##   nim r tools/submit_orders.nim my-game orders/house2.kdl --house 2

import std/[os, strutils, times]
import ../src/daemon/parser/kdl_commands
import ../src/daemon/persistence/writer
import ../src/engine/types/core

proc usage() =
  echo "Usage: submit_orders <game-slug> <orders.kdl> [--house N]"
  echo ""
  echo "  <game-slug>   Game identifier (matches data/games/<slug>/)"
  echo "  <orders.kdl>  Path to KDL orders file"
  echo "  --house N     Override house ID in orders file (1-based)"
  quit(1)

proc main() =
  let args = commandLineParams()
  if args.len < 2:
    usage()

  let gameSlug = args[0]
  let ordersPath = args[1]

  # Parse optional --house N override
  var houseOverride: int = -1
  var i = 2
  while i < args.len:
    if args[i] == "--house" and i + 1 < args.len:
      try:
        houseOverride = parseInt(args[i + 1])
      except ValueError:
        echo "Error: --house requires a numeric argument"
        usage()
      i += 2
    else:
      echo "Error: Unknown argument: " & args[i]
      usage()

  # Validate paths
  if not fileExists(ordersPath):
    echo "Error: Orders file not found: " & ordersPath
    quit(1)

  let dbPath = "data/games" / gameSlug / "ec4x.db"
  if not fileExists(dbPath):
    echo "Error: Game database not found: " & dbPath
    echo "       Check that '" & gameSlug & "' is a valid game slug."
    quit(1)

  # Parse orders file
  var packet =
    try:
      parseOrdersFile(ordersPath)
    except KdlParseError as e:
      echo "Error: Failed to parse orders file: " & e.msg
      quit(1)
    except IOError as e:
      echo "Error: Could not read orders file: " & e.msg
      quit(1)

  # Apply house override if requested
  if houseOverride > 0:
    packet.houseId = HouseId(houseOverride.uint32)

  # Submit to database
  let submittedAt = epochTime().int64
  try:
    saveCommandPacket(dbPath, gameSlug, packet, submittedAt)
  except Exception as e:
    echo "Error: Failed to save orders: " & e.msg
    quit(1)

  echo "Submitted orders for house " & $uint32(packet.houseId) &
    " turn " & $packet.turn &
    " -> " & dbPath

when isMainModule:
  main()
