## Persistence helpers for bot retry/correction traces.

import std/[json, os, strutils, tables, times]

import ./runner
import ./types
import ../engine/types/[command, zero_turn]

proc packetFeatureTags(packet: CommandPacket): seq[string] =
  if packet.zeroTurnCommands.len > 0:
    result.add("zero_turn")
    for cmd in packet.zeroTurnCommands:
      case cmd.commandType
      of ZeroTurnCommandType.DetachShips:
        result.add("ztc_detach_ships")
      of ZeroTurnCommandType.TransferShips:
        result.add("ztc_transfer_ships")
      of ZeroTurnCommandType.MergeFleets:
        result.add("ztc_merge_fleets")
      of ZeroTurnCommandType.LoadCargo:
        result.add("ztc_load_cargo")
      of ZeroTurnCommandType.UnloadCargo:
        result.add("ztc_unload_cargo")
      of ZeroTurnCommandType.LoadFighters:
        result.add("ztc_load_fighters")
      of ZeroTurnCommandType.UnloadFighters:
        result.add("ztc_unload_fighters")
      of ZeroTurnCommandType.TransferFighters:
        result.add("ztc_transfer_fighters")
      of ZeroTurnCommandType.Reactivate:
        result.add("ztc_reactivate")
  if packet.fleetCommands.len > 0:
    result.add("fleet")
  if packet.buildCommands.len > 0:
    result.add("build")
  if packet.repairCommands.len > 0:
    result.add("repair")
  if packet.scrapCommands.len > 0:
    result.add("scrap")
  if packet.diplomaticCommand.len > 0:
    result.add("diplomacy")
  if packet.populationTransfers.len > 0:
    result.add("population_transfer")
  if packet.terraformCommands.len > 0:
    result.add("terraform")
  if packet.colonyManagement.len > 0:
    result.add("colony_management")
  if packet.espionageActions.len > 0:
    result.add("espionage")
  if packet.researchAllocation.economic > 0 or
      packet.researchAllocation.science > 0 or
      packet.researchAllocation.technology.len > 0:
    result.add("research")
  if packet.ebpInvestment > 0 or packet.cipInvestment > 0:
    result.add("investment")

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
    "featureTags":
      if result.ok:
        packetFeatureTags(result.packet)
      else:
        @[],
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
