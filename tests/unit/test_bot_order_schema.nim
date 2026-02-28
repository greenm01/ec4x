import std/[unittest, options]

import ../../src/bot/order_schema

suite "bot order schema":
  test "parses minimal valid draft":
    let raw = """
    {
      "turn": 5,
      "houseId": 1,
      "fleetCommands": [
        {
          "fleetId": 100,
          "commandType": "move",
          "targetSystemId": 44,
          "roe": 6
        }
      ]
    }
    """
    let parsed = parseBotOrderDraft(raw)
    check parsed.ok
    check parsed.errors.len == 0
    check parsed.draft.turn == 5
    check parsed.draft.houseId == 1
    check parsed.draft.fleetCommands.len == 1
    check parsed.draft.fleetCommands[0].commandType == "move"
    check parsed.draft.fleetCommands[0].targetSystemId.isSome

  test "rejects invalid top-level payload":
    let parsed = parseBotOrderDraft("[]")
    check not parsed.ok
    check parsed.errors.len > 0

  test "reports missing required fields":
    let raw = """
    {
      "turn": 5,
      "fleetCommands": []
    }
    """
    let parsed = parseBotOrderDraft(raw)
    check not parsed.ok
    check parsed.errors.len > 0

  test "reports nested field type mismatches":
    let raw = """
    {
      "turn": 5,
      "houseId": 1,
      "fleetCommands": [
        {
          "fleetId": "A1",
          "commandType": "move",
          "targetSystemId": 44
        }
      ]
    }
    """
    let parsed = parseBotOrderDraft(raw)
    check not parsed.ok
    check parsed.errors.len > 0

  test "parses zero-turn fighter fields":
    let raw = """
    {
      "turn": 5,
      "houseId": 1,
      "zeroTurnCommands": [
        {
          "commandType": "transfer-fighters",
          "sourceFleetId": 10,
          "targetFleetId": 11,
          "fighterShipIds": [1001, 1002],
          "sourceCarrierShipId": 2001,
          "targetCarrierShipId": 2002
        }
      ]
    }
    """
    let parsed = parseBotOrderDraft(raw)
    check parsed.ok
    check parsed.draft.zeroTurnCommands.len == 1
    let cmd = parsed.draft.zeroTurnCommands[0]
    check cmd.fighterShipIds.len == 2
    check cmd.sourceCarrierShipId.isSome
    check cmd.targetCarrierShipId.isSome
