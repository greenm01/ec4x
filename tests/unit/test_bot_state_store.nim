import std/[unittest, options]

import ../../src/bot/[types, state_store]
import ../../src/daemon/transport/nostr/[state_msgpack, delta_msgpack]
import ../../src/common/config_sync
import ../../src/engine/types/[core, player_state]

suite "bot state store":
  test "applies full state payload":
    var runtime = initBotRuntimeState()
    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 5'i32
    )
    let envelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )
    let payload = serializePlayerStateEnvelope(envelope)

    let ok = runtime.applyFullStatePayload(payload, "evt-full-1")
    check ok
    check runtime.hasState
    check runtime.playerState.turn == 5
    check runtime.configHash == "cfg-v1"
    check runtime.configSchemaVersion == ConfigSchemaVersion
    check runtime.lastEventId.isSome

  test "applies delta payload after full state":
    var runtime = initBotRuntimeState()
    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 5'i32
    )
    let fullEnvelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )
    check runtime.applyFullStatePayload(
      serializePlayerStateEnvelope(fullEnvelope)
    )

    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 6'i32
    )
    let deltaEnvelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: "cfg-v1"
    )

    let ok = runtime.applyDeltaPayload(
      serializePlayerStateDeltaEnvelope(deltaEnvelope),
      "evt-delta-1"
    )
    check ok
    check runtime.playerState.turn == 6
    check runtime.lastSeenTurn == 6
    check runtime.lastEventId.isSome

  test "actionable turn lifecycle":
    var runtime = initBotRuntimeState()
    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 9'i32
    )
    let envelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )
    check runtime.applyFullStatePayload(serializePlayerStateEnvelope(envelope))
    check runtime.hasActionableTurn()

    runtime.markTurnSubmitted()
    check not runtime.hasActionableTurn()

  test "ignores duplicate event IDs":
    var runtime = initBotRuntimeState()
    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 5'i32
    )
    let envelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )

    check runtime.applyFullStatePayload(
      serializePlayerStateEnvelope(envelope),
      "evt-same"
    )
    check not runtime.applyFullStatePayload(
      serializePlayerStateEnvelope(envelope),
      "evt-same"
    )

    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 6'i32
    )
    let deltaEnvelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: "cfg-v1"
    )

    check runtime.applyDeltaPayload(
      serializePlayerStateDeltaEnvelope(deltaEnvelope),
      "evt-delta-same"
    )
    check not runtime.applyDeltaPayload(
      serializePlayerStateDeltaEnvelope(deltaEnvelope),
      "evt-delta-same"
    )
