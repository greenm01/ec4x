# TEA Pattern Implementation Guide

## Overview

This guide explains how to implement **The Elm Architecture (TEA)** pattern in Nim for both the EC4X client and daemon. TEA provides a predictable, testable, and maintainable architecture for managing application state.

## What is TEA?

**The Elm Architecture** is a pattern for building applications with three core components:

1. **Model** - Application state (data)
2. **Message** - Events that describe state changes
3. **Update** - Pure function that transforms state based on messages

Additionally:
- **Commands** - Async effects that produce messages
- **View** - Renders the model (for UI applications)

## Why TEA for EC4X?

**Benefits:**
- ✅ **Predictable**: All state changes go through one function
- ✅ **Testable**: Pure `update()` function easy to unit test
- ✅ **Single-threaded**: No race conditions or locks
- ✅ **Non-blocking**: Async I/O doesn't freeze the app
- ✅ **Concurrent**: Handle multiple operations simultaneously
- ✅ **Debuggable**: Clear message flow, easy to trace

## Core Pattern

### Minimal TEA Loop

```nim
import asyncdispatch, options

# 1. Model - Application State
type
  Model = object
    counter: int
    status: string

# 2. Message - Events
type
  Msg = enum
    Increment
    Decrement
    AsyncTaskComplete(result: string)

# 3. Update - Pure State Transition
proc update(msg: Msg, model: Model): (Model, Option[Cmd]) =
  case msg.kind:
  of Increment:
    var newModel = model
    newModel.counter += 1
    return (newModel, none(Cmd))

  of Decrement:
    var newModel = model
    newModel.counter -= 1
    return (newModel, none(Cmd))

  of AsyncTaskComplete:
    var newModel = model
    newModel.status = msg.result
    return (newModel, none(Cmd))

# 4. Commands - Async Effects
type
  Cmd = proc(): Future[Msg] {.async.}

# 5. Main Loop
proc mainLoop() {.async.} =
  var model = Model(counter: 0, status: "idle")

  while true:
    # Get next message (from user input, timer, etc.)
    let msg = await getNextMessage()

    # Update model
    let (newModel, cmd) = update(msg, model)
    model = newModel

    # Execute command if present
    if cmd.isSome:
      let future = cmd.get()
      # Handle async result...
```

## Advanced Pattern: Message Queue

For applications handling multiple concurrent events:

```nim
import asyncdispatch, deques

type
  MsgQueue = ref object
    queue: Deque[Msg]

proc newMsgQueue(): MsgQueue =
  MsgQueue(queue: initDeque[Msg]())

proc send(mq: MsgQueue, msg: Msg) =
  mq.queue.addLast(msg)

proc recv(mq: MsgQueue): Future[Msg] {.async.} =
  while mq.queue.len == 0:
    await sleepAsync(1)
  return mq.queue.popFirst()

proc mainLoop() {.async.} =
  var model = initModel()
  var msgQueue = newMsgQueue()
  var pendingCmds: seq[Future[Msg]] = @[]

  # Background tasks send messages to queue
  asyncCheck backgroundTask1(msgQueue)
  asyncCheck backgroundTask2(msgQueue)

  while true:
    # Wait for next message
    let msg = await msgQueue.recv()

    # Update model (pure)
    let (newModel, newCmds) = update(msg, model)
    model = newModel

    # Start new async commands
    for cmd in newCmds:
      pendingCmds.add(cmd())

    # Check completed commands
    var completed: seq[int] = @[]
    for i, fut in pendingCmds:
      if fut.finished:
        completed.add(i)
        msgQueue.send(fut.read())

    # Remove completed
    for i in countdown(completed.high, 0):
      pendingCmds.delete(completed[i])

    await sleepAsync(1)
```

## Daemon Implementation

### Model

```nim
import tables, sets, times

type
  GameId = string
  HouseId = string

  GameInfo = object
    id: GameId
    turn: int
    deadline: Time
    phase: GamePhase

  DaemonModel = object
    games: Table[GameId, GameInfo]
    resolving: HashSet[GameId]
    pendingOrders: Table[GameId, seq[Order]]
    transports: Table[GameId, Transport]
    nostrConnections: Table[string, WebSocket]

proc initModel(): DaemonModel =
  DaemonModel(
    games: initTable[GameId, GameInfo](),
    resolving: initHashSet[GameId](),
    pendingOrders: initTable[GameId, seq[Order]](),
    transports: initTable[GameId, Transport](),
    nostrConnections: initTable[string, WebSocket]()
  )
```

### Messages

