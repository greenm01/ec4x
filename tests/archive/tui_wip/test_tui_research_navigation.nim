## Unit tests for research view selectable navigation behavior.

import std/[unittest, tables, options]

import ../../src/player/sam/sam_pkg
import ../../src/player/tui/data/research_projection
import ../../src/engine/types/tech

proc configureResearchState(model: var TuiModel) =
  model.ui.mode = ViewMode.Research
  model.ui.researchFocus = ResearchFocus.List
  model.view.treasury = 1000
  model.view.techLevels = some(TechLevel(
    el: 3,
    sl: 3,
    cst: 3,
    wep: 3,
    ter: 1,
    eli: 1,
    clk: 1,
    sld: 1,
    cic: 1,
    stl: 2,
    fc: 2,
    sc: 2,
    fd: 2,
    aco: 5
  ))
  model.view.researchPoints = some(ResearchPoints(
    economic: 0,
    science: 0,
    technology: initTable[TechField, int32]()
  ))
  model.ui.researchAllocation.economic = 10
  model.ui.researchAllocation.science = 10
  model.ui.researchAllocation.technology[TechField.WeaponsTech] = 10
  model.ui.researchAllocation.technology[TechField.ConstructionTech] = 10
  model.ui.researchAllocation.technology[TechField.FlagshipCommandTech] = 12
  model.ui.researchAllocation.technology[TechField.StrategicCommandTech] = 15
  model.ui.researchAllocation.technology[TechField.FighterDoctrine] = 15
  model.ui.researchAllocation.technology[TechField.StrategicLiftTech] = 10

proc findFirstSelectableIdx(model: TuiModel): int =
  if model.view.techLevels.isNone or model.view.researchPoints.isNone:
    return -1
  let levels = model.view.techLevels.get()
  let points = model.view.researchPoints.get()
  let items = researchItems()
  for idx in 0 ..< items.len:
    let item = items[idx]
    if not research_projection.isBlockedProjected(
      levels, points, model.ui.researchAllocation, item
    ):
      return idx
  -1

proc isBlockedRow(model: TuiModel, idx: int): bool =
  if model.view.techLevels.isNone or model.view.researchPoints.isNone:
    return false
  let levels = model.view.techLevels.get()
  let points = model.view.researchPoints.get()
  let items = researchItems()
  if idx < 0 or idx >= items.len:
    return false
  research_projection.isBlockedProjected(
    levels, points, model.ui.researchAllocation, items[idx]
  )

suite "TUI research navigation":
  test "switching to research lands on first selectable row":
    var model = initTuiModel()
    configureResearchState(model)
    model.ui.mode = ViewMode.Overview
    model.ui.selectedIdx = 9

    navigationAcceptor(model, actionSwitchView(4))

    check model.ui.mode == ViewMode.Research
    let firstSelectable = findFirstSelectableIdx(model)
    if firstSelectable >= 0:
      check model.ui.selectedIdx == firstSelectable
    else:
      check model.ui.selectedIdx == 0

  test "list down skips blocked research rows":
    var model = initTuiModel()
    configureResearchState(model)
    let items = researchItems()

    var blockedIdx = -1
    for idx in 0 ..< items.len:
      if isBlockedRow(model, idx):
        blockedIdx = idx
        break

    let firstSelectable = findFirstSelectableIdx(model)
    if blockedIdx >= 0 and firstSelectable >= 0:
      model.ui.selectedIdx = blockedIdx
      selectionAcceptor(model, actionListDown())
      check not isBlockedRow(model, model.ui.selectedIdx)
    else:
      check true

  test "list up skips blocked research rows":
    var model = initTuiModel()
    configureResearchState(model)
    let items = researchItems()

    var blockedIdx = -1
    for idx in 0 ..< items.len:
      if isBlockedRow(model, idx):
        blockedIdx = idx
        break

    let firstSelectable = findFirstSelectableIdx(model)
    if blockedIdx >= 0 and firstSelectable >= 0:
      model.ui.selectedIdx = blockedIdx
      selectionAcceptor(model, actionListUp())
      check not isBlockedRow(model, model.ui.selectedIdx)
    else:
      check true
