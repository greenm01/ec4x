## Unit tests for game name resolution precedence.

import std/[unittest, options]

import ../../src/player/state/game_name_resolver

suite "Game Name Resolver":
  test "prefers non-empty event name":
    let resolved = resolveGameName(
      some("relic-desk-zippers"),
      "5ca68963-4181-491e-942b-c5bab7dc08f7",
      "cached-slug"
    )
    check resolved.name == "relic-desk-zippers"
    check resolved.source == "event"

  test "falls back to cached non-uuid when event name missing":
    let resolved = resolveGameName(
      none(string),
      "5ca68963-4181-491e-942b-c5bab7dc08f7",
      "cached-slug"
    )
    check resolved.name == "cached-slug"
    check resolved.source == "cache"

  test "falls back to gameId when cached value looks like uuid":
    let gameId = "5ca68963-4181-491e-942b-c5bab7dc08f7"
    let resolved = resolveGameName(
      none(string),
      gameId,
      "5ca68963-4181-491e-942b-c5bab7dc08f7"
    )
    check resolved.name == gameId
    check resolved.source == "gameId-fallback"

  test "treats empty event name as missing":
    let gameId = "5ca68963-4181-491e-942b-c5bab7dc08f7"
    let resolved = resolveGameName(some("  "), gameId, "cached-slug")
    check resolved.name == "cached-slug"
    check resolved.source == "cache"

  test "uuid detector catches canonical uuid":
    check isLikelyUuid("5ca68963-4181-491e-942b-c5bab7dc08f7")
    check not isLikelyUuid("relic-desk-zippers")
    check not isLikelyUuid("5ca68963-4181-491e-942b")