```nim
type
  DaemonMsg = object
    case kind: DaemonMsgKind
    of dmTick:
      timestamp: Time
    of dmOrderReceived:
      gameId: GameId
      houseId: HouseId
      order: Order
    of dmTurnResolving:
      gameIdResolving: GameId
    of dmTurnResolved:
      gameIdResolved: GameId
      result: TurnResult
    of dmResultsPublished:
      gameIdPublished: GameId
    of dmGameDiscovered:
      gameDir: string
    of dmTransportError:
      gameIdError: GameId
      error: string

  DaemonMsgKind = enum
    dmTick
    dmOrderReceived
    dmTurnResolving
    dmTurnResolved
    dmResultsPublished
    dmGameDiscovered
    dmTransportError
```

### Update Function

```nim
proc update(msg: DaemonMsg, model: DaemonModel): (DaemonModel, seq[Cmd]) =
  case msg.kind:

  of dmTick:
    # Check deadlines
    var cmds: seq[Cmd] = @[]
    for gameId, game in model.games:
      if game.deadline <= msg.timestamp and gameId notin model.resolving:
        cmds.add(Cmd.msg(DaemonMsg(kind: dmTurnResolving, gameIdResolving: gameId)))
    return (model, cmds)

  of dmOrderReceived:
    var newModel = model
    if msg.gameId notin newModel.pendingOrders:
      newModel.pendingOrders[msg.gameId] = @[]
    newModel.pendingOrders[msg.gameId].add(msg.order)

    # Check if ready to resolve
    if isReadyForResolution(newModel, msg.gameId):
      let cmd = Cmd.msg(DaemonMsg(kind: dmTurnResolving, gameIdResolving: msg.gameId))
      return (newModel, @[cmd])
    else:
      return (newModel, @[])

  of dmTurnResolving:
    var newModel = model
    newModel.resolving.incl(msg.gameIdResolving)

    # Kick off async resolution
    let cmd = Cmd.perform(
      resolveTurnAsync(msg.gameIdResolving),
      proc(result: TurnResult): DaemonMsg =
        DaemonMsg(kind: dmTurnResolved, gameIdResolved: msg.gameIdResolving, result: result)
    )
    return (newModel, @[cmd])

  of dmTurnResolved:
    var newModel = model
    newModel.resolving.excl(msg.gameIdResolved)
    newModel.games[msg.gameIdResolved].turn += 1
    newModel.pendingOrders.del(msg.gameIdResolved)

    # Kick off async publishing
    let cmd = Cmd.perform(
      publishResultsAsync(msg.gameIdResolved, msg.result),
      proc(): DaemonMsg =
        DaemonMsg(kind: dmResultsPublished, gameIdPublished: msg.gameIdResolved)
    )
    return (newModel, @[cmd])

  of dmResultsPublished:
    # Results published, nothing to do
    return (model, @[])

  of dmGameDiscovered:
    # Load game from directory
    let cmd = Cmd.perform(
      loadGameAsync(msg.gameDir),
      proc(game: GameInfo): DaemonMsg =
        # Add to model on next update
        DaemonMsg(kind: dmGameLoaded, game: game)
    )
    return (model, @[cmd])

  of dmTransportError:
    echo "Transport error for game ", msg.gameIdError, ": ", msg.error
    # Could retry, pause game, etc.
    return (model, @[])
```

### Commands (Async Effects)

```nim
type
  Cmd = proc(): Future[DaemonMsg] {.async.}

# Helper: Simple message command
proc msg(m: DaemonMsg): Cmd =
  return proc(): Future[DaemonMsg] {.async.} =
    return m

# Helper: Perform async operation
proc perform[T](
  task: Future[T],
  toMsg: proc(result: T): DaemonMsg
): Cmd =
  return proc(): Future[DaemonMsg] {.async.} =
    let result = await task
    return toMsg(result)

# Async turn resolution
proc resolveTurnAsync(gameId: GameId): Future[TurnResult] {.async.} =
  let dbPath = getGameDbPath(gameId)
  let db = await openDbAsync(dbPath)

  let state = await db.loadGameState()
  let orders = await db.loadOrders()

  # Pure game engine (fast)
  let result = engine.resolveTurn(state, orders)

  # Save results
  await db.saveGameState(result.newState)
  await db.saveDeltas(result.deltas)
  await db.updateIntelTables(result)
  await db.close()

  return result

# Async result publishing
proc publishResultsAsync(gameId: GameId, result: TurnResult): Future[void] {.async.} =
  let transport = getTransport(gameId)

  for house in result.houses:
    let delta = generateDelta(result, house)
    await transport.publish(gameId, house, delta)
```

### Main Loop

