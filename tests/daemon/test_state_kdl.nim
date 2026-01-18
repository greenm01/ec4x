import std/[options, unittest]
import kdl

import ../../src/engine/init/game_state
import ../../src/engine/types/core
import ../../src/daemon/transport/nostr/state_kdl

proc findChild(node: KdlNode, name: string): Option[KdlNode] =
  for child in node.children:
    if child.name == name:
      return some(child)
  none(KdlNode)

suite "PlayerState KDL (30405)":
  test "formats full state with expected sections":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "State KDL Test",
      configDir = "config",
      dataDir = "data"
    )

    let kdlState = formatPlayerStateKdl("test-game", state, HouseId(1))
    let doc = parseKdl(kdlState)

    check doc.len == 1
    let root = doc[0]
    check root.name == "state"
    check root.props.hasKey("turn")
    check root.props.hasKey("game")

    check root.findChild("viewing-house").isSome
    check root.findChild("systems").isSome
    check root.findChild("public").isSome

    let publicNode = root.findChild("public").get()
    let actNode = publicNode.findChild("act-progression")
    check actNode.isSome
    check actNode.get().findChild("current-act").isSome

  test "formats colonies with canonical fields":
    let state = initGameState(
      setupPath = "scenarios/standard-4-player.kdl",
      gameName = "State KDL Colonies",
      configDir = "config",
      dataDir = "data"
    )

    let kdlState = formatPlayerStateKdl("test-game", state, HouseId(1))
    let doc = parseKdl(kdlState)
    let root = doc[0]
    let coloniesNode = root.findChild("colonies")

    check coloniesNode.isSome
    let colonyNodes = coloniesNode.get().children
    check colonyNodes.len > 0
    check colonyNodes[0].findChild("population").isSome
