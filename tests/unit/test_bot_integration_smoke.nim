import std/unittest

import ../../src/bot/[types, session, runner, llm_client]
import ../../src/daemon/transport/nostr/state_msgpack
import ../../src/common/config_sync
import ../../src/player/state/msgpack_serializer
import ../../src/engine/types/[core, player_state, command]

suite "bot integration smoke":
  test "ingest state and decide packet":
    var bot = initBotSession(BotConfig(
      relays: @["wss://example.invalid"],
      gameId: "game-1",
      daemonPubkey: "daemon",
      playerPrivHex: "priv",
      playerPubHex: "pub",
      model: "gpt-test",
      baseUrl: "https://api.example.invalid/v1",
      apiKey: "key",
      maxRetries: 1,
      requestTimeoutSec: 10
    ))

    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 8'i32
    )
    let envelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )
    let payload = serializePlayerStateEnvelope(envelope)
    check bot.ingestFullStatePayload(payload, "evt-1")
    check bot.readyForDecision()

    let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
      discard prompt
      BotLlmResult(ok: true, content: """
      {
        "turn": 8,
        "houseId": 1,
        "fleetCommands": [
          {
            "fleetId": 77,
            "commandType": "hold"
          }
        ]
      }
      """)

    let decision = bot.decidePacket(generator)
    check decision.ok
    check decision.packet.turn == 8
    check decision.packet.fleetCommands.len == 1
    check not bot.readyForDecision()

    let packed = serializeCommandPacket(decision.packet)
    check packed.len > 0

  test "decide and submit marks turn submitted":
    var bot = initBotSession(BotConfig(maxRetries: 1))
    let state = PlayerState(
      viewingHouse: HouseId(1),
      turn: 3'i32
    )
    let envelope = PlayerStateEnvelope(
      playerState: state,
      authoritativeConfig: TuiRulesSnapshot(
        schemaVersion: ConfigSchemaVersion,
        configHash: "cfg-v1"
      )
    )
    check bot.ingestFullStatePayload(serializePlayerStateEnvelope(envelope))

    let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
      discard prompt
      BotLlmResult(ok: true, content: """
      {
        "turn": 3,
        "houseId": 1,
        "fleetCommands": [
          {
            "fleetId": 8,
            "commandType": "hold"
          }
        ]
      }
      """)
    let submitter: PacketSubmitter = proc(
        packet: CommandPacket
    ): tuple[ok: bool, message: string] =
      discard packet
      (true, "")

    let decision = bot.decideAndSubmitPacket(generator, submitter)
    check decision.ok
    check bot.runtime.lastSubmittedTurn == 3
