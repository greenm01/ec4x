## TUI Configuration File
##
## Handles reading/writing the TUI config file at ~/.config/ec4x/config.kdl
##
## Config file format:
##   config {
##     default-relay "wss://relay.ec4x.io"
##     
##     relay-aliases {
##       home "ws://192.168.1.50:8080"
##       work "wss://relay.work.example.com"
##     }
##   }
##
## The config file is optional. If it doesn't exist, defaults are used.

import std/[os, tables, strutils]
import kdl

import ../../common/logger

const
  DefaultConfigDir* = ".config/ec4x"
  ConfigFileName* = "config.kdl"

type
  TuiConfig* = object
    defaultRelay*: string
    relayAliases*: Table[string, string]

# =============================================================================
# Config Path
# =============================================================================

proc getConfigDir*(): string =
  ## Get the config directory path (XDG compliant)
  let home = getHomeDir()
  home / DefaultConfigDir

proc getConfigPath*(): string =
  ## Get the full config file path
  getConfigDir() / ConfigFileName

# =============================================================================
# Config Loading
# =============================================================================

proc loadTuiConfig*(): TuiConfig =
  ## Load the TUI config from disk
  ## Returns default config if file doesn't exist or is invalid
  result = TuiConfig(
    defaultRelay: "",
    relayAliases: initTable[string, string]()
  )
  
  let configPath = getConfigPath()
  if not fileExists(configPath):
    return
  
  try:
    let content = readFile(configPath)
    let doc = parseKdl(content)
    
    for node in doc:
      if node.name != "config":
        continue
      
      for child in node.children:
        case child.name
        of "default-relay":
          if child.args.len > 0:
            result.defaultRelay = child.args[0].kString()
        of "relay-aliases":
          for aliasNode in child.children:
            if aliasNode.args.len > 0:
              result.relayAliases[aliasNode.name] = aliasNode.args[0].kString()
        else:
          discard
  except CatchableError as e:
    logWarn("TuiConfig", "Failed to parse config: ", e.msg)

proc saveTuiConfig*(config: TuiConfig) =
  ## Save the TUI config to disk
  let configDir = getConfigDir()
  createDir(configDir)
  
  var content = "config {\n"
  
  if config.defaultRelay.len > 0:
    content.add("  default-relay \"" & config.defaultRelay & "\"\n")
  
  if config.relayAliases.len > 0:
    content.add("  \n")
    content.add("  relay-aliases {\n")
    for alias, url in config.relayAliases:
      content.add("    " & alias & " \"" & url & "\"\n")
    content.add("  }\n")
  
  content.add("}\n")
  
  let configPath = getConfigPath()
  writeFile(configPath, content)
  logInfo("TuiConfig", "Saved config to: ", configPath)

# =============================================================================
# Relay Resolution
# =============================================================================

proc resolveRelayAlias*(config: TuiConfig, aliasOrUrl: string): string =
  ## Resolve a relay alias to its URL
  ## If not an alias, returns the input unchanged
  if config.relayAliases.hasKey(aliasOrUrl):
    config.relayAliases[aliasOrUrl]
  else:
    aliasOrUrl

proc getDefaultRelay*(config: TuiConfig): string =
  ## Get the default relay URL
  config.defaultRelay

# =============================================================================
# Config Helpers
# =============================================================================

proc setDefaultRelay*(config: var TuiConfig, relayUrl: string) =
  ## Set the default relay URL
  config.defaultRelay = relayUrl

proc addRelayAlias*(config: var TuiConfig, alias, relayUrl: string) =
  ## Add or update a relay alias
  config.relayAliases[alias] = relayUrl

proc removeRelayAlias*(config: var TuiConfig, alias: string) =
  ## Remove a relay alias
  config.relayAliases.del(alias)

proc hasRelayAlias*(config: TuiConfig, alias: string): bool =
  ## Check if a relay alias exists
  config.relayAliases.hasKey(alias)
