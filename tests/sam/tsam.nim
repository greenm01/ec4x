## SAM Pattern Tests
##
## Unit tests for the SAM (State-Action-Model) implementation.
## Tests cover:
## - Core types and proposals
## - Acceptors
## - Reactors
## - NAPs (Next-Action Predicates)
## - Time travel/history
## - Integration scenarios

import std/[unittest, options, tables]
import ../../src/player/sam/sam_pkg

suite "SAM Types":
  
  test "create empty proposal":
    let p = emptyProposal()
    check p.kind == pkNone
    check p.actionName == "none"
  
  test "create quit proposal":
    let p = quitProposal()
    check p.kind == pkQuit
    check p.actionName == "quit"
  
  test "create navigation proposal":
    let p = navigationProposal(ord(ViewMode.Map), "switchToMap")
    check p.kind == pkNavigation
    check p.navMode == ord(ViewMode.Map)
    check p.actionName == "switchToMap"
  
  test "create cursor proposal":
    let p = cursorProposal(5, -3, "moveCursor")
    check p.kind == pkNavigation
    check p.navCursor == (5, -3)
  
  test "create selection proposal":
    let p = selectionProposal(3, "selectItem")
    check p.kind == pkSelection
    check p.selectIdx == 3
  
  test "create scroll proposal":
    let p = scrollProposal(2, -1, "scroll")
    check p.kind == pkViewportScroll
    check p.scrollDelta == (2, -1)
  
  test "create game action proposal":
    let p = gameActionProposal("buildShip", "{\"shipType\":\"destroyer\"}")
    check p.kind == pkGameAction
    check p.gameActionType == "buildShip"
    check p.gameActionData == "{\"shipType\":\"destroyer\"}"

suite "TUI Model":
  
  test "init model with defaults":
    let model = initTuiModel()
    check model.mode == ViewMode.Colonies
    check model.selectedIdx == 0
    check model.running == true
    check model.turn == 1
  
  test "hex coordinate operations":
    let coord = hexCoord(3, -2)
    check coord.q == 3
    check coord.r == -2
  
  test "hex neighbor - east":
    let coord = hexCoord(0, 0)
    let east = coord.neighbor(HexDirection.East)
    check east == (1, 0)
  
  test "hex neighbor - west":
    let coord = hexCoord(0, 0)
    let west = coord.neighbor(HexDirection.West)
    check west == (-1, 0)
  
  test "hex neighbor - northeast":
    let coord = hexCoord(0, 0)
    let ne = coord.neighbor(HexDirection.NorthEast)
    check ne == (1, -1)
  
  test "hex neighbor - southwest":
    let coord = hexCoord(0, 0)
    let sw = coord.neighbor(HexDirection.SouthWest)
    check sw == (-1, 1)
  
  test "current list length - empty":
    let model = initTuiModel()
    check model.currentListLength() == 0
  
  test "current list length - colonies":
    var model = initTuiModel()
    model.mode = ViewMode.Colonies
    model.colonies.add(ColonyInfo(systemId: 1, systemName: "Test", population: 100, production: 10, owner: 1))
    check model.currentListLength() == 1
  
  test "system at coordinate":
    var model = initTuiModel()
    model.systems[(0, 0)] = SystemInfo(id: 1, name: "Sol", coords: (0, 0), ring: 0)
    
    let found = model.systemAt((0, 0))
    check found.isSome
    check found.get.name == "Sol"
    
    let notFound = model.systemAt((99, 99))
    check notFound.isNone

suite "SAM Instance":
  
  test "create instance":
    var sam = initSam[TuiModel]()
    check sam.acceptors.len == 0
    check sam.reactors.len == 0
  
  test "create instance with history":
    var sam = initSamWithHistory[TuiModel](50)
    check sam.history.isSome
  
  test "set initial state":
    var sam = initSam[TuiModel]()
    var model = initTuiModel()
    model.turn = 5
    sam.setInitialState(model)
    check sam.state.turn == 5
  
  test "add acceptor":
    var sam = initSam[TuiModel]()
    sam.addAcceptor(proc(m: var TuiModel, p: Proposal) = discard)
    check sam.acceptors.len == 1
  
  test "add reactor":
    var sam = initSam[TuiModel]()
    sam.addReactor(proc(m: var TuiModel) = discard)
    check sam.reactors.len == 1
  
  test "add nap":
    var sam = initSam[TuiModel]()
    sam.addNap(proc(m: TuiModel): Option[Proposal] = none(Proposal))
    check sam.naps.len == 1

