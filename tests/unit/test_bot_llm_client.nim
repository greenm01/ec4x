import std/[unittest, strutils]

import ../../src/bot/llm_client

suite "bot llm client":
  test "buildChatPayload embeds model and prompt":
    let payload = buildChatPayload("gpt-test", "hello world")
    check payload.contains("gpt-test")
    check payload.contains("hello world")

  test "parseChatCompletionContent extracts message content":
    let raw = """
    {
      "choices": [
        {
          "message": {
            "content": "{\"turn\":1,\"houseId\":1}"
          }
        }
      ]
    }
    """
    let parsed = parseChatCompletionContent(raw)
    check parsed.ok
    check parsed.content.contains("\"turn\":1")

  test "parseChatCompletionContent rejects malformed payload":
    let parsed = parseChatCompletionContent("{\"choices\":[]}")
    check not parsed.ok
    check parsed.error.len > 0
