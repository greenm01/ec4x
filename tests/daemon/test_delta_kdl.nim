import std/[options, unittest]
import kdl

import ../../src/engine/init/game_state
import ../../src/engine/types/core
import ../../src/daemon/transport/nostr/delta_kdl
import ../../src/daemon/persistence/player_state_snapshot

proc findChild(node: KdlNode, name: string): Option[KdlNode] =
  for child in node.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

suite "PlayerState Delta KDL (30403)":
  test "formats delta root with metadata":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "Delta KDL Test",
      configDir = "config",
      dataDir = "data"
    )

    let snapshot = buildPlayerStateSnapshot(state, HouseId(1))
    let delta = diffPlayerState(none(PlayerStateSnapshot), snapshot)
    let kdlDelta = formatPlayerStateDeltaKdl("test-game", delta)
    let doc = parseKdl(kdlDelta)

    check doc.len == 1
    let root = doc[0]
    check root.name == "delta"
    check root.props.hasKey("version")
    check root.props.hasKey("turn")
    check root.props.hasKey("game")
    check root.props.hasKey("house")

  test "formats delta entries with canonical fields":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "Delta KDL Payloads",
      configDir = "config",
      dataDir = "data"
    )

    let snapshot = buildPlayerStateSnapshot(state, HouseId(1))
    let delta = diffPlayerState(none(PlayerStateSnapshot), snapshot)
    let kdlDelta = formatPlayerStateDeltaKdl("test-game", delta)
    let doc = parseKdl(kdlDelta)
    let root = doc[0]

    let coloniesNode = root.findChild("colonies")
    check coloniesNode.isSome
    if coloniesNode.isSome:
      let entries = coloniesNode.get().children
      check entries.len > 0
      let colonyEntry = entries[0]
      check colonyEntry.props.hasKey("population")
      check not colonyEntry.props.hasKey("construction-queue")

    let fleetsNode = root.findChild("fleets")
    check fleetsNode.isSome
    if fleetsNode.isSome:
      let entries = fleetsNode.get().children
      check entries.len > 0
      var hasShips = false
      for entry in entries:
        if entry.findChild("ships").isSome:
          hasShips = true
          break
      check hasShips

    let systemsNode = root.findChild("visible-systems")
    check systemsNode.isSome
    if systemsNode.isSome:
      let entries = systemsNode.get().children
      if entries.len > 0:
        check not entries[0].props.hasKey("lanes")
