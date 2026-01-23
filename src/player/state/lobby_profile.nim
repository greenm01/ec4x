## Lobby profile persistence

import std/[os, strutils]
import kdl

import ../../engine/types/core
import ../../common/logger

const
  ProfileNode = "profile"

proc profilePath*(dataDir, pubkey: string): string =
  dataDir / "players" / pubkey / "profile.kdl"

proc loadProfile*(dataDir, pubkey: string): tuple[name: string, session: bool] =
  let path = profilePath(dataDir, pubkey)
  if not fileExists(path):
    return (name: "", session: false)

  try:
    let doc = parseKdl(readFile(path))
    if doc.len == 0 or doc[0].name != ProfileNode:
      return (name: "", session: false)
    let node = doc[0]
    let name = if node.props.hasKey("name"):
                 node.props["name"].kString()
               else:
                 ""
    let session = if node.props.hasKey("session_only"):
                    node.props["session_only"].kBool()
                  else:
                    false
    (name: name, session: session)
  except CatchableError as e:
    logError("LobbyProfile", "Failed to load profile: ", e.msg)
    (name: "", session: false)

proc loadProfiles*(dataDir: string): seq[string] =
  let playersDir = dataDir / "players"
  if not dirExists(playersDir):
    return @[]

  result = @[]
  for kind, path in walkDir(playersDir):
    if kind != pcDir:
      continue
    let profileFile = path / "profile.kdl"
    if fileExists(profileFile):
      result.add(path.extractFilename)

proc saveProfile*(dataDir, pubkey, name: string, sessionOnly: bool) =
  let path = profilePath(dataDir, pubkey)
  createDir(path.parentDir)
  var line = ProfileNode & " pubkey=\"" & pubkey & "\""
  if name.len > 0:
    line.add(" name=\"" & name & "\"")
  line.add(" session_only=" & (if sessionOnly: "#true" else: "#false"))
  line.add("\n")
  writeFile(path, line)

proc activeGamesPath*(dataDir, pubkey: string): string =
  dataDir / "players" / pubkey / "games"

proc loadActiveGames*(dataDir, pubkey: string): seq[(string, HouseId)] =
  let dirPath = activeGamesPath(dataDir, pubkey)
  if not dirExists(dirPath):
    return @[]

  result = @[]
  for kind, path in walkDir(dirPath):
    if kind != pcFile or not path.endsWith(".kdl"):
      continue

    try:
      let doc = parseKdl(readFile(path))
      if doc.len == 0:
        continue
      let node = doc[0]
      if not node.props.hasKey("game") or not node.props.hasKey("house"):
        continue
      let gameId = node.props["game"].kString()
      let houseId = HouseId(node.props["house"].kInt().uint32)
      result.add((gameId, houseId))
    except CatchableError as e:
      logError("LobbyProfile", "Failed to load game cache: ", path, " ", e.msg)


