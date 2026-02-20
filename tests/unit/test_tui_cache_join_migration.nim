## Unit tests for legacy join-cache migration behavior.

import std/[unittest, os, times, strutils, options]

import ../../src/engine/types/core
import ../../src/player/state/[join_flow, tui_cache]

proc tempRoot(prefix: string): string =
  let ts = $epochTime().int64
  getTempDir() / (prefix & "_" & ts)

proc legacyJoinPath(dataDir: string, pubkey: string, gameId: string): string =
  dataDir / "players" / pubkey / "games" / (gameId & ".kdl")

proc ensureLegacyDir(dataDir: string, pubkey: string) =
  createDir(dataDir)
  let playersDir = dataDir / "players"
  createDir(playersDir)
  let pubkeyDir = playersDir / pubkey
  createDir(pubkeyDir)
  createDir(pubkeyDir / "games")

suite "TuiCache Join Migration":
  test "writeJoinCache writes optional game name":
    let root = tempRoot("ec4x_join_write")
    let dataDir = root / "data"
    let pubkey = "player-pubkey"
    let gameId = "5ca68963-4181-491e-942b-c5bab7dc08f7"
    defer:
      if dirExists(root):
        removeDir(root)

    writeJoinCache(dataDir, pubkey, gameId, HouseId(1),
      "relic-desk-zippers")

    let path = legacyJoinPath(dataDir, pubkey, gameId)
    check fileExists(path)
    let content = readFile(path)
    check content.contains("join-cache")
    check content.contains("name \"relic-desk-zippers\"")

  test "migration keeps existing cached name when legacy name missing":
    let root = tempRoot("ec4x_join_migrate_keep")
    let dataDir = root / "data"
    let cachePath = root / "cache.db"
    let pubkey = "player-pubkey"
    let gameId = "5ca68963-4181-491e-942b-c5bab7dc08f7"
    let slug = "relic-desk-zippers"
    defer:
      if dirExists(root):
        removeDir(root)

    ensureLegacyDir(dataDir, pubkey)
    let legacyPath = legacyJoinPath(dataDir, pubkey, gameId)
    writeFile(legacyPath,
      "join-cache game=\"" & gameId & "\" house=(HouseId)1 " &
      "pubkey=\"" & pubkey & "\"\n")

    let cache = openTuiCacheAt(cachePath)
    defer: cache.close()
    cache.upsertGame(gameId, slug, 0, "active")
    cache.migrateOldJoinCache(dataDir, pubkey)

    let cachedGame = cache.getGame(gameId)
    check cachedGame.isSome
    check cachedGame.get().name == slug
    check not fileExists(legacyPath)

  test "migration uses legacy name when present":
    let root = tempRoot("ec4x_join_migrate_name")
    let dataDir = root / "data"
    let cachePath = root / "cache.db"
    let pubkey = "player-pubkey"
    let gameId = "5ca68963-4181-491e-942b-c5bab7dc08f7"
    let legacyName = "frost-harbor-signal"
    defer:
      if dirExists(root):
        removeDir(root)

    ensureLegacyDir(dataDir, pubkey)
    let legacyPath = legacyJoinPath(dataDir, pubkey, gameId)
    writeFile(legacyPath,
      "join-cache game=\"" & gameId & "\" house=(HouseId)1 " &
      "pubkey=\"" & pubkey & "\" {\n" &
      "  name \"" & legacyName & "\"\n" &
      "}\n")

    let cache = openTuiCacheAt(cachePath)
    defer: cache.close()
    cache.migrateOldJoinCache(dataDir, pubkey)

    let cachedGame = cache.getGame(gameId)
    check cachedGame.isSome
    check cachedGame.get().name == legacyName
    check not fileExists(legacyPath)
