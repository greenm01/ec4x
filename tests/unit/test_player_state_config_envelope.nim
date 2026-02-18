## Unit tests for full-state/delta config envelope validation.

import std/[unittest, options, tables]
import msgpack4nim

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/engine/types/[core, player_state]
import ../../src/daemon/transport/nostr/state_msgpack
import ../../src/daemon/transport/nostr/delta_msgpack
import ../../src/player/state/msgpack_state

gameConfig = config_engine.loadGameConfig()

suite "Player State Config Envelope":
  test "parseFullStateMsgpack reads envelope":
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let ps = PlayerState(
      turn: 3,
      viewingHouse: HouseId(2)
    )
    let envelope = PlayerStateEnvelope(
      playerState: ps,
      authoritativeConfig: snapshot
    )
    let payload = pack(envelope)
    let parsed = parseFullStateMsgpack(payload)
    check parsed.isSome
    check parsed.get().playerState.turn == 3
    check parsed.get().authoritativeConfig.configHash == snapshot.configHash
    check parsed.get().authoritativeConfig.sections.tech.isSome
    let slLevels =
      parsed.get().authoritativeConfig.sections.tech.get().sl.levels
    check len(slLevels) > 0

  test "applyDeltaMsgpack accepts matching config hash":
    var ps = PlayerState(
      turn: 1,
      viewingHouse: HouseId(1)
    )
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 2
    )
    let envelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: snapshot.configHash
    )
    let payload = pack(envelope)
    let applied = applyDeltaMsgpack(
      ps,
      payload,
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isSome
    check ps.turn == 2

  test "applyDeltaMsgpack updates EBP/CIP pools":
    var ps = PlayerState(
      turn: 1,
      viewingHouse: HouseId(1),
      ebpPool: some(3'i32),
      cipPool: some(2'i32)
    )
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 2,
      ebpPoolChanged: true,
      ebpPool: some(11'i32),
      cipPoolChanged: true,
      cipPool: some(7'i32)
    )
    let envelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: snapshot.configHash
    )
    let payload = pack(envelope)
    let applied = applyDeltaMsgpack(
      ps,
      payload,
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isSome
    check ps.ebpPool == some(11'i32)
    check ps.cipPool == some(7'i32)

  test "applyDeltaMsgpack rejects mismatched config hash":
    var ps = PlayerState(
      turn: 1,
      viewingHouse: HouseId(1)
    )
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 2
    )
    let envelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: "bad-hash"
    )
    let payload = pack(envelope)
    let applied = applyDeltaMsgpack(
      ps,
      payload,
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isNone
    check ps.turn == 1
