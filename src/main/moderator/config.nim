## Configuration management for EC4X moderator
##
## This module handles loading and validation of game configuration
## files for the EC4X moderator application.

import std/[os, strutils]
import toml_serialization

type
  Config* = object
    ## Game configuration structure
    hostName*: string
    gameName*: string
    serverIp*: string
    port*: string
    numEmpires*: uint32

const
  configFile* = "game_config.toml"

proc checkGamePath*(dir: string): bool =
  ## Verify that the given path is a valid directory
  try:
    let info = getFileInfo(dir)
    return info.kind == pcDir
  except OSError:
    return false

proc loadConfig*(gamePath: string): Config =
  ## Load configuration from the game directory
  if not checkGamePath(gamePath):
    raise newException(IOError, "Invalid game path: " & gamePath)

  let configPath = gamePath / configFile

  if not fileExists(configPath):
    raise newException(IOError, "Configuration file not found: " & configPath)

  let configContent = readFile(configPath)
  let config = Toml.decode(configContent, Config)

  # Validate configuration
  if config.numEmpires < 2:
    raise newException(ValueError, "Minimum number of players is two")

  if config.numEmpires > 12:
    raise newException(ValueError, "Maximum number of players is twelve")

  echo "\nLoaded config file: ", configPath
  echo "Host Name: ", config.hostName
  echo "Game Name: ", config.gameName
  echo "Server IP: ", config.serverIp
  echo "Port: ", config.port
  echo "Num Empires: ", config.numEmpires

  return config

proc createDefaultConfig*(gamePath: string): Config =
  ## Create a default configuration file
  let config = Config(
    hostName: "EC4X Host",
    gameName: "New EC4X Game",
    serverIp: "127.0.0.1",
    port: "8080",
    numEmpires: 4
  )

  let configPath = gamePath / configFile
  let configContent = Toml.encode(config)
  writeFile(configPath, configContent)

  echo "Created default configuration file: ", configPath
  return config

proc validateConfig*(config: Config): bool =
  ## Validate configuration values
  result = true

  if config.hostName.len == 0:
    echo "Error: Host name cannot be empty"
    result = false

  if config.gameName.len == 0:
    echo "Error: Game name cannot be empty"
    result = false

  if config.numEmpires < 2 or config.numEmpires > 12:
    echo "Error: Number of empires must be between 2 and 12"
    result = false

  try:
    let port = parseInt(config.port)
    if port < 1 or port > 65535:
      echo "Error: Port must be between 1 and 65535"
      result = false
  except ValueError:
    echo "Error: Invalid port number"
    result = false
