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
    check p.actionKind == ActionKind.navigateMode
  
  test "create quit proposal":
    let p = quitProposal()
    check p.kind == pkQuit
    check p.actionKind == ActionKind.quit
  
  test "create navigation proposal":
    let p = navigationProposal(ord(ViewMode.Overview))
    check p.kind == pkNavigation
    check p.navMode == ord(ViewMode.Overview)
    check p.actionKind == ActionKind.navigateMode
  
  test "create cursor proposal":
    let p = cursorProposal(5, -3)
    check p.kind == pkNavigation
    check p.navCursor == (5, -3)
    check p.actionKind == ActionKind.moveCursor
  
  test "create selection proposal":
    let p = selectionProposal(3)
    check p.kind == pkSelection
    check p.selectIdx == 3
    check p.actionKind == ActionKind.select
  
  test "create scroll proposal":
    let p = scrollProposal(2, -1)
    check p.kind == pkViewportScroll
    check p.scrollDelta == (2, -1)
    check p.actionKind == ActionKind.scroll
  
  test "create game action proposal":
    let p = gameActionProposal(ActionKind.startOrderMove,
      "{\"shipType\":\"destroyer\"}")
    check p.kind == pkGameAction
    check p.actionKind == ActionKind.startOrderMove
    check p.gameActionData == "{\"shipType\":\"destroyer\"}"

