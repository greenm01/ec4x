## Persistence helpers for bot retry/correction traces.

import std/[json, os, strutils, times]

import ./runner
import ./types

proc tracePath(logDir: string, gameId: string): string =
  let safeGame =
    if gameId.len > 0:
      gameId.replace("/", "_")
    else:
      "unknown"
  logDir / ("bot_trace_" & safeGame & ".jsonl")

proc persistTurnTrace*(
    logDir: string,
    gameId: string,
    turn: int,
    result: RetryResult
) =
  if logDir.len == 0:
    return

  createDir(logDir)

  var traces = newJArray()
  for entry in result.trace:
    traces.add(%*{
      "attempt": entry.attempt,
      "stage": entry.stage,
      "details": entry.details,
      "outcome": entry.outcome,
      "llmRequestMs": entry.llmRequestMs,
      "llmResponseBytes": entry.llmResponseBytes
    })

  let payload = %*{
    "timestamp": now().format("yyyy-MM-dd'T'HH:mm:sszzz"),
    "gameId": gameId,
    "turn": turn,
    "ok": result.ok,
    "errorClass": classifyRetryResult(result),
    "attempts": result.attempts,
    "errors": result.errors,
    "trace": traces
  }

  let line = $payload & "\n"
  let path = tracePath(logDir, gameId)
  var fh: File
  if open(fh, path, fmAppend):
    defer:
      fh.close()
    fh.write(line)

proc persistSessionTrace*(logDir: string, cfg: BotConfig) =
  if logDir.len == 0:
    return

  createDir(logDir)

  let payload = %*{
    "kind": "session_start",
    "timestamp": now().format("yyyy-MM-dd'T'HH:mm:sszzz"),
    "gameId": cfg.gameId,
    "model": cfg.model,
    "relays": cfg.relays,
    "maxRetries": cfg.maxRetries,
    "requestTimeoutSec": cfg.requestTimeoutSec,
    "autoReconnect": true
  }

  let line = $payload & "\n"
  let path = tracePath(logDir, cfg.gameId)
  var fh: File
  if open(fh, path, fmAppend):
    defer:
      fh.close()
    fh.write(line)