```nim
proc daemonMain() {.async.} =
  var model = initModel()
  var msgQueue = newAsyncQueue[DaemonMsg]()
  var pendingCmds: seq[Future[DaemonMsg]] = @[]

  # Start background tasks
  asyncCheck tickTimer(msgQueue)              # Send Tick every 30s
  asyncCheck discoverGames(msgQueue)          # Scan for new games
  asyncCheck listenNostr(msgQueue)            # WebSocket subscriptions
  asyncCheck watchFilesystem(msgQueue)        # File watchers

  echo "Daemon started"

  while true:
    # Wait for next message (non-blocking)
    let msg = await msgQueue.recv()

    # Update model (pure, instant)
    let (newModel, newCmds) = update(msg, model)
    model = newModel

    # Execute new commands
    for cmd in newCmds:
      pendingCmds.add(cmd())

    # Check completed commands
    var completed: seq[int] = @[]
    for i, fut in pendingCmds:
      if fut.finished:
        completed.add(i)
        let resultMsg = fut.read()
        await msgQueue.send(resultMsg)

    # Remove completed
    for i in countdown(completed.high, 0):
      pendingCmds.delete(completed[i])

    # Yield to async scheduler
    await sleepAsync(1)

when isMainModule:
  waitFor daemonMain()
```

### Background Tasks

```nim
proc tickTimer(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  while true:
    await sleepAsync(30_000)  # 30 seconds
    await msgQueue.send(DaemonMsg(kind: dmTick, timestamp: getTime()))

proc discoverGames(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  while true:
    await sleepAsync(300_000)  # 5 minutes
    for gameDir in walkDirs("/var/ec4x/games/*"):
      if fileExists(gameDir / "ec4x.db"):
        await msgQueue.send(DaemonMsg(kind: dmGameDiscovered, gameDir: gameDir))

proc listenNostr(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  let ws = await newWebSocket("wss://relay.example.com")

  # Subscribe to all games
  # ...

  while true:
    let packet = await ws.receiveStrPacket()
    let event = parseNostrEvent(packet)

    if event.kind == 30001:  # Order packet
      let order = decryptOrder(event)
      await msgQueue.send(DaemonMsg(
        kind: dmOrderReceived,
        gameId: event.getTag("g"),
        houseId: event.getTag("h"),
        order: order
      ))

proc watchFilesystem(msgQueue: AsyncQueue[DaemonMsg]) {.async.} =
  # Use inotify or similar
  while true:
    let events = await pollFileEvents()
    for event in events:
      if event.name.endsWith("orders_pending.json"):
        let order = parseOrderFile(event.path)
        await msgQueue.send(DaemonMsg(
          kind: dmOrderReceived,
          gameId: extractGameId(event.path),
          houseId: extractHouseId(event.path),
          order: order
        ))
```

## Client Implementation

### Model

```nim
type
  ViewMode = enum
    vmMap
    vmOrders
    vmHistory
    vmDiplomacy

  ClientModel = object
    gameId: GameId
    houseId: HouseId
    gameState: GameState
    currentView: ViewMode
    pendingOrders: seq[Order]
    transport: Transport
    statusMessage: string
```

### Messages

```nim
type
  ClientMsg = object
    case kind: ClientMsgKind
    of cmGameStateReceived:
      state: GameState
    of cmKeyPressed:
      key: char
    of cmOrderAdded:
      order: Order
    of cmOrdersSubmitted:
      discard
    of cmViewChanged:
      newView: ViewMode
    of cmError:
      errorMsg: string

  ClientMsgKind = enum
    cmGameStateReceived
    cmKeyPressed
    cmOrderAdded
    cmOrdersSubmitted
    cmViewChanged
    cmError
```

### Update

```nim
proc update(msg: ClientMsg, model: ClientModel): (ClientModel, seq[Cmd]) =
  case msg.kind:

  of cmGameStateReceived:
    var newModel = model
    newModel.gameState = msg.state
    newModel.statusMessage = "Turn " & $msg.state.turn & " loaded"
    return (newModel, @[])

  of cmKeyPressed:
    case msg.key:
    of 'm':
      var newModel = model
      newModel.currentView = vmMap
      return (newModel, @[])
    of 'o':
      var newModel = model
      newModel.currentView = vmOrders
      return (newModel, @[])
    of 'q':
      quit(0)
    else:
      return (model, @[])

  of cmOrderAdded:
    var newModel = model
    newModel.pendingOrders.add(msg.order)
    newModel.statusMessage = "Order added (" & $newModel.pendingOrders.len & " total)"
    return (newModel, @[])

  of cmOrdersSubmitted:
    let cmd = Cmd.perform(
      submitOrdersAsync(model.transport, model.gameId, model.houseId, model.pendingOrders),
      proc(): ClientMsg =
        ClientMsg(kind: cmOrdersCommitted)
    )
    return (model, @[cmd])

  of cmViewChanged:
    var newModel = model
    newModel.currentView = msg.newView
    return (newModel, @[])

  of cmError:
    var newModel = model
    newModel.statusMessage = "Error: " & msg.errorMsg
    return (newModel, @[])
```

