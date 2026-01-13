## Localhost Order Watcher

## Polls orders/*.kdl → parse → Proposal(OrderReceived)

import std/[os, strutils, options]
import ../../../common/logger
import ../../../engine/types/command
import ../../../daemon/parser/kdl_orders
import ../../sam_core

proc collectOrdersLocal*(gameDir: string): seq[CommandPacket] =
  ## Walk orders/*.kdl → parse → packets
  result = @[]
  let ordersDir = gameDir / "orders"
  if not dirExists(ordersDir):
    return

  for kind, path in walkDir(ordersDir):
    if kind == pcFile and path.endsWith(".kdl"):
      try:
        let packet = parseOrdersFile(path)
        logInfo("Watcher", "Parsed orders file: ", path)
        result.add(packet)
        # Delete file after parse
        discard tryRemoveFile(path)
      except CatchableError as e:
        logError("Watcher", "Failed to parse orders file: ", path, " error: ", e.msg)
        
  if result.len > 0:
    logInfo("Watcher", "Collected ", $result.len, " packets from ", gameDir)