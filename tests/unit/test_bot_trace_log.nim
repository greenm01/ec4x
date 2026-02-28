import std/[unittest, os, strutils]

import std/options

import ../../src/bot/[trace_log, runner, types, order_schema, order_compiler]

suite "bot trace log":
  test "persistTurnTrace appends jsonl record":
    let tmpDir = getTempDir() / "ec4x_bot_trace_test"
    if dirExists(tmpDir):
      removeDir(tmpDir)
    createDir(tmpDir)

    let result = RetryResult(
      ok: false,
      attempts: 2,
      errors: @["schema error"],
      trace: @[
        RetryTraceEntry(
          attempt: 1,
          stage: "schema_parse",
          details: @["missing turn"],
          outcome: "retry",
          llmRequestMs: 120,
          llmResponseBytes: 560
        )
      ]
    )

    persistTurnTrace(tmpDir, "game-123", 5, result)
    let traceFile = tmpDir / "bot_trace_game-123.jsonl"
    check fileExists(traceFile)
    let content = readFile(traceFile)
    check content.contains("\"gameId\":\"game-123\"")
    check content.contains("\"turn\":5")
    check content.contains("\"stage\":\"schema_parse\"")
    check content.contains("\"llmRequestMs\":120")
    check content.contains("\"errorClass\":\"validation\"")

    let cfg = BotConfig(
      relays: @["ws://localhost:8080"],
      gameId: "game-123",
      model: "gpt-4o-mini",
      maxRetries: 2,
      requestTimeoutSec: 45
    )
    persistSessionTrace(tmpDir, cfg)

    let updatedContent = readFile(traceFile)
    check updatedContent.contains("\"kind\":\"session_start\"")
    check updatedContent.contains("\"autoReconnect\":true")

    let successDraft = BotOrderDraft(
      turn: 6,
      houseId: 1,
      zeroTurnCommands: @[
        BotZeroTurnOrder(
          commandType: "reactivate",
          sourceFleetId: some(9),
          targetFleetId: none(int),
          shipIndices: @[],
          fighterShipIds: @[],
          carrierShipId: none(int),
          sourceCarrierShipId: none(int),
          targetCarrierShipId: none(int),
          cargoType: none(string),
          quantity: none(int)
        )
      ],
      fleetCommands: @[
        BotFleetOrder(
          fleetId: 9,
          commandType: "hold",
          targetSystemId: none(int),
          targetFleetId: none(int),
          roe: none(int)
        )
      ],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      diplomaticCommand: none(BotDiplomaticOrder),
      researchAllocation: none(BotResearchAllocation),
      ebpInvestment: some(1),
      cipInvestment: some(0)
    )
    let compiled = compileCommandPacket(successDraft)
    check compiled.ok
    let successResult = RetryResult(
      ok: true,
      attempts: 1,
      errors: @[],
      packet: compiled.packet,
      trace: @[]
    )
    persistTurnTrace(tmpDir, "game-123", 6, successResult)
    let successContent = readFile(traceFile)
    check successContent.contains("\"featureTags\"")
    check successContent.contains("\"zero_turn\"")
    check successContent.contains("\"ztc_reactivate\"")
    check successContent.contains("\"fleet\"")
    check successContent.contains("\"investment\"")

    removeDir(tmpDir)
