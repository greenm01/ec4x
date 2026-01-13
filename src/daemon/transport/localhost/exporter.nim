## Localhost Result Exporter

## Post-turn: Basic state → KDL → houses/<h>/turn_results/turn_N.kdl

import std/[os, strutils]
import kdl
import ../../../common/logger
import ../../../engine/types/game_state
import ../../../engine/state/iterators

proc exportTurnResults*(gameDir: string, turn: int, state: GameState) =
  ## Export per-house KDL results with basic game state
  for house in state.activeHouses():
    let houseId = house.id

    let houseDir = gameDir / "houses" / $houseId.uint32
    let turnDir = houseDir / "turn_results"
    createDir(turnDir)

    let kdlPath = turnDir / ("turn_" & $turn & ".kdl")

    # Create simple KDL string
    let kdlStr = "turn_results " & $turn & "\n" &
                 "game name=\"" & state.gameName & "\" turn=" & $turn & "\n" &
                 "house id=" & $houseId.uint32 & " name=\"" & house.name & "\" treasury=" & $house.treasury & "\n"
    writeFile(kdlPath, kdlStr)
    logInfo("Exporter", "Exported KDL to ", kdlPath)