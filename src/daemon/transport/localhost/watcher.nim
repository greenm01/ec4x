## Localhost Order Watcher

## Polls houses/* /orders_pending.kdl → parse → Proposal(OrderReceived)

import std/[os, walkdir, strutils]
import nimkdl
import ../../engine/types/command
import ../sam_core

proc parseOrdersKdl(kdlPath: string): CommandPacket =
  ## Parse KDL orders → CommandPacket (stub)
  ## TODO: Full parser for fleet cmds
  let doc = kdl.parseFile(kdlPath)
  result = @[]  # Impl: doc.nodes → Commands
  logInfo(\"Watcher\", \"Parsed \", kdlPath, \" stub packet len \", $result.len)

proc collectOrdersLocal*(gameDir: string): seq[Proposal[DaemonModel]] =
  ## Walk houses/* /orders_pending.kdl → parse → proposals
  for path in walkDirRec(gameDir / \"houses\", relative = true):
    if path.endsWith(\"orders_pending.kdl\"):
      let packet = parseOrdersKdl(path)
      # Proposal order_received w/ gameId from gameDir basename, house from path
      let houseId = path.extractFilename().split(\"_\")[0]  # Stub
      let p = Proposal[DaemonModel](name: \"order_received\", payload: proc(model: var DaemonModel) =
        # Old OrderReceived logic
        model.pendingOrders[\"stub\"] += packet.len
      )
      result.add(p)
      # Del file after parse
      discard tryRemoveFile(path)
  logInfo(\"Watcher\", \"Collected \", $result.len, \" order proposals from \", gameDir)