suite "Acceptors":
  
  test "navigation acceptor - mode switch":
    var model = initTuiModel()
    model.mode = ViewMode.Colonies
    
    let proposal = actionSwitchMode(ViewMode.Map)
    navigationAcceptor(model, proposal)
    
    check model.mode == ViewMode.Map
    check model.selectedIdx == 0
  
  test "navigation acceptor - cursor move by direction":
    var model = initTuiModel()
    model.mapState.cursor = (0, 0)
    
    let proposal = actionMoveCursor(HexDirection.East)
    navigationAcceptor(model, proposal)
    
    check model.mapState.cursor == (1, 0)
  
  test "navigation acceptor - jump home":
    var model = initTuiModel()
    model.mapState.cursor = (5, 5)
    model.homeworld = some((0, 0))
    
    let proposal = actionJumpHome()
    navigationAcceptor(model, proposal)
    
    check model.mapState.cursor == (0, 0)
  
  test "selection acceptor - select in map mode":
    var model = initTuiModel()
    model.mode = ViewMode.Map
    model.mapState.cursor = (3, -1)
    
    let proposal = actionSelect()
    selectionAcceptor(model, proposal)
    
    check model.mapState.selected.isSome
    check model.mapState.selected.get == (3, -1)
  
  test "selection acceptor - deselect":
    var model = initTuiModel()
    model.mapState.selected = some((1, 2))
    
    let proposal = actionDeselect()
    selectionAcceptor(model, proposal)
    
    check model.mapState.selected.isNone
  
  test "selection acceptor - list up":
    var model = initTuiModel()
    model.selectedIdx = 3
    
    let proposal = actionListUp()
    selectionAcceptor(model, proposal)
    
    check model.selectedIdx == 2
  
  test "selection acceptor - list down":
    var model = initTuiModel()
    model.selectedIdx = 1
    model.colonies.add(ColonyInfo(systemId: 1, systemName: "A", population: 100, production: 10, owner: 1))
    model.colonies.add(ColonyInfo(systemId: 2, systemName: "B", population: 100, production: 10, owner: 1))
    model.colonies.add(ColonyInfo(systemId: 3, systemName: "C", population: 100, production: 10, owner: 1))
    
    let proposal = actionListDown()
    selectionAcceptor(model, proposal)
    
    check model.selectedIdx == 2
  
  test "game action acceptor - quit":
    var model = initTuiModel()
    model.running = true
    
    let proposal = quitProposal()
    gameActionAcceptor(model, proposal)
    
    check model.running == false

suite "Reactors":
  
  test "selection bounds reactor - clamp high":
    var model = initTuiModel()
    model.mode = ViewMode.Colonies
    model.selectedIdx = 10
    model.colonies.add(ColonyInfo(systemId: 1, systemName: "A", population: 100, production: 10, owner: 1))
    model.colonies.add(ColonyInfo(systemId: 2, systemName: "B", population: 100, production: 10, owner: 1))
    
    selectionBoundsReactor(model)
    
    check model.selectedIdx == 1  # clamped to max index
  
  test "selection bounds reactor - clamp low":
    var model = initTuiModel()
    model.selectedIdx = -5
    
    selectionBoundsReactor(model)
    
    check model.selectedIdx == 0

suite "History/Time Travel":
  
  test "init history":
    var h = initHistory[TuiModel](10)
    check h.maxEntries == 10
    check h.entries.len == 0
    check h.currentIdx == -1
  
  test "snap state":
    var h = initHistory[TuiModel](10)
    var model = initTuiModel()
    model.turn = 1
    h.snap(model, "init")
    
    check h.entries.len == 1
    check h.currentIdx == 0
  
  test "travel to index":
    var h = initHistory[TuiModel](10)
    var model1 = initTuiModel()
    model1.turn = 1
    h.snap(model1, "t1")
    
    var model2 = initTuiModel()
    model2.turn = 2
    h.snap(model2, "t2")
    
    let state = h.travel(0)
    check state.isSome
    check state.get.turn == 1
  
  test "has next/prev":
    var h = initHistory[TuiModel](10)
    var model = initTuiModel()
    h.snap(model, "t1")
    h.snap(model, "t2")
    h.snap(model, "t3")
    
    check h.hasNext == false  # at end
    discard h.travel(1)
    check h.hasNext == true
    check h.hasPrev == true
    discard h.travel(0)
    check h.hasPrev == false  # at start
  
  test "max entries limit":
    var h = initHistory[TuiModel](3)
    var model = initTuiModel()
    
    for i in 1..5:
      model.turn = i
      h.snap(model, "t" & $i)
    
    check h.entries.len == 3
    check h.entries[0].state.turn == 3  # oldest remaining

