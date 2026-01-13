proc resolveTurnCmd(gameId: GameId): DaemonCmd =
  () => async:
    let dbPath = \"data/games/\" & gameId & \"/ec4x.db\"  # Stub
    let reader = persistence.reader
    var state = reader.loadGameState(dbPath)
    let commands = initTable[HouseId, CommandPacket]()  # Empty stub
    let result = engine.resolveTurnDeterministic(state, commands)
    # Save stub
    persistence.writer.saveGameState(state)  # Stub
    Proposal[DaemonModel](
      name: \"turn_resolved\",
      payload: proc(model: var DaemonModel) =
        model.resolving.excl(gameId)
        model.pendingOrders[gameId] = 0
        daemonLoop.queueCmd(publishResultsCmd(gameId))
    )

proc publishResultsCmd(gameId: GameId): DaemonCmd =
  () => async:
    # Stub
    logInfo(\"Daemon\", \"Published results stub for \", gameId)
    Proposal[DaemonModel](name: \"results_published\", payload: proc(model: var DaemonModel) = discard)