### View (Terminal UI)

```nim
import illwill

proc view(model: ClientModel) =
  illwillInit()

  # Render based on current view
  case model.currentView:
  of vmMap:
    renderMap(model.gameState)
  of vmOrders:
    renderOrders(model.pendingOrders)
  of vmHistory:
    renderHistory(model.gameState)
  of vmDiplomacy:
    renderDiplomacy(model.gameState)

  # Status bar
  setCursorPos(0, terminalHeight() - 1)
  echo model.statusMessage

  illwillDeinit()
```

### Main Loop

```nim
proc clientMain() {.async.} =
  var model = initClientModel()
  var msgQueue = newAsyncQueue[ClientMsg]()
  var pendingCmds: seq[Future[ClientMsg]] = @[]

  # Start background tasks
  asyncCheck listenForGameUpdates(msgQueue, model.transport)
  asyncCheck handleKeyboard(msgQueue)

  while true:
    # Render current state
    view(model)

    # Process messages
    let msg = await msgQueue.recv()
    let (newModel, newCmds) = update(msg, model)
    model = newModel

    # Execute commands
    for cmd in newCmds:
      pendingCmds.add(cmd())

    # Check completed commands
    # ... (same pattern as daemon)

    await sleepAsync(16)  # ~60 FPS for UI
```

## Testing TEA Applications

### Unit Testing Update Function

```nim
import unittest

test "order received adds to pending orders":
  let model = ClientModel(
    gameId: "game-1",
    houseId: "house-a",
    pendingOrders: @[]
  )

  let order = Order(fleetId: "fleet-1", orderType: foMove)
  let msg = ClientMsg(kind: cmOrderAdded, order: order)

  let (newModel, cmds) = update(msg, model)

  check newModel.pendingOrders.len == 1
  check newModel.pendingOrders[0] == order
  check cmds.len == 0

test "turn resolving marks game as resolving":
  let model = DaemonModel(
    games: {"game-1": GameInfo(id: "game-1")}.toTable,
    resolving: initHashSet[GameId]()
  )

  let msg = DaemonMsg(kind: dmTurnResolving, gameIdResolving: "game-1")
  let (newModel, cmds) = update(msg, model)

  check "game-1" in newModel.resolving
  check cmds.len == 1  # Should kick off async resolution
```

### Integration Testing

```nim
test "full turn cycle":
  var model = initModel()

  # Submit orders
  let (m1, c1) = update(
    DaemonMsg(kind: dmOrderReceived, gameId: "g1", order: order1),
    model
  )

  # Should not resolve yet (need more orders)
  check c1.len == 0

  # Submit final order
  let (m2, c2) = update(
    DaemonMsg(kind: dmOrderReceived, gameId: "g1", order: order2),
    m1
  )

  # Should trigger resolution
  check c2.len == 1
  check c2[0] is TurnResolving
```

## Best Practices

### 1. Keep Update Pure

```nim
# GOOD - Pure function
proc update(msg: Msg, model: Model): (Model, seq[Cmd]) =
  var newModel = model
  newModel.counter += 1
  return (newModel, @[])

# BAD - Side effects in update
proc update(msg: Msg, model: Model): (Model, seq[Cmd]) =
  echo "Counter incremented"  # Don't log here!
  writeFile("state.json", $model)  # Don't do I/O here!
  return (model, @[])
```

### 2. Use Commands for All Side Effects

```nim
# GOOD - I/O in command
let cmd = Cmd.perform(
  writeFileAsync("state.json", $model),
  proc(): Msg = SaveComplete
)

# GOOD - Logging as command
let cmd = Cmd.perform(
  logAsync("Counter incremented"),
  proc(): Msg = LogComplete
)
```

### 3. Model Should Be Serializable

```nim
# GOOD - Simple data
type Model = object
  counter: int
  items: seq[string]

# BAD - Functions in model
type Model = object
  counter: int
  callback: proc()  # Can't serialize this!
```

### 4. Messages Should Be Self-Contained

```nim
# GOOD - All data in message
type Msg = object
  case kind: MsgKind
  of OrderReceived:
    gameId: string
    order: Order

# BAD - External references
type Msg = object
  case kind: MsgKind
  of OrderReceived:
    orderPtr: ptr Order  # Don't use pointers!
```

## Related Documentation

- [Daemon Design](./daemon.md) - Daemon-specific TEA implementation
- [Architecture Overview](./overview.md) - High-level system design
- [Data Flow](./dataflow.md) - How messages flow through the system
