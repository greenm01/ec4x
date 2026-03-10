import std/unittest

import ../../src/player/tui/app
import ../../src/player/tui/widget/hud

suite "TUI live sync runtime":
  test "stale subscription resync triggers before periodic sync":
    check shouldRequestStaleSubscriptionResync(
      activeGameId = "game-1",
      playerStateLoaded = true,
      connected = true,
      awaitingTurnAdvanceAfterSubmit = false,
      nowTime = 100.0,
      lastActivityAt = 40.0,
      staleAfterSec = 45
    )
    check not shouldRequestPeriodicInGameSync(
      activeGameId = "game-1",
      playerStateLoaded = true,
      connected = true,
      awaitingTurnAdvanceAfterSubmit = false,
      nowTime = 100.0,
      lastSyncAt = 10.0,
      intervalMinutes = 2
    )

  test "periodic sync requires active loaded connected game":
    check shouldRequestPeriodicInGameSync(
      activeGameId = "game-1",
      playerStateLoaded = true,
      connected = true,
      awaitingTurnAdvanceAfterSubmit = false,
      nowTime = 130.0,
      lastSyncAt = 0.0,
      intervalMinutes = 2
    )
    check not shouldRequestPeriodicInGameSync(
      activeGameId = "",
      playerStateLoaded = true,
      connected = true,
      awaitingTurnAdvanceAfterSubmit = false,
      nowTime = 130.0,
      lastSyncAt = 0.0,
      intervalMinutes = 2
    )
    check not shouldRequestPeriodicInGameSync(
      activeGameId = "game-1",
      playerStateLoaded = true,
      connected = true,
      awaitingTurnAdvanceAfterSubmit = true,
      nowTime = 130.0,
      lastSyncAt = 0.0,
      intervalMinutes = 2
    )

  test "hud exposes reconnecting and stale sync states":
    check syncBadgeText(HudData(syncIntegrityState: "reconnecting")) ==
      "RELAY"
    check syncBadgeText(HudData(syncIntegrityState: "stale")) == "STALE"
    check syncBadgeText(HudData(syncIntegrityState: "syncing")) == "SYNC"
