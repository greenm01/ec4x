## KDL join protocol helpers
# exports for join parsing/formatting

import std/[options, strutils]
import kdl
import ../engine/types/core

const
  JoinNodeName = "join"
  JoinResponseNodeName = "join-response"

  StatusAccepted = "accepted"
  StatusRejected = "rejected"

type
  JoinRequest* = object
    gameId*: string
    pubkey*: string
    name*: Option[string]

  JoinResponseStatus* {.pure.} = enum
    Accepted
    Rejected

  JoinResponse* = object
    gameId*: string
    status*: JoinResponseStatus
    houseId*: Option[HouseId]
    reason*: Option[string]

proc kdlString(val: KdlVal): string =
  case val.kind
  of KString:
    val.kString()
  else:
    raise newException(ValueError, "Expected string")

proc parseHouseId(val: KdlVal): HouseId =
  case val.kind
  of KInt, KInt8, KInt16, KInt32, KInt64:
    HouseId(val.kInt().uint32)
  of KString:
    try:
      HouseId(parseInt(val.kString()).uint32)
    except ValueError:
      raise newException(ValueError, "Invalid house ID")
  else:
    raise newException(ValueError, "Invalid house ID")

proc requireProp(node: KdlNode, key: string): KdlVal =
  if node.props.hasKey(key):
    return node.props[key]
  raise newException(ValueError, "Missing property: " & key)

proc parseJoinRequestKdl*(doc: KdlDoc): JoinRequest =
  if doc.len == 0:
    raise newException(ValueError, "Empty join document")

  let node = doc[0]
  if node.name != JoinNodeName:
    raise newException(ValueError, "Root node must be 'join'")

  result.gameId = node.requireProp("game").kdlString()
  result.pubkey = node.requireProp("nostr_pubkey").kdlString()
  if node.props.hasKey("name"):
    result.name = some(node.props["name"].kdlString())

proc parseJoinResponseKdl*(doc: KdlDoc): JoinResponse =
  if doc.len == 0:
    raise newException(ValueError, "Empty join response")

  let node = doc[0]
  if node.name != JoinResponseNodeName:
    raise newException(ValueError, "Root node must be 'join-response'")

  result.gameId = node.requireProp("game").kdlString()
  let statusVal = node.requireProp("status").kdlString().toLowerAscii()
  if statusVal == StatusAccepted:
    result.status = JoinResponseStatus.Accepted
  elif statusVal == StatusRejected:
    result.status = JoinResponseStatus.Rejected
  else:
    raise newException(ValueError, "Invalid join status")

  if node.props.hasKey("house"):
    result.houseId = some(parseHouseId(node.props["house"]))
  if node.props.hasKey("reason"):
    result.reason = some(node.props["reason"].kdlString())

proc parseJoinRequestFile*(path: string): JoinRequest =
  let content = readFile(path)
  let doc = parseKdl(content)
  parseJoinRequestKdl(doc)

proc parseJoinResponseFile*(path: string): JoinResponse =
  let content = readFile(path)
  let doc = parseKdl(content)
  parseJoinResponseKdl(doc)

proc formatJoinRequest*(request: JoinRequest): string =
  var line = "join game=\"" & request.gameId & "\" " &
    "nostr_pubkey=\"" & request.pubkey & "\""
  if request.name.isSome:
    line.add(" name=\"" & request.name.get() & "\"")
  line & "\n"

proc formatJoinResponse*(response: JoinResponse): string =
  var line = "join-response game=\"" & response.gameId & "\" "
  case response.status
  of JoinResponseStatus.Accepted:
    line.add("status=" & StatusAccepted)
    if response.houseId.isSome:
      line.add(" house=(HouseId)" & $response.houseId.get().uint32)
  of JoinResponseStatus.Rejected:
    line.add("status=" & StatusRejected)
    if response.reason.isSome:
      line.add(" reason=\"" & response.reason.get() & "\"")
  line & "\n"
