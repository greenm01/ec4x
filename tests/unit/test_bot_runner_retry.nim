import std/unittest

import ../../src/bot/[runner, llm_client]
import ../../src/engine/types/fleet
import ../../src/engine/types/command

suite "bot runner retry loop":
  test "recovers from malformed first response":
    var calls = 0
    let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
      discard prompt
      calls.inc
      if calls == 1:
        return BotLlmResult(ok: true, content: "{not-json")
      BotLlmResult(ok: true, content: """
      {
        "turn": 4,
        "houseId": 1,
        "fleetCommands": [
          {
            "fleetId": 9,
            "commandType": "hold"
          }
        ]
      }
      """)

    let result = generatePacketWithRetries("base", 2, generator)
    check result.ok
    check result.attempts == 2
    check result.packet.fleetCommands.len == 1
    check result.packet.fleetCommands[0].commandType ==
      FleetCommandType.Hold

  test "fails when retry budget exhausted":
    let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
      discard prompt
      BotLlmResult(ok: true, content: "{bad")

    let result = generatePacketWithRetries("base", 1, generator)
    check not result.ok
    check result.attempts == 2
    check result.errors.len > 0

  test "retries when submission is rejected":
    var genCalls = 0
    var submitCalls = 0

    let generator: DraftGenerator = proc(prompt: string): BotLlmResult =
      discard prompt
      genCalls.inc
      BotLlmResult(ok: true, content: """
      {
        "turn": 4,
        "houseId": 1,
        "fleetCommands": [
          {
            "fleetId": 9,
            "commandType": "hold"
          }
        ]
      }
      """)

    let submitter: PacketSubmitter = proc(
        packet: CommandPacket
    ): tuple[ok: bool, message: string] =
      discard packet
      submitCalls.inc
      if submitCalls == 1:
        return (false, "turn mismatch")
      (true, "")

    let result = generateAndSubmitWithRetries(
      "base",
      2,
      generator,
      submitter
    )
    check result.ok
    check result.attempts == 2
    check genCalls == 2
    check submitCalls == 2
