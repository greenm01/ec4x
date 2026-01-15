## SVG file export - writes SVG to disk
##
## Handles file I/O for SVG starmap export, including directory
## creation and path management.

import std/[os, strformat]

const
  DefaultBaseDir = ".ec4x"
  MapsSubdir = "maps"

proc getExportDir*(gameId: string): string =
  ## Get the export directory for a game
  ## Creates: ~/.ec4x/maps/<game_id>/
  let homeDir = getHomeDir()
  homeDir / DefaultBaseDir / MapsSubdir / gameId

proc ensureExportDir*(gameId: string): string =
  ## Ensure export directory exists, create if needed
  ## Returns the directory path
  result = getExportDir(gameId)
  if not dirExists(result):
    createDir(result)

proc getExportPath*(gameId: string, turn: int): string =
  ## Get the full path for an SVG export
  ## Returns: ~/.ec4x/maps/<game_id>/turn_<N>.svg
  let dir = getExportDir(gameId)
  dir / &"turn_{turn}.svg"

proc exportSvg*(svg: string, gameId: string, turn: int): string =
  ## Write SVG to file
  ##
  ## Args:
  ##   svg: SVG content string
  ##   gameId: Game identifier
  ##   turn: Current turn number
  ##
  ## Returns: Path to the written file
  discard ensureExportDir(gameId)
  result = getExportPath(gameId, turn)
  writeFile(result, svg)

proc openInViewer*(path: string): bool =
  ## Attempt to open file in default viewer
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