suite "TUI Model":
  
  test "init model with defaults":
    let model = initTuiModel()
    check model.ui.mode == ViewMode.Planets
    check model.ui.selectedIdx == 0
    check model.ui.running == true
    check model.view.turn == 1
  
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
    model.ui.mode = ViewMode.Planets
    model.view.colonies.add(ColonyInfo(
      colonyId: 1,
      systemId: 1,
      systemName: "Test",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    check model.currentListLength() == 1
  
  test "system at coordinate":
    var model = initTuiModel()
    model.view.systems[(0, 0)] = SystemInfo(
      id: 1,
      name: "Sol",
      coords: (0, 0),
      ring: 0
    )
    
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
    model.view.turn = 5
    sam.setInitialState(model)
    check sam.state.view.turn == 5
  
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
    model.ui.mode = ViewMode.Planets
    
    let proposal = actionSwitchMode(ViewMode.Overview)
    navigationAcceptor(model, proposal)
    
    check model.ui.mode == ViewMode.Overview
    check model.ui.selectedIdx == 0
  
  test "navigation acceptor - cursor move by direction":
    var model = initTuiModel()
    model.ui.mapState.cursor = (0, 0)
    
    let proposal = actionMoveCursor(HexDirection.East)
    navigationAcceptor(model, proposal)
    
    check model.ui.mapState.cursor == (1, 0)
  
  test "navigation acceptor - jump home":
    var model = initTuiModel()
    model.ui.mapState.cursor = (5, 5)
    model.view.homeworld = some((0, 0))
    
    let proposal = actionJumpHome()
    navigationAcceptor(model, proposal)
    
    check model.ui.mapState.cursor == (0, 0)
  
  test "selection acceptor - select in map mode":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Overview
    model.ui.mapState.cursor = (3, -1)
    
    let proposal = actionSelect()
    selectionAcceptor(model, proposal)
    
    check model.ui.mapState.selected.isSome
    check model.ui.mapState.selected.get == (3, -1)
  
  test "selection acceptor - deselect":
    var model = initTuiModel()
    model.ui.mapState.selected = some((1, 2))
    
    let proposal = actionDeselect()
    selectionAcceptor(model, proposal)
    
    check model.ui.mapState.selected.isNone
  
  test "selection acceptor - list up":
    var model = initTuiModel()
    model.ui.selectedIdx = 3
    
    let proposal = actionListUp()
    selectionAcceptor(model, proposal)
    
    check model.ui.selectedIdx == 2
  
  test "selection acceptor - list down":
    var model = initTuiModel()
    model.ui.selectedIdx = 1
    model.view.colonies.add(ColonyInfo(
      colonyId: 1,
      systemId: 1,
      systemName: "A",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    model.view.colonies.add(ColonyInfo(
      colonyId: 2,
      systemId: 2,
      systemName: "B",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    model.view.colonies.add(ColonyInfo(
      colonyId: 3,
      systemId: 3,
      systemName: "C",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    
    let proposal = actionListDown()
    selectionAcceptor(model, proposal)
    
    check model.ui.selectedIdx == 2
  
  test "game action acceptor - quit":
    var model = initTuiModel()
    model.ui.running = true
    
    let proposal = quitProposal()
    gameActionAcceptor(model, proposal)
    
    check model.ui.running == false

suite "Reactors":
  
  test "selection bounds reactor - clamp high":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    model.ui.selectedIdx = 10
    model.view.colonies.add(ColonyInfo(
      colonyId: 1,
      systemId: 1,
      systemName: "A",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    model.view.colonies.add(ColonyInfo(
      colonyId: 2,
      systemId: 2,
      systemName: "B",
      populationUnits: 100,
      industrialUnits: 10,
      owner: 1
    ))
    
    selectionBoundsReactor(model)
    
    check model.ui.selectedIdx == 1  # clamped to max index
  
  test "selection bounds reactor - clamp low":
    var model = initTuiModel()
    model.ui.selectedIdx = -5
    
    selectionBoundsReactor(model)
    
    check model.ui.selectedIdx == 0

suite "History/Time Travel":
  
  test "init history":
    var h = initHistory[TuiModel](10)
    check h.maxEntries == 10
    check h.entries.len == 0
    check h.currentIdx == -1
  
  test "snap state":
    var h = initHistory[TuiModel](10)
    var model = initTuiModel()
    model.view.turn = 1
    h.snap(model, ActionKind.navigateMode)
    
    check h.entries.len == 1
    check h.currentIdx == 0
  
  test "travel to index":
    var h = initHistory[TuiModel](10)
    var model1 = initTuiModel()
    model1.view.turn = 1
    h.snap(model1, ActionKind.navigateMode)
    
    var model2 = initTuiModel()
    model2.view.turn = 2
    h.snap(model2, ActionKind.navigateMode)
    
    let state = h.travel(0)
    check state.isSome
    check state.get.view.turn == 1
  
  test "has next/prev":
    var h = initHistory[TuiModel](10)
    var model = initTuiModel()
    h.snap(model, ActionKind.navigateMode)
    h.snap(model, ActionKind.navigateMode)
    h.snap(model, ActionKind.navigateMode)
    
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
      model.view.turn = i
      h.snap(model, ActionKind.navigateMode)
    
    check h.entries.len == 3
    check h.entries[0].state.view.turn == 3  # oldest remaining

suite "Full SAM Present Cycle":
  
  test "present updates model via acceptor":
    var sam = initSam[TuiModel]()
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    
    sam.addAcceptor(navigationAcceptor)
    sam.setInitialState(model)
    
    let proposal = actionSwitchMode(ViewMode.Overview)
    sam.present(proposal)
    
    check sam.state.ui.mode == ViewMode.Overview
  
  test "present runs reactors after acceptors":
    var sam = initSam[TuiModel]()
    var model = initTuiModel()
    model.ui.selectedIdx = 100
    model.ui.mode = ViewMode.Planets
    
    sam.addReactor(selectionBoundsReactor)
    sam.setInitialState(model)
    sam.present(emptyProposal())
    
    check sam.state.ui.selectedIdx == 0  # clamped
  
  test "present records history":
    var sam = initSamWithHistory[TuiModel](10)
    var model = initTuiModel()
    model.view.turn = 1
    
    sam.addAcceptor(proc(m: var TuiModel, p: Proposal) =
      if p.kind == pkNavigation:
        m.view.turn += 1
    )
    sam.setInitialState(model)
    
    # Present a few actions
    sam.present(actionSwitchMode(ViewMode.Overview))
    sam.present(actionSwitchMode(ViewMode.Planets))
    
    check sam.history.get.entries.len == 3  # initial + 2 actions

suite "Action Creators":
  
  test "actionSwitchMode creates correct proposal":
    let p = actionSwitchMode(ViewMode.Fleets)
    check p.kind == pkNavigation
    check p.navMode == ord(ViewMode.Fleets)
    check p.actionKind == ActionKind.navigateMode
  
  test "actionMoveCursor creates correct proposal":
    let p = actionMoveCursor(HexDirection.NorthWest)
    check p.kind == pkNavigation
    check p.navMode == ord(HexDirection.NorthWest)
    check p.actionKind == ActionKind.moveCursor
  
  test "actionEndTurn creates correct proposal":
    let p = actionEndTurn()
    check p.kind == pkEndTurn
    check p.actionKind == ActionKind.endTurn
  
  test "actionResize creates correct proposal":
    let p = actionResize(120, 40)
    check p.kind == pkViewportScroll
    check p.scrollDelta == (120, 40)
    check p.actionKind == ActionKind.resize

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
    check result.get.navMode == ord(ViewMode.Planets)
    
    result = mapKeyToAction(KeyCode.KeyF, model)
    check result.get.navMode == ord(ViewMode.Fleets)
    
    result = mapKeyToAction(KeyCode.KeyM, model)
    check result.get.navMode == ord(ViewMode.Overview)
  
  test "map arrow keys in map mode":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Overview
    
    let result = mapKeyToAction(KeyCode.KeyRight, model)
    check result.isSome
    check result.get.actionKind == ActionKind.moveCursor
  
  test "map arrow keys in list mode":
    var model = initTuiModel()
    model.ui.mode = ViewMode.Planets
    
    let upResult = mapKeyToAction(KeyCode.KeyUp, model)
    check upResult.isSome
    check upResult.get.actionKind == ActionKind.listUp
    
    let downResult = mapKeyToAction(KeyCode.KeyDown, model)
    check downResult.isSome
    check downResult.get.actionKind == ActionKind.listDown

when isMainModule:
  # Run all tests
  discard
