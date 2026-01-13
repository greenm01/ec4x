## EC4X Player Client (CLI)
## Submit orders and view game state via localhost transport

import std/[os, strutils, tables]
import cligen
import ./config
import ../common/logger

proc submitOrders(gameId: string, ordersFile: string, houseId = "", configPath = "config/client.kdl") =
  ## Submit orders from KDL file to daemon
  let config = loadClientConfig(configPath)
  let hidStr = if houseId != "": houseId else: config.houseId
  # Extract numeric ID from house ID string (e.g., "house1" -> "1")
  let hid = if hidStr.startsWith("house"): hidStr[5..^1] else: hidStr
  let gameDir = config.dataDir / "games" / gameId
  let ordersDir = gameDir / "orders"

  if not dirExists(ordersDir):
    createDir(ordersDir)

  let destFile = ordersDir / (hid & "_" & extractFilename(ordersFile))
  copyFile(ordersFile, destFile)
  logInfo("Client", "Submitted orders to ", destFile)

proc viewState(gameId: string, houseId = "", turn = -1, configPath = "config/client.kdl") =
  ## View game state for house
  let config = loadClientConfig(configPath)
  let hidStr = if houseId != "": houseId else: config.houseId
  # Extract numeric ID from house ID string (e.g., "house1" -> "1")
  let hid = if hidStr.startsWith("house"): hidStr[5..^1] else: hidStr
  let turnDir = config.dataDir / "games" / gameId / "houses" / hid / "turn_results"

  if not dirExists(turnDir):
    echo "No turn results found for house ", hid, " in game ", gameId
    return

  let turnNum = if turn == -1:
    # Find latest turn
    var maxTurn = 0
    for kind, path in walkDir(turnDir):
      if kind == pcFile and path.endsWith(".kdl"):
        let parts = path.splitFile().name.split('_')
        if parts.len >= 2:
          try:
            let fileTurn = parseInt(parts[1])
            if fileTurn > maxTurn: maxTurn = fileTurn
          except ValueError:
            discard
    maxTurn
  else: turn

  let kdlFile = turnDir / ("turn_" & $turnNum & ".kdl")
  if fileExists(kdlFile):
    echo readFile(kdlFile)
  else:
    echo "Turn ", turnNum, " results not found"

when isMainModule:
  dispatchMulti(
    [submitOrders, cmdName = "submit"],
    [viewState, cmdName = "view"]
  )