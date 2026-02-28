## OpenAI-compatible LLM client for bot order generation.

import std/[httpclient, json, options, strutils, times]

import ./types

type
  BotLlmResult* = object
    ok*: bool
    content*: string
    error*: string
    requestMs*: int
    responseBytes*: int

proc apiBaseUrl(cfg: BotConfig): string =
  if cfg.baseUrl.len == 0:
    return "https://api.openai.com/v1"
  cfg.baseUrl.strip(chars = {'/'})

proc buildChatPayload*(model: string, prompt: string): string =
  let payload = %*{
    "model": model,
    "messages": [
      {
        "role": "system",
        "content": "Return only strict JSON for EC4X command draft."
      },
      {
        "role": "user",
        "content": prompt
      }
    ],
    "temperature": 0.2
  }
  $payload

proc parseChatCompletionContent*(raw: string): BotLlmResult =
  var root: JsonNode
  try:
    root = parseJson(raw)
  except CatchableError as e:
    return BotLlmResult(
      ok: false,
      error: "Invalid LLM response JSON: " & e.msg
    )

  if root.kind != JObject:
    return BotLlmResult(ok: false,
      error: "LLM response root must be object")
  if "choices" notin root or root["choices"].kind != JArray:
    return BotLlmResult(ok: false,
      error: "LLM response missing choices array")
  if root["choices"].len == 0:
    return BotLlmResult(ok: false,
      error: "LLM response choices array is empty")

  let first = root["choices"][0]
  if "message" notin first or first["message"].kind != JObject:
    return BotLlmResult(ok: false,
      error: "LLM response missing choices[0].message")
  if "content" notin first["message"] or
      first["message"]["content"].kind != JString:
    return BotLlmResult(ok: false,
      error: "LLM response missing choices[0].message.content")

  BotLlmResult(
    ok: true,
    content: first["message"]["content"].getStr(),
    responseBytes: raw.len
  )

proc generateDraftJson*(cfg: BotConfig, prompt: string): BotLlmResult =
  if cfg.apiKey.len == 0:
    return BotLlmResult(ok: false, error: "BOT_API_KEY is missing")
  if cfg.model.len == 0:
    return BotLlmResult(ok: false, error: "BOT_MODEL is missing")

  var http = newHttpClient(timeout = cfg.requestTimeoutSec * 1000)
  defer:
    http.close()

  let url = apiBaseUrl(cfg) & "/chat/completions"
  http.headers = newHttpHeaders({
    "Authorization": "Bearer " & cfg.apiKey,
    "Content-Type": "application/json"
  })

  let payload = buildChatPayload(cfg.model, prompt)
  let startedAt = getTime()
  let raw =
    try:
      http.request(
        url,
        httpMethod = HttpPost,
        body = payload
      ).body
    except CatchableError as e:
      return BotLlmResult(ok: false,
        error: "LLM request failed: " & e.msg)
  let elapsedMs = int((getTime() - startedAt).inMilliseconds)

  result = parseChatCompletionContent(raw)
  result.requestMs = elapsedMs
  if result.responseBytes <= 0:
    result.responseBytes = raw.len
