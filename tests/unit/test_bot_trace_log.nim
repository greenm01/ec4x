import std/[unittest, os, strutils]

import ../../src/bot/[trace_log, runner]

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
          details: @["missing turn"]
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

    removeDir(tmpDir)
