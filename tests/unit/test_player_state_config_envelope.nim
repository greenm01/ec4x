## Unit tests for full-state/delta config envelope validation.

import std/[unittest, options, tables]
import msgpack4nim

import ../../src/common/config_sync
import ../../src/engine/config/engine as config_engine
import ../../src/engine/globals
import ../../src/engine/types/[combat, core, event, facilities, player_state]
import ../../src/daemon/persistence/player_state_snapshot
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
      authoritativeConfig: snapshot,
      stateHash: computePlayerStateHash(ps)
    )
    let payload = pack(envelope)
    let parsed = parseFullStateMsgpack(payload)
    check parsed.isSome
    check fullStateHashMatches(parsed.get())
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
      configHash: snapshot.configHash,
      stateHash: computePlayerStateHash(PlayerState(
        turn: 2,
        viewingHouse: HouseId(1)
      ))
    )
    let payload = pack(envelope)
    let applied = applyDeltaMsgpack(
      ps,
      payload,
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isSome
    check applied.get().hashMatched
    check applied.get().turn == 2
    check applied.get().playerState.turn == 2

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
      configHash: snapshot.configHash,
      stateHash: computePlayerStateHash(PlayerState(
        turn: 2,
        viewingHouse: HouseId(1),
        ebpPool: some(11'i32),
        cipPool: some(7'i32)
      ))
    )
    let payload = pack(envelope)
    let applied = applyDeltaMsgpack(
      ps,
      payload,
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isSome
    check applied.get().hashMatched
    check applied.get().playerState.ebpPool == some(11'i32)
    check applied.get().playerState.cipPool == some(7'i32)

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
      configHash: "bad-hash",
      stateHash: computePlayerStateHash(PlayerState(
        turn: 2,
        viewingHouse: HouseId(1)
      ))
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

  test "applyDeltaMsgpack updates facilities and turn events":
    let snapshot = buildTuiRulesSnapshot(gameConfig)
    let event = GameEvent(
      turn: 2,
      description: "construction started",
      eventType: GameEventType.ConstructionStarted
    )
    let neoria = Neoria(
      id: NeoriaId(7),
      neoriaClass: NeoriaClass.Spaceport,
      colonyId: ColonyId(12),
      commissionedTurn: 2,
      state: CombatState.Nominal
    )
    let kastra = Kastra(
      id: KastraId(9),
      kastraClass: KastraClass.Starbase,
      colonyId: ColonyId(12),
      commissionedTurn: 2,
      state: CombatState.Nominal
    )
    let expectedState = PlayerState(
      turn: 2,
      viewingHouse: HouseId(1),
      ownNeorias: @[neoria],
      ownKastras: @[kastra],
      turnEvents: @[event]
    )
    let delta = PlayerStateDelta(
      viewingHouse: HouseId(1),
      turn: 2,
      ownNeorias: EntityDelta[Neoria](added: @[neoria]),
      ownKastras: EntityDelta[Kastra](added: @[kastra]),
      turnEvents: @[event]
    )
    let envelope = PlayerStateDeltaEnvelope(
      delta: delta,
      configSchemaVersion: ConfigSchemaVersion,
      configHash: snapshot.configHash,
      stateHash: computePlayerStateHash(expectedState)
    )
    let applied = applyDeltaMsgpack(
      PlayerState(turn: 1, viewingHouse: HouseId(1)),
      pack(envelope),
      snapshot.configHash,
      ConfigSchemaVersion
    )
    check applied.isSome
    check applied.get().hashMatched
    check applied.get().playerState.ownNeorias.len == 1
    check applied.get().playerState.ownKastras.len == 1
    check applied.get().playerState.turnEvents.len == 1
