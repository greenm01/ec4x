## Bot turn loop primitives and correction loop helpers.

import std/strutils

import ./types
import ./state_store
import ./llm_client
import ./order_schema
import ./order_compiler

import ../engine/types/command

type
  DraftGenerator* = proc(prompt: string): BotLlmResult
  PacketSubmitter* = proc(packet: CommandPacket): tuple[
    ok: bool,
    message: string
  ]

  RetryResult* = object
    ok*: bool
    packet*: CommandPacket
    finalPrompt*: string
    attempts*: int
    errors*: seq[string]

proc shouldSubmitTurn*(runtime: BotRuntimeState): bool =
  runtime.hasActionableTurn()

proc markSubmitted*(runtime: var BotRuntimeState) =
  runtime.markTurnSubmitted()

proc appendFeedbackPrompt(basePrompt: string, errors: seq[string]): string =
  var lines: seq[string] = @[basePrompt, "", "Fix these errors:"]
  for err in errors:
    lines.add("- " & err)
  lines.add("Return corrected JSON only.")
  lines.join("\n")

proc generatePacketWithRetries*(
    basePrompt: string,
    maxRetries: int,
    generator: DraftGenerator
): RetryResult =
  var prompt = basePrompt
  var errors: seq[string] = @[]
  let maxAttempts = max(1, maxRetries + 1)

  for attempt in 1 .. maxAttempts:
    let llm = generator(prompt)
    if not llm.ok:
      errors.add(llm.error)
      prompt = appendFeedbackPrompt(basePrompt, @[llm.error])
      continue

    let parsed = parseBotOrderDraft(llm.content)
    if not parsed.ok:
      errors = parsed.errors
      prompt = appendFeedbackPrompt(basePrompt, parsed.errors)
      continue

    let compiled = compileCommandPacket(parsed.draft)
    if not compiled.ok:
      errors = compiled.errors
      prompt = appendFeedbackPrompt(basePrompt, compiled.errors)
      continue

    return RetryResult(
      ok: true,
      packet: compiled.packet,
      finalPrompt: prompt,
      attempts: attempt,
      errors: @[]
    )

  RetryResult(
    ok: false,
    finalPrompt: prompt,
    attempts: maxAttempts,
    errors: errors
  )

proc generateAndSubmitWithRetries*(
    basePrompt: string,
    maxRetries: int,
    generator: DraftGenerator,
    submitter: PacketSubmitter
): RetryResult =
  var prompt = basePrompt
  var errors: seq[string] = @[]
  let maxAttempts = max(1, maxRetries + 1)

  for attempt in 1 .. maxAttempts:
    let llm = generator(prompt)
    if not llm.ok:
      errors = @[llm.error]
      prompt = appendFeedbackPrompt(basePrompt, errors)
      continue

    let parsed = parseBotOrderDraft(llm.content)
    if not parsed.ok:
      errors = parsed.errors
      prompt = appendFeedbackPrompt(basePrompt, errors)
      continue

    let compiled = compileCommandPacket(parsed.draft)
    if not compiled.ok:
      errors = compiled.errors
      prompt = appendFeedbackPrompt(basePrompt, errors)
      continue

    let submit = submitter(compiled.packet)
    if submit.ok:
      return RetryResult(
        ok: true,
        packet: compiled.packet,
        finalPrompt: prompt,
        attempts: attempt,
        errors: @[]
      )

    errors = @["Submission rejected: " & submit.message]
    prompt = appendFeedbackPrompt(basePrompt, errors)

  RetryResult(
    ok: false,
    finalPrompt: prompt,
    attempts: maxAttempts,
    errors: errors
  )
