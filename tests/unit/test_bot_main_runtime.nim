import std/unittest

import ../../src/bot/[main, runner]

suite "bot main runtime helpers":
  test "reconnect delay increases with cap":
    check reconnectDelaySec(0) >= 1
    check reconnectDelaySec(3) >= reconnectDelaySec(1)
    check reconnectDelaySec(10) <= 30

  test "decision retry delay classifies failures":
    let transportFailure = RetryResult(
      ok: false,
      trace: @[
        RetryTraceEntry(stage: "submit")
      ]
    )
    let validationFailure = RetryResult(
      ok: false,
      trace: @[
        RetryTraceEntry(stage: "schema_parse")
      ]
    )

    let transportDelay = decisionRetryDelaySec(transportFailure, 1)
    let validationDelay = decisionRetryDelaySec(validationFailure, 1)
    check validationDelay > transportDelay
