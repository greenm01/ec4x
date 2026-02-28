## Bot session coordinator for state ingestion and turn decisions.

import std/options

import ./types
import ./state_store
import ./prompt_context
import ./runner
import ./trace_log

type
  BotSession* = object
    config*: BotConfig
    runtime*: BotRuntimeState

proc initBotSession*(config: BotConfig): BotSession =
  BotSession(
    config: config,
    runtime: initBotRuntimeState()
  )

proc ingestFullStatePayload*(
    session: var BotSession,
    payload: string,
    eventId: string = ""
): bool =
  session.runtime.applyFullStatePayload(payload, eventId)

proc ingestDeltaPayload*(
    session: var BotSession,
    payload: string,
    eventId: string = ""
): bool =
  session.runtime.applyDeltaPayload(payload, eventId)

proc readyForDecision*(session: BotSession): bool =
  session.runtime.hasActionableTurn()

proc buildDecisionPrompt*(session: BotSession): Option[string] =
  if not session.runtime.hasState:
    return none(string)
  some(buildTurnContext(session.runtime.playerState))

proc decidePacket*(
    session: var BotSession,
    generator: DraftGenerator
): RetryResult =
  if not session.readyForDecision():
    return RetryResult(ok: false, errors: @["No actionable turn available"])

  let promptOpt = session.buildDecisionPrompt()
  if promptOpt.isNone:
    return RetryResult(ok: false, errors: @["No state loaded"])

  let decision = generatePacketWithRetries(
    promptOpt.get(),
    session.config.maxRetries,
    generator
  )
  persistTurnTrace(
    session.config.logDir,
    session.config.gameId,
    int(session.runtime.playerState.turn),
    decision
  )
  if decision.ok:
    session.runtime.markTurnSubmitted()
  decision

proc decideAndSubmitPacket*(
    session: var BotSession,
    generator: DraftGenerator,
    submitter: PacketSubmitter
): RetryResult =
  if not session.readyForDecision():
    return RetryResult(ok: false, errors: @["No actionable turn available"])

  let promptOpt = session.buildDecisionPrompt()
  if promptOpt.isNone:
    return RetryResult(ok: false, errors: @["No state loaded"])

  let decision = generateAndSubmitWithRetries(
    promptOpt.get(),
    session.config.maxRetries,
    generator,
    submitter
  )
  persistTurnTrace(
    session.config.logDir,
    session.config.gameId,
    int(session.runtime.playerState.turn),
    decision
  )
  if decision.ok:
    session.runtime.markTurnSubmitted()
  decision
