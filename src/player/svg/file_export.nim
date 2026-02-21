## SVG file export - writes SVG to disk
##
## Handles file I/O for SVG starmap export, including directory
## creation and path management.
##
## Default export path: ~/ec4x-maps/<game-slug>/turn_<N>.svg
## Override via map-export-dir in ~/.config/ec4x/config.kdl

import std/[os, strformat]

const
  DefaultExportDirName = "ec4x-maps"

proc resolveBaseDir*(configOverride: string = ""): string =
  ## Resolve the base export directory.
  ## Uses configOverride if set, otherwise ~/ec4x-maps/
  if configOverride.len > 0:
    configOverride
  else:
    getHomeDir() / DefaultExportDirName

proc getExportDir*(gameName: string,
                   configOverride: string = ""): string =
  ## Get the export directory for a game.
  ## Returns: <baseDir>/<gameName>/
  resolveBaseDir(configOverride) / gameName

proc ensureExportDir*(gameName: string,
                      configOverride: string = ""): string =
  ## Ensure export directory exists, create if needed.
  ## Returns the directory path.
  result = getExportDir(gameName, configOverride)
  if not dirExists(result):
    createDir(result)

proc getExportPath*(gameName: string, turn: int,
                    configOverride: string = ""): string =
  ## Get the full path for an SVG export.
  ## Returns: <baseDir>/<gameName>/turn_<N>.svg
  getExportDir(gameName, configOverride) / &"turn_{turn}.svg"

proc exportSvg*(svg: string, gameName: string, turn: int,
                configOverride: string = ""): string =
  ## Write SVG to file.
  ##
  ## Args:
  ##   svg: SVG content string
  ##   gameName: Game slug (e.g. velvet-mountain-copper)
  ##   turn: Current turn number
  ##   configOverride: Optional base directory from config
  ##
  ## Returns: Path to the written file
  discard ensureExportDir(gameName, configOverride)
  result = getExportPath(gameName, turn, configOverride)
  writeFile(result, svg)

proc openInViewer*(path: string): bool =
  ## Attempt to open file in default viewer.
  ## Returns true if command was executed (not necessarily successful)
  when defined(linux):
    let cmd = "xdg-open " & quoteShell(path) & " &"
    discard execShellCmd(cmd)
    true
  elif defined(macosx):
    let cmd = "open " & quoteShell(path)
    discard execShellCmd(cmd)
    true
  elif defined(windows):
    let cmd = "start \"\" " & quoteShell(path)
    discard execShellCmd(cmd)
    true
  else:
    false
