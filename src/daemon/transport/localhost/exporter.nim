## Localhost Result Exporter

## Post-turn: Fog view → KDL → houses/<h>/turn_results/turn_N.kdl

import std/[os, strutils]
import nimkdl
import ../../engine/types/game_state
import ../../engine/state/iterators  # Fog views

proc exportTurnResults*(gameDir: string, turn: int, state: GameState) =
  ## Export per-house KDL results (stub)
  ## TODO: createFogOfWarView → serialize KDL
  let turnDir = gameDir / \"houses\" / \"stub\" / \"turn_results\"
  createDir(turnDir)
  let kdlPath = turnDir / &\"turn_{turn}.kdl\"
  let kdlStr = \"# Stub turn {turn} results\"  # Impl serialize
  writeFile(kdlPath, kdlStr)
  logInfo(\"Exporter\", \"Exported stub KDL to \", kdlPath)