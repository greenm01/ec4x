## Client Configuration (KDL)

import std/os
import kdl

type
  ClientConfig* = object
    dataDir*: string
    serverUrl*: string  # For future HTTP transport
    houseId*: string

proc loadClientConfig*(configPath: string = "config/client.kdl"): ClientConfig =
  ## Load client config from KDL file
  if not fileExists(configPath):
    # Default config
    return ClientConfig(
      dataDir: getCurrentDir() / "data",
      serverUrl: "http://localhost:8080",
      houseId: "house1"
    )

  let content = readFile(configPath)
  let doc = parseKdl(content)
  if doc.len == 0:
    return ClientConfig(
      dataDir: getCurrentDir() / "data",
      serverUrl: "http://localhost:8080",
      houseId: "house1"
    )

  let clientNode = doc[0]
  if clientNode.name != "client":
    # Assume flat structure like daemon
    for child in clientNode.children:
      case child.name
      of "data_dir":
        if child.args.len > 0:
          result.dataDir = child.args[0].getString()
      of "server_url":
        if child.args.len > 0:
          result.serverUrl = child.args[0].getString()
      of "house_id":
        if child.args.len > 0:
          result.houseId = child.args[0].getString()
      else:
        discard
  else:
    # Flat structure
    for child in doc:
      case child.name
      of "data_dir":
        if child.args.len > 0:
          result.dataDir = child.args[0].getString()
      of "server_url":
        if child.args.len > 0:
          result.serverUrl = child.args[0].getString()
      of "house_id":
        if child.args.len > 0:
          result.houseId = child.args[0].getString()
      else:
        discard

  # Defaults
  if result.dataDir.len == 0:
    result.dataDir = getCurrentDir() / "data"
  if result.serverUrl.len == 0:
    result.serverUrl = "http://localhost:8080"
  if result.houseId.len == 0:
    result.houseId = "house1"