suite "Full SAM Present Cycle":
  
  test "present updates model via acceptor":
    var sam = initSam[TuiModel]()
    var model = initTuiModel()
    model.mode = ViewMode.Colonies
    
    sam.addAcceptor(navigationAcceptor)
    sam.setInitialState(model)
    
    let proposal = actionSwitchMode(ViewMode.Map)
    sam.present(proposal)
    
    check sam.state.mode == ViewMode.Map
  
  test "present runs reactors after acceptors":
    var sam = initSam[TuiModel]()
    var model = initTuiModel()
    model.selectedIdx = 100
    model.mode = ViewMode.Colonies
    
    sam.addReactor(selectionBoundsReactor)
    sam.setInitialState(model)
    sam.present(emptyProposal())
    
    check sam.state.selectedIdx == 0  # clamped
  
  test "present records history":
    var sam = initSamWithHistory[TuiModel](10)
    var model = initTuiModel()
    model.turn = 1
    
    sam.addAcceptor(proc(m: var TuiModel, p: Proposal) =
      if p.kind == pkNavigation:
        m.turn += 1
    )
    sam.setInitialState(model)
    
    # Present a few actions
    sam.present(actionSwitchMode(ViewMode.Map))
    sam.present(actionSwitchMode(ViewMode.Colonies))
    
    check sam.history.get.entries.len == 3  # initial + 2 actions

suite "Action Creators":
  
  test "actionSwitchMode creates correct proposal":
    let p = actionSwitchMode(ViewMode.Fleets)
    check p.kind == pkNavigation
    check p.navMode == ord(ViewMode.Fleets)
    check p.actionName == ActionNavigateMode
  
  test "actionMoveCursor creates correct proposal":
    let p = actionMoveCursor(HexDirection.NorthWest)
    check p.kind == pkNavigation
    check p.navMode == ord(HexDirection.NorthWest)
    check p.actionName == ActionMoveCursor
  
  test "actionEndTurn creates correct proposal":
    let p = actionEndTurn()
    check p.kind == pkEndTurn
    check p.actionName == "endTurn"
  
  test "actionResize creates correct proposal":
    let p = actionResize(120, 40)
    check p.kind == pkViewportScroll
    check p.scrollDelta == (120, 40)
    check p.actionName == ActionResize

suite "Key Mapping":
  
  test "map Q key to quit":
    let model = initTuiModel()
    let result = mapKeyToAction(KeyCode.KeyQ, model)
    check result.isSome
    check result.get.kind == pkQuit
  
  test "map mode switch keys":
    var model = initTuiModel()
    
    var result = mapKeyToAction(KeyCode.KeyC, model)
    check result.isSome
    check result.get.navMode == ord(ViewMode.Colonies)
    
    result = mapKeyToAction(KeyCode.KeyF, model)
    check result.get.navMode == ord(ViewMode.Fleets)
    
    result = mapKeyToAction(KeyCode.KeyM, model)
    check result.get.navMode == ord(ViewMode.Map)
  
  test "map arrow keys in map mode":
    var model = initTuiModel()
    model.mode = ViewMode.Map
    
    let result = mapKeyToAction(KeyCode.KeyRight, model)
    check result.isSome
    check result.get.actionName == ActionMoveCursor
  
  test "map arrow keys in list mode":
    var model = initTuiModel()
    model.mode = ViewMode.Colonies
    
    let upResult = mapKeyToAction(KeyCode.KeyUp, model)
    check upResult.isSome
    check upResult.get.actionName == ActionListUp
    
    let downResult = mapKeyToAction(KeyCode.KeyDown, model)
    check downResult.isSome
    check downResult.get.actionName == ActionListDown

when isMainModule:
  # Run all tests
  discard
