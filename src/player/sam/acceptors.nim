## TUI Acceptors - Functions that mutate model state
##
## Acceptors receive proposals and mutate the model accordingly.
## They are the ONLY place where model mutation happens.
## Each acceptor handles specific proposal types or aspects of state.
##
## Acceptor signature: proc(model: var M, proposal: Proposal)

import std/[options, times, strutils, tables, sets]
import ./types
import ./tui_model
import ./actions
import ./expert_parser
import ./expert_executor
import ../tui/expert_autocomplete
import ./client_limits
import ../tui/widget/scroll_state
import ../tui/build_spec
import ../tui/table_layout_policy
import ../state/join_flow
import ../state/lobby_profile
import ../../common/invite_code
import ../../engine/types/diplomacy
import ../../engine/systems/diplomacy/proposals as dip_proposals
import ../../common/logger
import ../../engine/globals
import ../../engine/types/[core, production, ship, facilities, ground_unit,
  fleet, command, tech, espionage, combat]
import ../../engine/systems/capacity/construction_docks
import ../../engine/systems/tech/costs
import ../tui/data/research_projection

export types, tui_model, actions

const DigitBufferTimeout = 1.0  ## Seconds to wait for a second keystroke in multi-char input

const ResearchAdjustStep = 5
const ResearchAdjustFineStep = 1
const ResearchDigitBufferTimeout = 1.5
const EspionageBudgetStep = 1

proc fleetConsoleViewportRows(model: TuiModel): int =
  var maxFleetCount = 0
  for fleets in model.ui.fleetConsoleFleetsBySystem.values:
    if fleets.len > maxFleetCount:
      maxFleetCount = fleets.len
  let contentRows = max(
    model.ui.fleetConsoleSystems.len,
    maxFleetCount
  )
  clampedVisibleRows(
    contentRows,
    model.ui.termHeight,
    PanelFrameRows + TableChromeRows + ModalFooterRows
  )

proc viewModeFromInt(value: int): Option[ViewMode] =
  case value
  of 1:
    some(ViewMode.Overview)
  of 2:
    some(ViewMode.Planets)
  of 3:
    some(ViewMode.Fleets)
  of 4:
    some(ViewMode.Research)
  of 5:
    some(ViewMode.Espionage)
  of 6:
    some(ViewMode.Economy)
  of 8:
    some(ViewMode.IntelDb)
  of 10:
    some(ViewMode.Messages)
  of 20:
    some(ViewMode.PlanetDetail)
  of 30:
    some(ViewMode.FleetDetail)
  of 80:
    some(ViewMode.IntelDetail)
  else:
    none(ViewMode)

proc researchAllocatedTotal(allocation: ResearchAllocation): int =
  var total = allocation.economic + allocation.science
  for pp in allocation.technology.values:
    total += pp
  total.int

proc researchItemAllocation(
    allocation: ResearchAllocation,
    item: ResearchItem
): int =
  case item.kind
  of ResearchItemKind.EconomicLevel:
    allocation.economic.int
  of ResearchItemKind.ScienceLevel:
    allocation.science.int
  of ResearchItemKind.Technology:
    if allocation.technology.hasKey(item.field):
      allocation.technology[item.field].int
    else:
      0

proc setResearchItemAllocation(
    allocation: var ResearchAllocation,
    item: ResearchItem,
    value: int
) =
  let clamped = max(0, value)
  case item.kind
  of ResearchItemKind.EconomicLevel:
    allocation.economic = int32(clamped)
  of ResearchItemKind.ScienceLevel:
    allocation.science = int32(clamped)
  of ResearchItemKind.Technology:
    allocation.technology[item.field] = int32(clamped)

proc researchMaxAllocation(model: TuiModel, item: ResearchItem): int =
  if model.view.techLevels.isNone or model.view.researchPoints.isNone:
    return 0
  let levels = model.view.techLevels.get()
  let points = model.view.researchPoints.get()
  research_projection.maxProjectedAllocation(
    levels, points, model.ui.researchAllocation, item
  )

proc normalizeResearchAllocation(model: var TuiModel): bool =
  ## Re-clamp all rows against projected SL.
  ## Returns true when dependent staged allocations were reduced.
  if model.view.techLevels.isNone or model.view.researchPoints.isNone:
    return false

  let levels = model.view.techLevels.get()
  let points = model.view.researchPoints.get()
  var dependentReduced = false
  var changed = true

  while changed:
    changed = false
    for item in researchItems():
      let current = researchItemAllocation(model.ui.researchAllocation, item)
      let maxAllowed = research_projection.maxProjectedAllocation(
        levels, points, model.ui.researchAllocation, item
      )
      if current > maxAllowed:
        if item.kind != ResearchItemKind.ScienceLevel and current > 0:
          dependentReduced = true
        setResearchItemAllocation(model.ui.researchAllocation, item, maxAllowed)
        changed = true

  dependentReduced

proc adjustResearchAllocation(
    model: var TuiModel,
    delta: int
) =
  if model.ui.mode != ViewMode.Research:
    return
  if model.ui.researchFocus != ResearchFocus.List:
    return
  let items = researchItems()
  if items.len == 0:
    return
  let idx = clamp(model.ui.selectedIdx, 0, items.len - 1)
  let item = items[idx]
  let current = researchItemAllocation(model.ui.researchAllocation, item)
  var nextValue = current + delta
  if nextValue < 0:
    nextValue = 0
  let maxPerTech = researchMaxAllocation(model, item)
  if nextValue > maxPerTech:
    nextValue = maxPerTech
  var total = researchAllocatedTotal(model.ui.researchAllocation)
  let diff = nextValue - current
  if diff > 0:
    let remaining = max(0, model.view.treasury - total)
    if diff > remaining:
      nextValue = current + remaining
  setResearchItemAllocation(model.ui.researchAllocation, item, nextValue)
  if normalizeResearchAllocation(model):
    model.ui.statusMessage = "SL reduced: blocked allocations were cleared"

proc applyResearchDigitInput(
    model: var TuiModel,
    digit: char
) =
  if model.ui.mode != ViewMode.Research:
    return
  if model.ui.researchFocus != ResearchFocus.List:
    return
  let now = epochTime()
  let buffer = model.ui.researchDigitBuffer
  let lastTime = model.ui.researchDigitTime
  var nextBuffer = ""
  if buffer.len > 0 and (now - lastTime) < ResearchDigitBufferTimeout:
    nextBuffer = buffer & $digit
  else:
    nextBuffer = $digit
  model.ui.researchDigitBuffer = nextBuffer
  model.ui.researchDigitTime = now
  let parsed = try:
    parseInt(nextBuffer)
  except:
    0
  let items = researchItems()
  if items.len == 0:
    return
  let idx = clamp(model.ui.selectedIdx, 0, items.len - 1)
  let item = items[idx]
  let current = researchItemAllocation(model.ui.researchAllocation, item)
  let total = researchAllocatedTotal(model.ui.researchAllocation)
  let remaining = max(0, model.view.treasury - (total - current))
  var nextValue = min(parsed, remaining)
  let maxPerTech = researchMaxAllocation(model, item)
  if nextValue > maxPerTech:
    nextValue = maxPerTech
  setResearchItemAllocation(model.ui.researchAllocation, item, nextValue)
  if normalizeResearchAllocation(model):
    model.ui.statusMessage = "SL reduced: blocked allocations were cleared"

proc espionageBudgetCostPp(model: TuiModel): int =
  let ebpCost = int(gameConfig.espionage.costs.ebpCostPp)
  let cipCost = int(gameConfig.espionage.costs.cipCostPp)
  int(model.ui.stagedEbpInvestment) * ebpCost +
    int(model.ui.stagedCipInvestment) * cipCost

proc reconcileEspionageQueueToAvailableEbp(
    model: var TuiModel
): int =
  ## Ensure queued espionage actions fit within available EBP.
  ## Drops newest queued actions first until valid.
  while model.ui.stagedEspionageActions.len > 0 and
      model.espionageQueuedTotalEbp() > model.espionageEbpTotal():
    model.ui.stagedEspionageActions.delete(
      model.ui.stagedEspionageActions.len - 1
    )
    result.inc

  if result > 0:
    model.ui.modifiedSinceSubmit = true

proc adjustEspionageBudget(
    model: var TuiModel,
    delta: int
) =
  if model.ui.mode != ViewMode.Espionage:
    return
  let totalResearchPp = researchAllocatedTotal(model.ui.researchAllocation)
  let currentBudgetPp = model.espionageBudgetCostPp()
  let ebpCostPp = int(gameConfig.espionage.costs.ebpCostPp)
  let cipCostPp = int(gameConfig.espionage.costs.cipCostPp)
  var currentPoints = 0
  var pointCost = 0
  var adjustEbp = false
  case model.ui.espionageBudgetChannel
  of EspionageBudgetChannel.Ebp:
    currentPoints = int(model.ui.stagedEbpInvestment)
    pointCost = ebpCostPp
    adjustEbp = true
  of EspionageBudgetChannel.Cip:
    currentPoints = int(model.ui.stagedCipInvestment)
    pointCost = cipCostPp
  if pointCost <= 0:
    return
  var nextPoints = currentPoints + delta
  if nextPoints < 0:
    nextPoints = 0
  if nextPoints > currentPoints:
    let availablePp = max(
      0,
      model.view.treasury - totalResearchPp - currentBudgetPp
    )
    let maxIncrease = availablePp div pointCost
    if nextPoints > currentPoints + maxIncrease:
      nextPoints = currentPoints + maxIncrease
  case model.ui.espionageBudgetChannel
  of EspionageBudgetChannel.Ebp:
    model.ui.stagedEbpInvestment = int32(nextPoints)
  of EspionageBudgetChannel.Cip:
    model.ui.stagedCipInvestment = int32(nextPoints)
  if adjustEbp and delta < 0:
    let removed = model.reconcileEspionageQueueToAvailableEbp()
    if removed > 0:
      model.ui.statusMessage = "Reduced EBP; removed " & $removed &
        " queued operation(s)"
  model.ui.modifiedSinceSubmit = true

proc stageSelectedEspionageOperation(model: var TuiModel): bool =
  let targets = model.espionageTargetHouses()
  let ops = espionageActions()
  if targets.len == 0 or ops.len == 0:
    model.ui.statusMessage = "No valid espionage target"
    return false
  let targetIdx = clamp(model.ui.espionageTargetIdx, 0, targets.len - 1)
  let opIdx = clamp(model.ui.espionageOperationIdx, 0, ops.len - 1)
  let selectedCost = espionageActionCost(ops[opIdx])
  let availableEbp = model.espionageEbpAvailable()
  if selectedCost > availableEbp:
    model.ui.statusMessage = "Insufficient EBP: need " & $selectedCost &
      ", available " & $availableEbp
    return false
  let targetHouse = HouseId(targets[targetIdx].id.uint32)
  model.ui.stagedEspionageActions.add(EspionageAttempt(
    attacker: HouseId(model.view.viewingHouse.uint32),
    target: targetHouse,
    action: ops[opIdx],
    targetSystem: none(SystemId)
  ))
  model.ui.modifiedSinceSubmit = true
  result = true

proc removeSelectedEspionageOperation(model: var TuiModel): bool =
  let targets = model.espionageTargetHouses()
  let ops = espionageActions()
  if targets.len == 0 or ops.len == 0:
    return false
  let targetIdx = clamp(model.ui.espionageTargetIdx, 0, targets.len - 1)
  let opIdx = clamp(model.ui.espionageOperationIdx, 0, ops.len - 1)
  let targetHouse = HouseId(targets[targetIdx].id.uint32)
  let selectedAction = ops[opIdx]
  for idx in countdown(model.ui.stagedEspionageActions.len - 1, 0):
    let attempt = model.ui.stagedEspionageActions[idx]
    if attempt.target == targetHouse and attempt.action == selectedAction:
      model.ui.stagedEspionageActions.delete(idx)
      model.ui.modifiedSinceSubmit = true
      return true
  false


proc updateFleetDetailScroll(model: var TuiModel): tuple[
    pageSize, maxOffset: int] =
  let pageSize = max(1, fleetDetailMaxRows(model.ui.termHeight))
  model.ui.fleetDetailModal.shipScroll.contentLength =
    model.ui.fleetDetailModal.shipCount
  model.ui.fleetDetailModal.shipScroll.viewportLength = pageSize
  model.ui.fleetDetailModal.shipScroll.clampOffsets()
  let maxOffset = model.ui.fleetDetailModal.shipScroll.maxVerticalOffset()
  (pageSize, maxOffset)

proc combatStatusLabel(state: CombatState): string =
  case state
  of CombatState.Nominal:
    "Nominal"
  of CombatState.Crippled:
    "Crippled"
  of CombatState.Destroyed:
    "Destroyed"

proc resetFleetDetailSubModal(model: var TuiModel) =
  model.ui.fleetDetailModal.subModal = FleetSubModal.None
  model.ui.fleetDetailModal.confirmPending = false
  model.ui.fleetDetailModal.confirmMessage = ""
  model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
  model.ui.fleetDetailModal.noticeMessage = ""
  model.ui.fleetDetailModal.noticeReturnSubModal = FleetSubModal.None
  model.ui.fleetDetailModal.fleetPickerCandidates = @[]
  model.ui.fleetDetailModal.fleetPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerSystems = @[]
  model.ui.fleetDetailModal.systemPickerFilter = ""
  model.ui.fleetDetailModal.systemPickerFilterTime = 0.0
  model.ui.fleetDetailModal.ztcType = none(ZeroTurnCommandType)
  model.ui.fleetDetailModal.ztcPickerCommands = @[]
  model.ui.fleetDetailModal.ztcTargetFleetId = 0
  model.ui.fleetDetailModal.shipSelectorIdx = 0
  model.ui.fleetDetailModal.shipSelectorShipIds = @[]
  model.ui.fleetDetailModal.shipSelectorRows = @[]
  model.ui.fleetDetailModal.shipSelectorSelected = initHashSet[ShipId]()
  model.ui.fleetDetailModal.cargoType = CargoClass.Marines
  model.ui.fleetDetailModal.cargoQuantityInput.clear()
  model.ui.fleetDetailModal.fighterQuantityInput.clear()

proc syncIntelListScroll(model: var TuiModel) =
  ## Keep Intel DB list scroll state aligned with selection.
  let viewportRows = max(1, model.ui.intelScroll.viewportLength)
  model.ui.intelScroll.contentLength = model.view.intelRows.len
  model.ui.intelScroll.viewportLength = viewportRows
  model.ui.intelScroll.ensureVisible(model.ui.selectedIdx)
  model.ui.intelScroll.clampOffsets()

proc ensureIntelCursorVisible(model: var TuiModel) =
  let viewportLines = max(1, model.ui.termHeight - 16)
  model.ui.intelNoteEditor.ensureCursorVisibleLines(viewportLines)

proc openSystemPickerForCommand(
    model: var TuiModel,
    cmdType: FleetCommandType,
    returnSubModal: FleetSubModal
) =
  let filtered = model.buildSystemPickerListForCommand(
    cmdType
  )
  if filtered.systems.len == 0 and
      filtered.emptyMessage.len > 0:
    model.ui.fleetDetailModal.noticeMessage =
      filtered.emptyMessage
    model.ui.fleetDetailModal.noticeReturnSubModal =
      returnSubModal
    model.ui.fleetDetailModal.subModal =
      FleetSubModal.NoticePrompt
    return
  model.ui.fleetDetailModal.systemPickerSystems =
    filtered.systems
  model.ui.fleetDetailModal.systemPickerIdx = 0
  model.ui.fleetDetailModal.systemPickerFilter = ""
  model.ui.fleetDetailModal.systemPickerFilterTime = 0.0
  model.ui.fleetDetailModal.systemPickerCommandType = cmdType
  model.ui.fleetDetailModal.subModal =
    FleetSubModal.SystemPicker

proc commandIndexForCode(
    commands: seq[FleetCommandType],
    code: int
): int =
  let allCommands = allFleetCommands()
  if code < 0 or code >= allCommands.len:
    return -1
  let cmdType = allCommands[code]
  for idx, cmd in commands:
    if cmd == cmdType:
      return idx
  -1

proc openCommandPicker(model: var TuiModel) =
  let commands = model.buildCommandPickerList()
  if commands.len == 0:
    model.ui.fleetDetailModal.noticeMessage =
      "No valid commands available"
    model.ui.fleetDetailModal.noticeReturnSubModal =
      FleetSubModal.None
    model.ui.fleetDetailModal.subModal =
      FleetSubModal.NoticePrompt
    return
  model.ui.fleetDetailModal.commandPickerCommands = commands
  model.ui.fleetDetailModal.commandIdx = 0
  model.ui.fleetDetailModal.commandDigitBuffer = ""
  model.ui.fleetDetailModal.commandDigitTime = 0.0
  model.ui.fleetDetailModal.subModal =
    FleetSubModal.CommandPicker

proc ztcCloseToFleets(model: var TuiModel) =
  resetFleetDetailSubModal(model)
  model.ui.mode = ViewMode.Fleets
  model.clearFleetSelection()
  model.resetBreadcrumbs(ViewMode.Fleets)

proc stageZeroTurnCommand(
    model: var TuiModel,
    cmd: ZeroTurnCommand,
    statusMessage: string,
) =
  model.ui.stagedZeroTurnCommands.add(cmd)
  model.ui.modifiedSinceSubmit = true
  model.ui.statusMessage = statusMessage
  model.applyZeroTurnCommandOptimistically(cmd)
  model.ztcCloseToFleets()

proc parseInputQuantity(input: TextInputState): int =
  let raw = input.value().strip()
  if raw.len == 0:
    return 0
  try:
    max(0, parseInt(raw))
  except:
    0

proc buildFleetPickerCandidatesForZtc(
    model: var TuiModel,
    sourceFleetId: int
): bool =
  if sourceFleetId notin model.view.ownFleetsById:
    model.ui.statusMessage = "Source fleet not found"
    return false
  let sourceFleet = model.view.ownFleetsById[sourceFleetId]
  model.ui.fleetDetailModal.fleetPickerCandidates = @[]
  for fleet in model.view.fleets:
    if fleet.id == sourceFleetId:
      continue
    if fleet.location != int(sourceFleet.location):
      continue
    if fleet.owner != model.view.viewingHouse:
      continue
    model.ui.fleetDetailModal.fleetPickerCandidates.add(
      FleetConsoleFleet(
        fleetId: fleet.id,
        name: fleet.name,
        shipCount: fleet.shipCount,
        attackStrength: fleet.attackStrength,
        defenseStrength: fleet.defenseStrength,
        troopTransports: 0,
        etacs: 0,
        commandLabel: fleet.commandLabel,
        destinationLabel: fleet.destinationLabel,
        eta: fleet.eta,
        roe: fleet.roe,
        status: fleet.statusLabel,
        needsAttention: fleet.needsAttention
      )
    )
  if model.ui.fleetDetailModal.fleetPickerCandidates.len == 0:
    model.ui.statusMessage = "No eligible fleets at source location"
    return false
  model.ui.fleetDetailModal.fleetPickerIdx = 0
  true

proc openShipSelectorForZtc(
    model: var TuiModel,
    sourceFleetId: int,
    ztcType: ZeroTurnCommandType
) =
  if sourceFleetId notin model.view.ownFleetsById:
    model.ui.statusMessage = "Source fleet not found"
    return
  let sourceFleet = model.view.ownFleetsById[sourceFleetId]

  # Build set of ships already committed to leave this fleet via a
  # previously staged TransferShips or DetachShips.  These must not
  # appear as selectable candidates — the engine will reject a second
  # command that references ships no longer in the source fleet.
  var alreadyStagedShips = initHashSet[ShipId]()
  for staged in model.ui.stagedZeroTurnCommands:
    if staged.commandType in {
        ZeroTurnCommandType.TransferShips,
        ZeroTurnCommandType.DetachShips} and
        staged.sourceFleetId.isSome and
        int(staged.sourceFleetId.get()) == sourceFleetId:
      for sid in staged.shipIds:
        alreadyStagedShips.incl(sid)

  model.ui.fleetDetailModal.ztcType = some(ztcType)
  model.ui.fleetDetailModal.shipSelectorShipIds = @[]
  model.ui.fleetDetailModal.shipSelectorRows = @[]
  model.ui.fleetDetailModal.shipSelectorSelected = initHashSet[ShipId]()
  model.ui.fleetDetailModal.shipSelectorIdx = 0
  for shipId in sourceFleet.ships:
    if int(shipId) notin model.view.ownShipsById:
      continue
    let ship = model.view.ownShipsById[int(shipId)]
    if ship.state == CombatState.Destroyed:
      continue
    if shipId in alreadyStagedShips:
      continue
    model.ui.fleetDetailModal.shipSelectorShipIds.add(shipId)
    model.ui.fleetDetailModal.shipSelectorRows.add(ShipSelectorRow(
      shipId: shipId,
      classLabel: $ship.shipClass,
      wepTech: int(ship.stats.wep),
      attackStrength: ship.stats.attackStrength,
      defenseStrength: ship.stats.defenseStrength,
      combatStatus: combatStatusLabel(ship.state)
    ))
  if model.ui.fleetDetailModal.shipSelectorShipIds.len == 0:
    model.ui.statusMessage = "No ships available"
    return
  model.ui.fleetDetailModal.fleetId = sourceFleetId
  model.ui.fleetDetailModal.subModal = FleetSubModal.ShipSelector

proc advanceSortColumn*(state: var TableSortState) =
  ## Move to next sort column, reset to ascending
  state.columnIdx =
    (state.columnIdx + 1) mod state.columnCount
  state.ascending = true

proc retreatSortColumn*(state: var TableSortState) =
  ## Move to previous sort column, reset to ascending
  state.columnIdx =
    (state.columnIdx - 1 + state.columnCount) mod
    state.columnCount
  state.ascending = true

proc toggleSortDirection*(
    state: var TableSortState) =
  ## Toggle ascending/descending on current column
  state.ascending = not state.ascending

proc resetExpertPaletteSelection(model: var TuiModel) =
  let matches = getAutocompleteSuggestions(model, model.ui.expertModeInput.value())
  if matches.len == 0:
    model.ui.expertPaletteSelection = -1
  else:
    model.ui.expertPaletteSelection = 0

proc clampExpertPaletteSelection(model: var TuiModel) =
  let matches = getAutocompleteSuggestions(model, model.ui.expertModeInput.value())
  if matches.len == 0:
    model.ui.expertPaletteSelection = -1
    return
  if model.ui.expertPaletteSelection < 0:
    model.ui.expertPaletteSelection = 0
  elif model.ui.expertPaletteSelection >= matches.len:
    model.ui.expertPaletteSelection = matches.len - 1

# ============================================================================
# Navigation Acceptor
# ============================================================================

proc navigationAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle navigation proposals (mode changes, cursor movement)
  if proposal.kind != ProposalKind.pkNavigation:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.navigateMode:
    # Mode switch
    let newMode = viewModeFromInt(proposal.navMode)
    if newMode.isSome:
      let selectedMode = newMode.get()
      model.ui.mode = selectedMode
      model.ui.selectedIdx = 0 # Reset selection when switching modes
      model.resetBreadcrumbs(selectedMode)
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
      if selectedMode == ViewMode.Research:
        model.ui.selectedIdx = 0
        model.ui.researchDigitBuffer = ""
        model.ui.researchDigitTime = 0.0
        model.ui.researchFocus = ResearchFocus.List
  of ActionKind.switchView:
    # Primary view switch
    let newMode = viewModeFromInt(proposal.navMode)
    if newMode.isSome:
      let selectedMode = newMode.get()
      model.ui.mode = selectedMode
      model.ui.selectedIdx = 0
      model.resetBreadcrumbs(selectedMode)
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
      if selectedMode == ViewMode.Research:
        model.ui.selectedIdx = 0
        model.ui.researchDigitBuffer = ""
        model.ui.researchDigitTime = 0.0
        model.ui.researchFocus = ResearchFocus.List
      if selectedMode == ViewMode.Messages:
        model.ui.inboxFocus = InboxPaneFocus.List
        model.ui.inboxSection = InboxSection.Messages
        model.ui.inboxListIdx = firstSelectableIdx(
          model.view.inboxItems)
        model.ui.messageHouseIdx = 0
        model.ui.inboxTurnIdx = 0
        model.ui.inboxReportIdx = 0
        model.ui.inboxTurnExpanded = false
        model.ui.messagesScroll = initScrollState()
        model.ui.inboxDetailScroll = initScrollState()
        model.ui.messageComposeActive = false
        model.ui.messageComposeInput.clear()
  of ActionKind.breadcrumbBack:
    if model.popBreadcrumb():
      let current = model.currentBreadcrumb()
      model.ui.mode = current.viewMode
      model.ui.statusMessage = ""
  of ActionKind.moveCursor:
    if proposal.navMode >= 0:
      # Direction-based movement
      let dir = HexDirection(proposal.navMode)
      model.ui.mapState.cursor = model.ui.mapState.cursor.neighbor(dir)
    else:
      # Direct coordinate movement
      model.ui.mapState.cursor = proposal.navCursor
  of ActionKind.jumpHome:
    if model.view.homeworld.isSome:
      model.ui.mapState.cursor = model.view.homeworld.get
  of ActionKind.cycleColony:
    let coords = model.ownedColonyCoords()
    if coords.len > 0:
      # Find current cursor in owned colonies
      var currentIdx = -1
      for i, coord in coords:
        if coord == model.ui.mapState.cursor:
          currentIdx = i
          break

      # Cycle to next/prev
      let reverse = proposal.navMode == 1
      if reverse:
        if currentIdx <= 0:
          model.ui.mapState.cursor = coords[coords.len - 1]
        else:
          model.ui.mapState.cursor = coords[currentIdx - 1]
      else:
        if currentIdx < 0 or currentIdx >= coords.len - 1:
          model.ui.mapState.cursor = coords[0]
        else:
          model.ui.mapState.cursor = coords[currentIdx + 1]
  of ActionKind.switchFleetView:
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      model.ui.fleetViewMode = FleetViewMode.ListView
    else:
      model.ui.fleetViewMode = FleetViewMode.SystemView
  
  of ActionKind.fleetConsoleNextPane:
    # Only active in SystemView mode
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.FleetsPane
      of FleetConsoleFocus.FleetsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.SystemsPane
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.SystemsPane
  
  of ActionKind.fleetConsolePrevPane:
    # Only active in SystemView mode
    if model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.FleetsPane
      of FleetConsoleFocus.FleetsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.SystemsPane
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleFocus = FleetConsoleFocus.FleetsPane
  
  of ActionKind.lobbySwitchPane:
    if proposal.navMode >= 0 and proposal.navMode <= 2:
      model.ui.lobbyPane = LobbyPane(proposal.navMode)
  else:
    discard

# ============================================================================
# Selection Acceptor
# ============================================================================

proc selectionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle selection proposals (list selection, map selection)
  if proposal.kind != ProposalKind.pkSelection:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.select:
    case model.ui.mode
    of ViewMode.Overview:
      # Overview selection (action queue items)
      if proposal.selectIdx >= 0:
        model.ui.selectedIdx = proposal.selectIdx
    of ViewMode.Planets, ViewMode.Fleets, ViewMode.Research,
       ViewMode.Espionage, ViewMode.Economy,
       ViewMode.PlanetDetail,
       ViewMode.FleetDetail,
       ViewMode.IntelDb, ViewMode.IntelDetail:
      # Select current list item (idx is already set)
      if proposal.selectIdx >= 0:
        model.ui.selectedIdx = proposal.selectIdx
    of ViewMode.Messages:
      discard  # Handled below with inbox logic

    if model.ui.mode == ViewMode.IntelDb:
      if model.ui.selectedIdx >= 0 and
          model.ui.selectedIdx < model.view.intelRows.len:
        let row = model.view.intelRows[model.ui.selectedIdx]
        model.ui.previousMode = model.ui.mode
        model.ui.mode = ViewMode.IntelDetail
        model.ui.intelDetailSystemId = row.systemId
        model.ui.intelDetailFleetPopupActive = false
        model.ui.intelDetailFleetSelectedIdx = 0
        model.ui.intelDetailFleetScrollOffset = 0
        model.ui.intelDetailNoteScrollOffset = 0
        model.pushBreadcrumb(
          row.systemName,
          ViewMode.IntelDetail,
          row.systemId,
        )
        model.ui.statusMessage = ""
      else:
        model.ui.statusMessage = "No intel system selected"
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.IntelDetail:
      model.ui.intelDetailFleetPopupActive = true
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.Messages:
      # Inbox select: context-dependent on focus + section
      if model.ui.inboxFocus == InboxPaneFocus.List:
        if model.ui.inboxSection == InboxSection.Messages:
          # Focus detail pane for message conversation
          model.ui.inboxFocus = InboxPaneFocus.Detail
          model.ui.messageComposeActive = false
        elif model.ui.inboxSection == InboxSection.Reports:
          # Toggle expand on turn bucket
          if model.ui.inboxTurnExpanded:
            model.ui.inboxTurnExpanded = false
            model.ui.inboxReportIdx = -1
          else:
            model.ui.inboxTurnExpanded = true
            model.ui.inboxReportIdx = 0  # focus first report
            model.ui.inboxDetailScroll.reset()
      elif model.ui.inboxFocus == InboxPaneFocus.Compose:
        # Send message
        if not model.ui.messageComposeInput.isEmpty():
          model.ui.statusMessage = "Sending message..."
        else:
          model.ui.statusMessage = "Message is empty"
  of ActionKind.toggleFleetSelect:
    if model.ui.mode == ViewMode.Fleets:
      if model.ui.fleetViewMode == FleetViewMode.ListView:
        let fleets = model.filteredFleets()
        if model.ui.selectedIdx < fleets.len:
          let fleetId = fleets[model.ui.selectedIdx].id
          model.toggleFleetSelection(fleetId)
      elif model.ui.fleetViewMode == FleetViewMode.SystemView:
        if model.ui.fleetConsoleFocus == FleetConsoleFocus.FleetsPane:
          let systems = model.ui.fleetConsoleSystems
          if systems.len > 0:
            let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
            let systemId = systems[sysIdx].systemId
            if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
              let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
              let fleetIdx = model.ui.fleetConsoleFleetIdx
              if fleetIdx >= 0 and fleetIdx < fleets.len:
                let fleetId = fleets[fleetIdx].fleetId
                model.toggleFleetSelection(fleetId)
  of ActionKind.deselect:
    model.ui.mapState.selected = none(HexCoord)
    if model.ui.mode == ViewMode.FleetDetail:
      # Return to fleet list
      model.ui.mode = ViewMode.Fleets
      model.clearFleetSelection()
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.PlanetDetail:
      # Return to colony list
      model.ui.mode = ViewMode.Planets
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.IntelDetail:
      if model.ui.intelDetailFleetPopupActive:
        model.ui.intelDetailFleetPopupActive = false
      else:
        model.ui.mode = ViewMode.IntelDb
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    elif model.ui.mode == ViewMode.Messages:
      # Esc in inbox: collapse expanded turn, or
      # return focus to list
      if model.ui.inboxTurnExpanded:
        model.ui.inboxTurnExpanded = false
        model.ui.inboxReportIdx = 0
        model.ui.inboxDetailScroll.reset()
      elif model.ui.inboxFocus != InboxPaneFocus.List:
        model.ui.inboxFocus = InboxPaneFocus.List
        model.ui.messageComposeActive = false
    else:
      model.ui.statusMessage = ""
      model.clearExpertFeedback()
    if model.ui.mode == ViewMode.Research:
      model.ui.researchDigitBuffer = ""
      model.ui.researchDigitTime = 0.0
  of ActionKind.listUp:
    # Fleet console per-pane navigation
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView:
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        let maxIdx = max(0, model.ui.fleetConsoleSystems.len - 1)
        if model.ui.fleetConsoleSystemIdx > 0:
          model.ui.fleetConsoleSystemIdx -= 1
        else:
          model.ui.fleetConsoleSystemIdx = maxIdx
        # Update scroll state to keep selection visible
        let viewportHeight = model.fleetConsoleViewportRows()
        model.ui.fleetConsoleSystemScroll.contentLength = model.ui.fleetConsoleSystems.len
        model.ui.fleetConsoleSystemScroll.viewportLength = viewportHeight
        model.ui.fleetConsoleSystemScroll.ensureVisible(model.ui.fleetConsoleSystemIdx)
      of FleetConsoleFocus.FleetsPane:
        if model.ui.fleetConsoleSystems.len > 0:
          let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0,
            model.ui.fleetConsoleSystems.len - 1)
          let systemId = model.ui.fleetConsoleSystems[sysIdx].systemId
          if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
            let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
            let maxIdx = max(0, fleets.len - 1)
            if model.ui.fleetConsoleFleetIdx > 0:
              model.ui.fleetConsoleFleetIdx -= 1
            else:
              model.ui.fleetConsoleFleetIdx = maxIdx
            # Update scroll state
            let viewportHeight = model.fleetConsoleViewportRows()
            model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
            model.ui.fleetConsoleFleetScroll.viewportLength = viewportHeight
            model.ui.fleetConsoleFleetScroll.ensureVisible(model.ui.fleetConsoleFleetIdx)
      of FleetConsoleFocus.ShipsPane:
        if model.ui.fleetConsoleShipIdx > 0:
          model.ui.fleetConsoleShipIdx -= 1
    elif model.ui.mode == ViewMode.Espionage:
      case model.ui.espionageFocus
      of EspionageFocus.Budget:
        model.ui.espionageFocus = EspionageFocus.Targets
      of EspionageFocus.Targets:
        let targets = model.espionageTargetHouses()
        if model.ui.espionageTargetIdx > 0 and targets.len > 0:
          model.ui.espionageTargetIdx.dec
        elif targets.len > 0:
          model.ui.espionageTargetIdx = targets.len - 1
      of EspionageFocus.Operations:
        let ops = espionageActions()
        let maxIdx = max(0, ops.len - 1)
        if model.ui.espionageOperationIdx > 0 and ops.len > 0:
          model.ui.espionageOperationIdx.dec
        elif ops.len > 0:
          model.ui.espionageOperationIdx = maxIdx
    elif model.ui.mode == ViewMode.Economy:
      if model.ui.economyFocus == EconomyFocus.Diplomacy:
        let targets = model.espionageTargetHouses()
        if targets.len > 0:
          if model.ui.economyHouseIdx > 0:
            model.ui.economyHouseIdx.dec
          else:
            model.ui.economyHouseIdx = targets.len - 1
    elif model.ui.mode == ViewMode.IntelDetail:
      if model.ui.intelDetailFleetPopupActive:
        return
      let maxIdx = max(0, model.ui.intelDetailFleetCount - 1)
      if model.ui.intelDetailFleetSelectedIdx > 0:
        model.ui.intelDetailFleetSelectedIdx -= 1
      else:
        model.ui.intelDetailFleetSelectedIdx = maxIdx
    elif model.ui.mode == ViewMode.Messages:
      if model.ui.inboxFocus == InboxPaneFocus.List:
        if model.ui.inboxTurnExpanded and
            model.ui.inboxSection ==
              InboxSection.Reports:
          # Navigate within expanded reports
          if model.ui.inboxReportIdx > 0:
            # Inside reports, go up one
            model.ui.inboxReportIdx -= 1
            model.ui.inboxDetailScroll.reset()
          elif model.ui.inboxReportIdx == 0:
            # At first report, do normal flat list Up
            let items = model.view.inboxItems
            let newIdx = nextSelectableIdx(
              items, model.ui.inboxListIdx, -1)
            if newIdx != model.ui.inboxListIdx:
              model.ui.inboxListIdx = newIdx
              let item = items[newIdx]
              if item.kind == InboxItemKind.MessageHouse:
                model.ui.inboxSection =
                  InboxSection.Messages
                model.ui.messageHouseIdx = item.houseIdx
                model.ui.messagesScroll.reset()
              elif item.kind == InboxItemKind.TurnBucket:
                model.ui.inboxSection =
                  InboxSection.Reports
                model.ui.inboxTurnIdx = item.turnIdx
                model.ui.inboxReportIdx = 0
                model.ui.inboxDetailScroll.reset()
        else:
          let items = model.view.inboxItems
          let newIdx = nextSelectableIdx(
            items, model.ui.inboxListIdx, -1)
          if newIdx != model.ui.inboxListIdx:
            model.ui.inboxListIdx = newIdx
            let item = items[newIdx]
            if item.kind == InboxItemKind.MessageHouse:
              model.ui.inboxSection =
                InboxSection.Messages
              model.ui.messageHouseIdx = item.houseIdx
              model.ui.messagesScroll.reset()
            elif item.kind == InboxItemKind.TurnBucket:
              model.ui.inboxSection =
                InboxSection.Reports
              model.ui.inboxTurnIdx = item.turnIdx
              model.ui.inboxReportIdx = 0
              model.ui.inboxDetailScroll.reset()
      elif model.ui.inboxFocus == InboxPaneFocus.Detail:
        # Scroll report/message detail with Up when detail pane focused
        if model.ui.inboxSection == InboxSection.Messages:
          model.ui.messagesScroll.scrollBy(-1)
        else:
          model.ui.inboxDetailScroll.scrollBy(-1)
    elif model.ui.mode == ViewMode.Research:
      if model.ui.researchFocus == ResearchFocus.Detail:
        model.ui.researchFocus = ResearchFocus.List
      else:
        let maxIdx = max(0, model.currentListLength() - 1)
        if model.ui.selectedIdx > 0:
          model.ui.selectedIdx -= 1
        else:
          model.ui.selectedIdx = maxIdx
      model.ui.researchDigitBuffer = ""
      model.ui.researchDigitTime = 0.0
    else:
      # Default list navigation
      let maxIdx = max(0, model.currentListLength() - 1)
      if model.ui.selectedIdx > 0:
        model.ui.selectedIdx -= 1
      else:
        model.ui.selectedIdx = maxIdx
      if model.ui.mode == ViewMode.IntelDb:
        model.syncIntelListScroll()
  
  of ActionKind.listDown:
    # Fleet console per-pane navigation
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView:
      # Use cached data for proper bounds checking
      case model.ui.fleetConsoleFocus
      of FleetConsoleFocus.SystemsPane:
        let maxIdx = max(0, model.ui.fleetConsoleSystems.len - 1)
        if model.ui.fleetConsoleSystemIdx < maxIdx:
          model.ui.fleetConsoleSystemIdx += 1
        else:
          model.ui.fleetConsoleSystemIdx = 0
        # Update scroll state to keep selection visible
        let viewportHeight = model.fleetConsoleViewportRows()
        model.ui.fleetConsoleSystemScroll.contentLength = model.ui.fleetConsoleSystems.len
        model.ui.fleetConsoleSystemScroll.viewportLength = viewportHeight
        model.ui.fleetConsoleSystemScroll.ensureVisible(model.ui.fleetConsoleSystemIdx)
      of FleetConsoleFocus.FleetsPane:
        # Get fleets for current system to check bounds
        if model.ui.fleetConsoleSystems.len > 0:
          let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, 
            model.ui.fleetConsoleSystems.len - 1)
          let systemId = model.ui.fleetConsoleSystems[sysIdx].systemId
          if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
            let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
            let maxIdx = max(0, fleets.len - 1)
            if model.ui.fleetConsoleFleetIdx < maxIdx:
              model.ui.fleetConsoleFleetIdx += 1
            else:
              model.ui.fleetConsoleFleetIdx = 0
            # Update scroll state
            let viewportHeight = model.fleetConsoleViewportRows()
            model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
            model.ui.fleetConsoleFleetScroll.viewportLength = viewportHeight
            model.ui.fleetConsoleFleetScroll.ensureVisible(model.ui.fleetConsoleFleetIdx)
      of FleetConsoleFocus.ShipsPane:
        model.ui.fleetConsoleShipIdx += 1  # Ships bounds checked at render
    elif model.ui.mode == ViewMode.Espionage:
      case model.ui.espionageFocus
      of EspionageFocus.Budget:
        model.ui.espionageFocus = EspionageFocus.Targets
      of EspionageFocus.Targets:
        let targets = model.espionageTargetHouses()
        let maxIdx = max(0, targets.len - 1)
        if targets.len > 0 and model.ui.espionageTargetIdx < maxIdx:
          model.ui.espionageTargetIdx.inc
        elif targets.len > 0:
          model.ui.espionageTargetIdx = 0
      of EspionageFocus.Operations:
        let ops = espionageActions()
        let maxIdx = max(0, ops.len - 1)
        if ops.len > 0 and model.ui.espionageOperationIdx < maxIdx:
          model.ui.espionageOperationIdx.inc
        elif ops.len > 0:
          model.ui.espionageOperationIdx = 0
    elif model.ui.mode == ViewMode.Economy:
      if model.ui.economyFocus == EconomyFocus.Diplomacy:
        let targets = model.espionageTargetHouses()
        if targets.len > 0:
          if model.ui.economyHouseIdx < targets.len - 1:
            model.ui.economyHouseIdx.inc
          else:
            model.ui.economyHouseIdx = 0
    elif model.ui.mode == ViewMode.IntelDetail:
      if model.ui.intelDetailFleetPopupActive:
        return
      let maxIdx = max(0, model.ui.intelDetailFleetCount - 1)
      if model.ui.intelDetailFleetSelectedIdx < maxIdx:
        model.ui.intelDetailFleetSelectedIdx += 1
      else:
        model.ui.intelDetailFleetSelectedIdx = 0
    elif model.ui.mode == ViewMode.Messages:
      if model.ui.inboxFocus == InboxPaneFocus.List:
        if model.ui.inboxTurnExpanded and
            model.ui.inboxSection ==
              InboxSection.Reports:
          # Navigate within expanded reports
          let turnIdx = model.ui.inboxTurnIdx
          if turnIdx < model.view.turnBuckets.len:
            let maxRpt = max(0,
                model.view.turnBuckets[
                  turnIdx].reports.len - 1)
            if model.ui.inboxReportIdx < maxRpt:
              # Advance within reports
              model.ui.inboxReportIdx += 1
              model.ui.inboxDetailScroll.reset()
            else:
              # At last report, advance to next flat item
              let items = model.view.inboxItems
              let newIdx = nextSelectableIdx(
                items, model.ui.inboxListIdx, 1)
              if newIdx != model.ui.inboxListIdx:
                model.ui.inboxListIdx = newIdx
                let item = items[newIdx]
                if item.kind == InboxItemKind.MessageHouse:
                  model.ui.inboxSection =
                    InboxSection.Messages
                  model.ui.messageHouseIdx = item.houseIdx
                  model.ui.messagesScroll.reset()
                elif item.kind == InboxItemKind.TurnBucket:
                  model.ui.inboxSection =
                    InboxSection.Reports
                  model.ui.inboxTurnIdx = item.turnIdx
                  model.ui.inboxReportIdx = 0
                  model.ui.inboxDetailScroll.reset()
              # else: at bottom, stay put
        else:
          let items = model.view.inboxItems
          let newIdx = nextSelectableIdx(
            items, model.ui.inboxListIdx, 1)
          if newIdx != model.ui.inboxListIdx:
            model.ui.inboxListIdx = newIdx
            let item = items[newIdx]
            if item.kind == InboxItemKind.MessageHouse:
              model.ui.inboxSection =
                InboxSection.Messages
              model.ui.messageHouseIdx = item.houseIdx
              model.ui.messagesScroll.reset()
            elif item.kind == InboxItemKind.TurnBucket:
              model.ui.inboxSection =
                InboxSection.Reports
              model.ui.inboxTurnIdx = item.turnIdx
              model.ui.inboxReportIdx = 0
              model.ui.inboxDetailScroll.reset()
      elif model.ui.inboxFocus == InboxPaneFocus.Detail:
        # Scroll report/message detail with Down when detail pane focused
        if model.ui.inboxSection == InboxSection.Messages:
          model.ui.messagesScroll.scrollBy(1)
        else:
          model.ui.inboxDetailScroll.scrollBy(1)
    elif model.ui.mode == ViewMode.Research:
      if model.ui.researchFocus == ResearchFocus.Detail:
        discard  # down does nothing in detail pane (no scrollable content)
      else:
        let maxIdx = max(0, model.currentListLength() - 1)
        if model.ui.selectedIdx < maxIdx:
          model.ui.selectedIdx += 1
        else:
          model.ui.selectedIdx = 0
      model.ui.researchDigitBuffer = ""
      model.ui.researchDigitTime = 0.0
    else:
      # Default list navigation
      let maxIdx = max(0, model.currentListLength() - 1)
      if model.ui.selectedIdx < maxIdx:
        model.ui.selectedIdx = min(maxIdx, model.ui.selectedIdx + 1)
      else:
        model.ui.selectedIdx = 0
      if model.ui.mode == ViewMode.IntelDb:
        model.syncIntelListScroll()
  of ActionKind.listPageUp:
    if model.ui.mode == ViewMode.IntelDetail:
      if model.ui.intelDetailFleetPopupActive:
        return
      let pageSize = max(1, model.ui.termHeight - 12)
      model.ui.intelDetailNoteScrollOffset = max(
        0,
        model.ui.intelDetailNoteScrollOffset - pageSize
      )
    elif model.ui.mode == ViewMode.Research:
      let pageSize = max(1, model.ui.termHeight - 10)
      model.ui.selectedIdx = max(0, model.ui.selectedIdx - pageSize)
      model.ui.researchDigitBuffer = ""
      model.ui.researchDigitTime = 0.0
    elif model.ui.mode == ViewMode.Espionage:
      discard
    else:
      let pageSize = max(1, model.ui.termHeight - 10)
      model.ui.selectedIdx = max(0, model.ui.selectedIdx - pageSize)
      if model.ui.mode == ViewMode.IntelDb:
        model.syncIntelListScroll()
  of ActionKind.listPageDown:
    if model.ui.mode == ViewMode.IntelDetail:
      if model.ui.intelDetailFleetPopupActive:
        return
      let pageSize = max(1, model.ui.termHeight - 12)
      model.ui.intelDetailNoteScrollOffset += pageSize
    elif model.ui.mode == ViewMode.Research:
      let maxIdx = model.currentListLength() - 1
      let pageSize = max(1, model.ui.termHeight - 10)
      model.ui.selectedIdx = min(maxIdx, model.ui.selectedIdx + pageSize)
      model.ui.researchDigitBuffer = ""
      model.ui.researchDigitTime = 0.0
    elif model.ui.mode == ViewMode.Espionage:
      discard
    else:
      let maxIdx = model.currentListLength() - 1
      let pageSize = max(1, model.ui.termHeight - 10)
      model.ui.selectedIdx = min(maxIdx, model.ui.selectedIdx + pageSize)
      if model.ui.mode == ViewMode.IntelDb:
        model.syncIntelListScroll()
  else:
    discard

# ============================================================================
# Viewport Acceptor
# ============================================================================

proc viewportAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle viewport/scroll proposals
  if proposal.kind != ProposalKind.pkViewportScroll:
    return

  model.clearExpertFeedback()
  case proposal.actionKind
  of ActionKind.scroll:
    model.ui.mapState.viewportOrigin = (
      model.ui.mapState.viewportOrigin.q + proposal.scrollDelta.dx,
      model.ui.mapState.viewportOrigin.r + proposal.scrollDelta.dy,
    )
  of ActionKind.resize:
    model.ui.termWidth = proposal.scrollDelta.dx
    model.ui.termHeight = proposal.scrollDelta.dy
    model.ui.needsResize = true
  else:
    discard

# ============================================================================
# Game Action Acceptor
# ============================================================================

proc gameActionAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle game action proposals
  model.clearExpertFeedback()
  case proposal.kind
  of ProposalKind.pkNavigation:
    # Skip - navigation is handled by navigationAcceptor
    # Only process detail view transitions triggered by game actions
    if proposal.actionKind in [ActionKind.switchView, ActionKind.navigateMode,
        ActionKind.breadcrumbBack, ActionKind.moveCursor, ActionKind.jumpHome,
        ActionKind.cycleColony]:
      return
    let target = proposal.navMode
    # Special handling for detail views (mode 20/30 are dynamic)
    if target == 20:
      model.ui.previousMode = model.ui.mode
      model.ui.mode = ViewMode.PlanetDetail
      model.resetBreadcrumbs(model.ui.mode)
      if model.ui.selectedIdx < model.view.colonies.len:
        model.ui.selectedColonyId =
          model.view.colonies[model.ui.selectedIdx].colonyId
    # NOTE: target == 30 (FleetDetail) removed - now uses popup modal instead of full view

  of ProposalKind.pkGameAction:
    case proposal.actionKind
    of ActionKind.toggleHelpOverlay:
      model.ui.showHelpOverlay = not model.ui.showHelpOverlay
    of ActionKind.researchAdjustInc:
      adjustResearchAllocation(model, ResearchAdjustStep)
    of ActionKind.researchAdjustDec:
      adjustResearchAllocation(model, -ResearchAdjustStep)
    of ActionKind.researchAdjustFineInc:
      adjustResearchAllocation(model, ResearchAdjustFineStep)
    of ActionKind.researchAdjustFineDec:
      adjustResearchAllocation(model, -ResearchAdjustFineStep)
    of ActionKind.researchClearAllocation:
      if model.ui.mode == ViewMode.Research:
        let items = researchItems()
        if items.len > 0:
          let idx = clamp(model.ui.selectedIdx, 0, items.len - 1)
          let item = items[idx]
          setResearchItemAllocation(model.ui.researchAllocation, item, 0)
          if normalizeResearchAllocation(model):
            model.ui.statusMessage =
              "SL reduced: blocked allocations were cleared"
    of ActionKind.researchDigitInput:
      if proposal.gameActionData.len > 0:
        applyResearchDigitInput(model, proposal.gameActionData[0])
    of ActionKind.espionageFocusNext:
      if model.ui.mode == ViewMode.Espionage:
        case model.ui.espionageFocus
        of EspionageFocus.Budget:
          model.ui.espionageFocus = EspionageFocus.Targets
        of EspionageFocus.Targets:
          model.ui.espionageFocus = EspionageFocus.Operations
        of EspionageFocus.Operations:
          model.ui.espionageFocus = EspionageFocus.Budget
    of ActionKind.espionageFocusPrev:
      if model.ui.mode == ViewMode.Espionage:
        case model.ui.espionageFocus
        of EspionageFocus.Budget:
          model.ui.espionageFocus = EspionageFocus.Operations
        of EspionageFocus.Targets:
          model.ui.espionageFocus = EspionageFocus.Budget
        of EspionageFocus.Operations:
          model.ui.espionageFocus = EspionageFocus.Targets
    of ActionKind.espionageSelectEbp:
      if model.ui.mode == ViewMode.Espionage:
        model.ui.espionageFocus = EspionageFocus.Budget
        model.ui.espionageBudgetChannel = EspionageBudgetChannel.Ebp
    of ActionKind.espionageSelectCip:
      if model.ui.mode == ViewMode.Espionage:
        model.ui.espionageFocus = EspionageFocus.Budget
        model.ui.espionageBudgetChannel = EspionageBudgetChannel.Cip
    of ActionKind.espionageBudgetAdjustInc:
      if model.ui.mode == ViewMode.Espionage and
          model.ui.espionageFocus == EspionageFocus.Operations:
        discard model.stageSelectedEspionageOperation()
      else:
        adjustEspionageBudget(model, EspionageBudgetStep)
    of ActionKind.espionageBudgetAdjustDec:
      if model.ui.mode == ViewMode.Espionage and
          model.ui.espionageFocus == EspionageFocus.Operations:
        discard model.removeSelectedEspionageOperation()
      else:
        adjustEspionageBudget(model, -EspionageBudgetStep)
    of ActionKind.espionageQueueAdd:
      if model.ui.mode == ViewMode.Espionage:
        if model.stageSelectedEspionageOperation():
          model.ui.espionageFocus = EspionageFocus.Operations
    of ActionKind.espionageQueueDelete:
      if model.ui.mode == ViewMode.Espionage and
          model.ui.stagedEspionageActions.len > 0:
        model.ui.stagedEspionageActions.delete(
          model.ui.stagedEspionageActions.len - 1
        )
        model.ui.modifiedSinceSubmit = true
    of ActionKind.espionageClearBudget:
      if model.ui.mode == ViewMode.Espionage:
        model.ui.stagedEbpInvestment = 0
        model.ui.stagedCipInvestment = 0
        let removed = model.reconcileEspionageQueueToAvailableEbp()
        if removed > 0:
          model.ui.statusMessage = "Reduced EBP; removed " & $removed &
            " queued operation(s)"
        model.ui.modifiedSinceSubmit = true

    of ActionKind.economyFocusNext:
      if model.ui.mode == ViewMode.Economy:
        case model.ui.economyFocus
        of EconomyFocus.TaxRate:
          model.ui.economyFocus = EconomyFocus.Diplomacy
        of EconomyFocus.Diplomacy:
          model.ui.economyFocus = EconomyFocus.Actions
        of EconomyFocus.Actions:
          model.ui.economyFocus = EconomyFocus.TaxRate

    of ActionKind.economyFocusPrev:
      if model.ui.mode == ViewMode.Economy:
        case model.ui.economyFocus
        of EconomyFocus.TaxRate:
          model.ui.economyFocus = EconomyFocus.Actions
        of EconomyFocus.Diplomacy:
          model.ui.economyFocus = EconomyFocus.TaxRate
        of EconomyFocus.Actions:
          model.ui.economyFocus = EconomyFocus.Diplomacy

    of ActionKind.economyTaxInc:
      if model.ui.mode == ViewMode.Economy and
          model.ui.economyFocus == EconomyFocus.TaxRate:
        let current = model.ui.stagedTaxRate.get(
          model.view.houseTaxRate)
        let next = min(100, current + 10)
        if next != model.view.houseTaxRate:
          model.ui.stagedTaxRate = some(next)
        else:
          model.ui.stagedTaxRate = none(int)
        model.ui.modifiedSinceSubmit = true

    of ActionKind.economyTaxDec:
      if model.ui.mode == ViewMode.Economy and
          model.ui.economyFocus == EconomyFocus.TaxRate:
        let current = model.ui.stagedTaxRate.get(
          model.view.houseTaxRate)
        let next = max(0, current - 10)
        if next != model.view.houseTaxRate:
          model.ui.stagedTaxRate = some(next)
        else:
          model.ui.stagedTaxRate = none(int)
        model.ui.modifiedSinceSubmit = true

    of ActionKind.economyTaxFineInc:
      if model.ui.mode == ViewMode.Economy and
          model.ui.economyFocus == EconomyFocus.TaxRate:
        let current = model.ui.stagedTaxRate.get(
          model.view.houseTaxRate)
        let next = min(100, current + 1)
        if next != model.view.houseTaxRate:
          model.ui.stagedTaxRate = some(next)
        else:
          model.ui.stagedTaxRate = none(int)
        model.ui.modifiedSinceSubmit = true

    of ActionKind.economyTaxFineDec:
      if model.ui.mode == ViewMode.Economy and
          model.ui.economyFocus == EconomyFocus.TaxRate:
        let current = model.ui.stagedTaxRate.get(
          model.view.houseTaxRate)
        let next = max(0, current - 1)
        if next != model.view.houseTaxRate:
          model.ui.stagedTaxRate = some(next)
        else:
          model.ui.stagedTaxRate = none(int)
        model.ui.modifiedSinceSubmit = true

    of ActionKind.economyDiplomacyAction:
      if model.ui.mode == ViewMode.Economy and
          model.ui.economyFocus == EconomyFocus.Diplomacy:
        let targets = model.espionageTargetHouses()
        if targets.len == 0:
          return
        let idx = clamp(
          model.ui.economyHouseIdx, 0, targets.len - 1)
        let targetId = targets[idx].id
        let myId = model.view.viewingHouse
        let key = (myId, targetId)
        # Read base state from server ground truth
        let baseState = model.view.diplomaticRelations.getOrDefault(
          key, DiplomaticState.Neutral)
        var current = baseState
        # Apply staged override so repeated presses cycle from staged state
        for cmd in model.ui.stagedDiplomaticCommands:
          if int(cmd.targetHouse) == targetId:
            current = case cmd.actionType
              of DiplomaticActionType.DeclareHostile:
                DiplomaticState.Hostile
              of DiplomaticActionType.DeclareEnemy:
                DiplomaticState.Enemy
              of DiplomaticActionType.SetNeutral:
                DiplomaticState.Neutral
              else: current
        
        if baseState == DiplomaticState.Enemy and current == DiplomaticState.Enemy:
          model.ui.statusMessage = "Already at Enemy status - cannot escalate further"
          return

        # Escalate: Neutral → Hostile → Enemy → back to baseState
        let nextState = case current
          of DiplomaticState.Neutral: DiplomaticState.Hostile
          of DiplomaticState.Hostile: DiplomaticState.Enemy
          of DiplomaticState.Enemy: baseState
        
        # Remove any existing staged command for this target
        var newCmds: seq[DiplomaticCommand] = @[]
        for cmd in model.ui.stagedDiplomaticCommands:
          if int(cmd.targetHouse) != targetId:
            newCmds.add(cmd)
        
        model.ui.stagedDiplomaticCommands = newCmds
        model.ui.modifiedSinceSubmit = true
        
        if nextState == baseState:
          model.ui.statusMessage = "Escalation cancelled"
        else:
          let actionType = case nextState
            of DiplomaticState.Hostile:
              DiplomaticActionType.DeclareHostile
            of DiplomaticState.Enemy:
              DiplomaticActionType.DeclareEnemy
            of DiplomaticState.Neutral:
              DiplomaticActionType.SetNeutral # Unreachable, as nextState != baseState and nextState can only be Hostile or Enemy if it's greater than baseState
          
          # Stage the new command
          model.ui.stagedDiplomaticCommands.add(DiplomaticCommand(
            houseId: HouseId(myId),
            targetHouse: HouseId(targetId),
            actionType: actionType,
            proposalId: none(ProposalId),
            proposalType: none(ProposalType),
            message: none(string)
          ))
          
          let tgtName = model.view.houseNames.getOrDefault(
            targetId, "House " & $targetId)
          let stateLabel = case nextState
            of DiplomaticState.Neutral: "Neutral"
            of DiplomaticState.Hostile: "Hostile"
            of DiplomaticState.Enemy: "Enemy"
          model.ui.statusMessage =
            "Staged: " & tgtName & " → " & stateLabel

    of ActionKind.economyDiplomacyPropose:
      if model.ui.mode != ViewMode.Economy or
          model.ui.economyFocus != EconomyFocus.Diplomacy:
        return
      let targets = model.espionageTargetHouses()
      if targets.len == 0:
        return
      let idx = clamp(
        model.ui.economyHouseIdx, 0, targets.len - 1)
      let targetId = targets[idx].id
      let myId = model.view.viewingHouse
      let key = (myId, targetId)
      let currentState = model.view.diplomaticRelations.getOrDefault(
        key, DiplomaticState.Neutral)
      # Determine de-escalation target: propose one step down
      let propTarget = case currentState
        of DiplomaticState.Enemy: DiplomaticState.Hostile
        of DiplomaticState.Hostile: DiplomaticState.Neutral
        of DiplomaticState.Neutral:
          model.ui.statusMessage =
            "Already Neutral - cannot de-escalate further"
          return
      if not dip_proposals.canProposeDeescalation(
          currentState, propTarget):
        model.ui.statusMessage = "Cannot propose de-escalation"
        return
      let propType = case propTarget
        of DiplomaticState.Neutral:
          ProposalType.DeescalateToNeutral
        of DiplomaticState.Hostile:
          ProposalType.DeescalateToHostile
        of DiplomaticState.Enemy:
          return  # unreachable
      # Remove any existing staged propose command for this target
      var newCmds: seq[DiplomaticCommand] = @[]
      for cmd in model.ui.stagedDiplomaticCommands:
        if int(cmd.targetHouse) == targetId and
            cmd.actionType == DiplomaticActionType.ProposeDeescalation:
          continue
        newCmds.add(cmd)
      newCmds.add(DiplomaticCommand(
        houseId: HouseId(myId),
        targetHouse: HouseId(targetId),
        actionType: DiplomaticActionType.ProposeDeescalation,
        proposalId: none(ProposalId),
        proposalType: some(propType),
        message: none(string)
      ))
      model.ui.stagedDiplomaticCommands = newCmds
      model.ui.modifiedSinceSubmit = true
      let tgtName = model.view.houseNames.getOrDefault(
        targetId, "House " & $targetId)
      let stateLabel = case propTarget
        of DiplomaticState.Neutral: "Neutral"
        of DiplomaticState.Hostile: "Hostile"
        of DiplomaticState.Enemy: "Enemy"
      model.ui.statusMessage =
        "Staged proposal to " & tgtName & " → " & stateLabel

    of ActionKind.economyDiplomacyAccept:
      if model.ui.mode != ViewMode.Economy or
          model.ui.economyFocus != EconomyFocus.Diplomacy:
        return
      let targets = model.espionageTargetHouses()
      if targets.len == 0:
        return
      let idx = clamp(
        model.ui.economyHouseIdx, 0, targets.len - 1)
      let targetId = targets[idx].id
      let myId = model.view.viewingHouse
      # Find first incoming Pending proposal from this target
      var foundId: Option[ProposalId] = none(ProposalId)
      for prop in model.view.pendingProposals:
        if prop.status == ProposalStatus.Pending and
            int(prop.proposer) == targetId and
            int(prop.target) == myId:
          foundId = some(prop.id)
          break
      if foundId.isNone:
        model.ui.statusMessage = "No incoming proposal to accept"
        return
      # Remove any existing staged accept/reject for this proposal
      var newCmds: seq[DiplomaticCommand] = @[]
      for cmd in model.ui.stagedDiplomaticCommands:
        if cmd.actionType in {DiplomaticActionType.AcceptProposal,
            DiplomaticActionType.RejectProposal} and
            cmd.proposalId == foundId:
          continue
        newCmds.add(cmd)
      newCmds.add(DiplomaticCommand(
        houseId: HouseId(myId),
        targetHouse: HouseId(targetId),
        actionType: DiplomaticActionType.AcceptProposal,
        proposalId: foundId,
        proposalType: none(ProposalType),
        message: none(string)
      ))
      model.ui.stagedDiplomaticCommands = newCmds
      model.ui.modifiedSinceSubmit = true
      let tgtName = model.view.houseNames.getOrDefault(
        targetId, "House " & $targetId)
      model.ui.statusMessage =
        "Staged: Accept proposal from " & tgtName

    of ActionKind.economyDiplomacyReject:
      if model.ui.mode != ViewMode.Economy or
          model.ui.economyFocus != EconomyFocus.Diplomacy:
        return
      let targets = model.espionageTargetHouses()
      if targets.len == 0:
        return
      let idx = clamp(
        model.ui.economyHouseIdx, 0, targets.len - 1)
      let targetId = targets[idx].id
      let myId = model.view.viewingHouse
      # Find first incoming Pending proposal from this target
      var foundId: Option[ProposalId] = none(ProposalId)
      for prop in model.view.pendingProposals:
        if prop.status == ProposalStatus.Pending and
            int(prop.proposer) == targetId and
            int(prop.target) == myId:
          foundId = some(prop.id)
          break
      if foundId.isNone:
        model.ui.statusMessage = "No incoming proposal to reject"
        return
      # Remove any existing staged accept/reject for this proposal
      var newCmds: seq[DiplomaticCommand] = @[]
      for cmd in model.ui.stagedDiplomaticCommands:
        if cmd.actionType in {DiplomaticActionType.AcceptProposal,
            DiplomaticActionType.RejectProposal} and
            cmd.proposalId == foundId:
          continue
        newCmds.add(cmd)
      newCmds.add(DiplomaticCommand(
        houseId: HouseId(myId),
        targetHouse: HouseId(targetId),
        actionType: DiplomaticActionType.RejectProposal,
        proposalId: foundId,
        proposalType: none(ProposalType),
        message: none(string)
      ))
      model.ui.stagedDiplomaticCommands = newCmds
      model.ui.modifiedSinceSubmit = true
      let tgtName = model.view.houseNames.getOrDefault(
        targetId, "House " & $targetId)
      model.ui.statusMessage =
        "Staged: Reject proposal from " & tgtName

    of ActionKind.dismissExportConfirm:
      model.ui.exportConfirmActive = false

    of ActionKind.exportMap:
      if model.ui.mode == ViewMode.Economy:
        model.ui.exportMapRequested = true

    of ActionKind.toggleAutoRepair,
       ActionKind.toggleAutoLoadMarines,
       ActionKind.toggleAutoLoadFighters:
      if model.ui.mode != ViewMode.PlanetDetail:
        return
      let colonyId = model.ui.selectedColonyId
      if colonyId <= 0:
        model.ui.statusMessage = "No colony selected"
        return
      let baseOpt = model.colonyInfoById(colonyId)
      if baseOpt.isNone:
        model.ui.statusMessage = "No colony selected"
        return
      let base = baseOpt.get()
      var autoRepair = base.autoRepair
      var autoLoadMarines = base.autoLoadMarines
      var autoLoadFighters = base.autoLoadFighters
      var existingIdx = -1
      for idx, cmd in model.ui.stagedColonyManagement:
        if int(cmd.colonyId) == colonyId:
          existingIdx = idx
          autoRepair = cmd.autoRepair
          autoLoadMarines = cmd.autoLoadMarines
          autoLoadFighters = cmd.autoLoadFighters
          break
      case proposal.actionKind
      of ActionKind.toggleAutoRepair:
        autoRepair = not autoRepair
        model.ui.statusMessage = "Auto-Repair: " &
          (if autoRepair: "ON" else: "OFF")
      of ActionKind.toggleAutoLoadMarines:
        autoLoadMarines = not autoLoadMarines
        model.ui.statusMessage = "Auto-Load Marines: " &
          (if autoLoadMarines: "ON" else: "OFF")
      of ActionKind.toggleAutoLoadFighters:
        autoLoadFighters = not autoLoadFighters
        model.ui.statusMessage = "Auto-Load Fighters: " &
          (if autoLoadFighters: "ON" else: "OFF")
      else:
        discard
      let matchesBase =
        autoRepair == base.autoRepair and
        autoLoadMarines == base.autoLoadMarines and
        autoLoadFighters == base.autoLoadFighters
      if matchesBase:
        if existingIdx >= 0:
          model.ui.stagedColonyManagement.delete(existingIdx)
      else:
        let cmd = ColonyManagementCommand(
          colonyId: ColonyId(colonyId),
          autoRepair: autoRepair,
          autoLoadFighters: autoLoadFighters,
          autoLoadMarines: autoLoadMarines,
          taxRate: none(int32)
        )
        if existingIdx >= 0:
          model.ui.stagedColonyManagement[existingIdx] = cmd
        else:
          model.ui.stagedColonyManagement.add(cmd)
        model.ui.modifiedSinceSubmit = true
    of ActionKind.intelEditNote:
      var systemId = model.ui.intelDetailSystemId
      var existingNote = ""
      if systemId > 0:
        for row in model.view.intelRows:
          if row.systemId == systemId:
            existingNote = row.notes
            break
      elif model.ui.selectedIdx >= 0 and
          model.ui.selectedIdx < model.view.intelRows.len:
        let row = model.view.intelRows[model.ui.selectedIdx]
        systemId = row.systemId
        existingNote = row.notes
      if systemId <= 0:
        model.ui.statusMessage = "No intel system selected"
        return
      model.ui.intelDetailSystemId = systemId
      model.ui.intelNoteEditActive = true
      model.ui.intelNoteEditor.clear()
      model.ui.intelNoteEditor.mode = EditorMode.MultiLine
      model.ui.intelNoteEditor.setText(existingNote)
      model.ui.intelNoteEditor.updatePreferredColumn()
      model.ensureIntelCursorVisible()
      model.ui.statusMessage = "Editing intel note"
    of ActionKind.intelNoteAppend:
      if not model.ui.intelNoteEditActive:
        return
      discard model.ui.intelNoteEditor.appendText(proposal.gameActionData)
      model.ui.intelNoteEditor.updatePreferredColumn()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteBackspace:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.backspace()
      model.ui.intelNoteEditor.updatePreferredColumn()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteCursorLeft:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.moveCursorLeft()
      model.ui.intelNoteEditor.updatePreferredColumn()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteCursorRight:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.moveCursorRight()
      model.ui.intelNoteEditor.updatePreferredColumn()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteCursorUp:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.moveCursorUpLine()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteCursorDown:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.moveCursorDownLine()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteDelete:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.delete()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteInsertNewline:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditor.insertNewline()
      model.ensureIntelCursorVisible()
    of ActionKind.intelNoteSave:
      if not model.ui.intelNoteEditActive:
        return
      let systemId = model.ui.intelDetailSystemId
      if systemId <= 0:
        model.ui.statusMessage = "No intel system selected"
        model.ui.intelNoteEditActive = false
        return
      model.ui.intelNoteSaveRequested = true
      model.ui.intelNoteSaveSystemId = systemId
      model.ui.intelNoteSaveText = model.ui.intelNoteEditor.value()
      for idx, row in model.view.intelRows:
        if row.systemId == systemId:
          model.view.intelRows[idx].notes =
            model.ui.intelNoteEditor.value()
          break
      model.ui.intelNoteEditActive = false
      model.ui.statusMessage = "Intel note saved"
    of ActionKind.intelNoteCancel:
      if not model.ui.intelNoteEditActive:
        return
      model.ui.intelNoteEditActive = false
      model.ui.intelNoteEditor.clear()
      model.ui.statusMessage = "Intel note edit canceled"
    of ActionKind.intelDetailNext:
      # Navigate to next intel system in detail view
      if model.ui.intelDetailSystemId <= 0 or
          model.view.intelRows.len == 0:
        return
      # Find current index
      var currentIdx = -1
      for i, row in model.view.intelRows:
        if row.systemId == model.ui.intelDetailSystemId:
          currentIdx = i
          break
      if currentIdx < 0:
        return
      # Cycle to next (wrapping)
      let nextIdx = if currentIdx >= model.view.intelRows.len - 1:
        0
      else:
        currentIdx + 1
      let nextRow = model.view.intelRows[nextIdx]
      model.ui.intelDetailSystemId = nextRow.systemId
      model.ui.intelDetailFleetPopupActive = false
      model.ui.intelDetailFleetSelectedIdx = 0
      model.ui.intelDetailFleetScrollOffset = 0
      model.ui.intelDetailNoteScrollOffset = 0
      # Update breadcrumb
      if model.ui.breadcrumbs.len > 0:
        model.ui.breadcrumbs[^1].label = nextRow.systemName
        model.ui.breadcrumbs[^1].entityId = nextRow.systemId
    of ActionKind.intelDetailPrev:
      # Navigate to previous intel system in detail view
      if model.ui.intelDetailSystemId <= 0 or
          model.view.intelRows.len == 0:
        return
      # Find current index
      var currentIdx = -1
      for i, row in model.view.intelRows:
        if row.systemId == model.ui.intelDetailSystemId:
          currentIdx = i
          break
      if currentIdx < 0:
        return
      # Cycle to previous (wrapping)
      let prevIdx = if currentIdx <= 0:
        model.view.intelRows.len - 1
      else:
        currentIdx - 1
      let prevRow = model.view.intelRows[prevIdx]
      model.ui.intelDetailSystemId = prevRow.systemId
      model.ui.intelDetailFleetPopupActive = false
      model.ui.intelDetailFleetSelectedIdx = 0
      model.ui.intelDetailFleetScrollOffset = 0
      model.ui.intelDetailNoteScrollOffset = 0
      # Update breadcrumb
      if model.ui.breadcrumbs.len > 0:
        model.ui.breadcrumbs[^1].label = prevRow.systemName
        model.ui.breadcrumbs[^1].entityId = prevRow.systemId
    of ActionKind.intelFleetPopupClose:
      model.ui.intelDetailFleetPopupActive = false
    of ActionKind.messageFocusNext:
      if model.ui.mode == ViewMode.Messages:
        case model.ui.inboxFocus
        of InboxPaneFocus.List:
          model.ui.inboxFocus = InboxPaneFocus.Detail
        of InboxPaneFocus.Detail:
          model.ui.inboxFocus = InboxPaneFocus.List
        of InboxPaneFocus.Compose:
          model.ui.inboxFocus = InboxPaneFocus.List
          model.ui.messageComposeActive = false
    of ActionKind.messageFocusPrev:
      if model.ui.mode == ViewMode.Messages:
        case model.ui.inboxFocus
        of InboxPaneFocus.List:
          model.ui.inboxFocus = InboxPaneFocus.Detail
        of InboxPaneFocus.Detail:
          model.ui.inboxFocus = InboxPaneFocus.List
        of InboxPaneFocus.Compose:
          model.ui.inboxFocus = InboxPaneFocus.Detail
          model.ui.messageComposeActive = false
    of ActionKind.messageSelectHouse:
      if model.ui.mode == ViewMode.Messages:
        let maxIdx = max(0,
          model.view.messageHouses.len - 1)
        let idx = clamp(
          model.ui.messageHouseIdx, 0, maxIdx)
        model.ui.messageHouseIdx = idx
        model.ui.messagesScroll.reset()
    of ActionKind.messageScrollUp:
      if model.ui.mode == ViewMode.Messages:
        if model.ui.inboxSection == InboxSection.Messages:
          model.ui.messagesScroll.scrollBy(
            -(max(1, model.ui.messagesScroll.viewportLength - 1)))
        else:
          model.ui.inboxDetailScroll.scrollBy(
            -(max(1, model.ui.inboxDetailScroll.viewportLength - 1)))
    of ActionKind.messageScrollDown:
      if model.ui.mode == ViewMode.Messages:
        if model.ui.inboxSection == InboxSection.Messages:
          model.ui.messagesScroll.scrollBy(
            max(1, model.ui.messagesScroll.viewportLength - 1))
        else:
          model.ui.inboxDetailScroll.scrollBy(
            max(1, model.ui.inboxDetailScroll.viewportLength - 1))
    of ActionKind.messageMarkRead:
      if model.ui.mode == ViewMode.Messages:
        model.ui.statusMessage = "Marking thread read..."
    of ActionKind.messageComposeToggle:
      if model.ui.mode == ViewMode.Messages:
        if model.ui.inboxSection ==
            InboxSection.Messages:
          model.ui.messageComposeActive =
            not model.ui.messageComposeActive
          model.ui.inboxFocus =
            InboxPaneFocus.Detail
    of ActionKind.messageComposeStartWithChar:
      if model.ui.mode == ViewMode.Messages and
          model.ui.inboxSection == InboxSection.Messages and
          model.ui.inboxFocus == InboxPaneFocus.Detail and
          not model.ui.messageComposeActive:
        model.ui.messageComposeActive = true
        model.ui.inboxFocus = InboxPaneFocus.Detail
        if proposal.gameActionData.len > 0:
          discard model.ui.messageComposeInput.appendChar(
            proposal.gameActionData[0]
          )
    of ActionKind.messageComposeAppend:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        if proposal.gameActionData.len > 0:
          discard model.ui.messageComposeInput.appendChar(
            proposal.gameActionData[0]
          )
    of ActionKind.messageComposeBackspace:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        model.ui.messageComposeInput.backspace()
    of ActionKind.messageComposeDelete:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        model.ui.messageComposeInput.delete()
    of ActionKind.messageComposeCursorLeft:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        model.ui.messageComposeInput.moveCursorLeft()
    of ActionKind.messageComposeCursorRight:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        model.ui.messageComposeInput.moveCursorRight()
    of ActionKind.messageSend:
      if model.ui.mode == ViewMode.Messages and model.ui.messageComposeActive:
        if not model.ui.messageComposeInput.isEmpty():
          model.ui.statusMessage = "Sending message..."
        else:
          model.ui.statusMessage = "Message is empty"
    of ActionKind.inboxJumpMessages:
      if model.ui.mode == ViewMode.Messages:
        # Jump to first message house item
        let items = model.view.inboxItems
        for i, item in items:
          if item.kind == InboxItemKind.MessageHouse:
            model.ui.inboxListIdx = i
            model.ui.inboxSection = InboxSection.Messages
            model.ui.messageHouseIdx = item.houseIdx
            model.ui.messagesScroll.reset()
            model.ui.inboxFocus = InboxPaneFocus.List
            break
    of ActionKind.inboxJumpReports:
      if model.ui.mode == ViewMode.Messages:
        # Jump to first turn bucket item
        let items = model.view.inboxItems
        for i, item in items:
          if item.kind == InboxItemKind.TurnBucket:
            model.ui.inboxListIdx = i
            model.ui.inboxSection = InboxSection.Reports
            model.ui.inboxTurnIdx = item.turnIdx
            model.ui.inboxTurnExpanded = false
            model.ui.inboxReportIdx = 0
            model.ui.inboxDetailScroll.reset()
            model.ui.inboxFocus = InboxPaneFocus.List
            break
    of ActionKind.inboxExpandTurn:
      if model.ui.mode == ViewMode.Messages and
          model.ui.inboxSection == InboxSection.Reports:
        if not model.ui.inboxTurnExpanded:
          model.ui.inboxTurnExpanded = true
          model.ui.inboxReportIdx = 0
          model.ui.inboxDetailScroll.reset()
    of ActionKind.inboxCollapseTurn:
      if model.ui.mode == ViewMode.Messages and
          model.ui.inboxSection == InboxSection.Reports:
        if model.ui.inboxTurnExpanded:
          model.ui.inboxTurnExpanded = false
          model.ui.inboxReportIdx = -1
          model.ui.inboxDetailScroll.reset()
    of ActionKind.inboxReportUp:
      if model.ui.mode == ViewMode.Messages and
          model.ui.inboxSection == InboxSection.Reports and
          model.ui.inboxTurnExpanded:
        if model.ui.inboxReportIdx > 0:
          model.ui.inboxReportIdx -= 1
          model.ui.inboxDetailScroll.reset()
    of ActionKind.inboxReportDown:
      if model.ui.mode == ViewMode.Messages and
          model.ui.inboxSection == InboxSection.Reports and
          model.ui.inboxTurnExpanded:
        let turnIdx = model.ui.inboxTurnIdx
        if turnIdx < model.view.turnBuckets.len:
          let maxRpt = max(0,
            model.view.turnBuckets[turnIdx].reports.len - 1)
          if model.ui.inboxReportIdx == -1:
            model.ui.inboxReportIdx = 0
            model.ui.inboxDetailScroll.reset()
          elif model.ui.inboxReportIdx < maxRpt:
            model.ui.inboxReportIdx += 1
            model.ui.inboxDetailScroll.reset()
    of ActionKind.lobbyGenerateKey:
      model.ui.lobbySessionKeyActive = true
      model.ui.lobbyWarning = "Session-only key: not saved"
      model.ui.lobbyProfilePubkeyInput.setText(
        "session-" & $getTime().toUnix()
      )
      model.ui.statusMessage = "Generated session key (not stored)"
      # Active games populated from Nostr events, not filesystem
    of ActionKind.lobbyJoinRefresh:
      # Games now discovered via Nostr events (30400), not filesystem scan
      # This action triggers a UI refresh; actual data comes from Nostr
      model.ui.lobbyJoinSelectedIdx = 0
      model.ui.statusMessage = "Refreshing game list from relay..."
    of ActionKind.lobbyJoinSubmit:
      if model.ui.lobbyInputMode == LobbyInputMode.Pubkey:
        let normalized = normalizePubkey(
          model.ui.lobbyProfilePubkeyInput.value()
        )
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkeyInput.setText(normalized.get())
          model.ui.lobbyInputMode = LobbyInputMode.None
          saveProfile("data",
            model.ui.lobbyProfilePubkeyInput.value(),
            model.ui.lobbyProfileNameInput.value(),
            model.ui.lobbySessionKeyActive)
          # Active games populated from TUI cache, not filesystem
      elif model.ui.lobbyInputMode == LobbyInputMode.Name:
        model.ui.lobbyInputMode = LobbyInputMode.None
        saveProfile("data",
          model.ui.lobbyProfilePubkeyInput.value(),
          model.ui.lobbyProfileNameInput.value(),
          model.ui.lobbySessionKeyActive)
      elif model.ui.lobbyJoinStatus == JoinStatus.SelectingGame:
        if model.ui.lobbyJoinSelectedIdx < model.view.lobbyJoinGames.len:
          let game = model.view.lobbyJoinGames[
            model.ui.lobbyJoinSelectedIdx
          ]
          model.ui.lobbyGameId = game.id
          model.ui.lobbyJoinStatus = JoinStatus.EnteringPubkey
          model.ui.statusMessage = "Enter Nostr pubkey"
        else:
          model.ui.lobbyJoinError = "No game selected"
      elif model.ui.lobbyJoinStatus == JoinStatus.EnteringPubkey:
        let normalized = normalizePubkey(
          model.ui.lobbyProfilePubkeyInput.value()
        )
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkeyInput.setText(normalized.get())
          model.ui.lobbyJoinStatus = JoinStatus.EnteringName
          model.ui.statusMessage = "Enter player name (optional)"
      elif model.ui.lobbyJoinStatus == JoinStatus.EnteringName:
        let normalized = normalizePubkey(
          model.ui.lobbyProfilePubkeyInput.value()
        )
        if normalized.isNone:
          model.ui.lobbyJoinError = "Invalid pubkey"
          model.ui.statusMessage = model.ui.lobbyJoinError
        else:
          model.ui.lobbyProfilePubkeyInput.setText(normalized.get())
          saveProfile("data",
            model.ui.lobbyProfilePubkeyInput.value(),
            model.ui.lobbyProfileNameInput.value(),
            model.ui.lobbySessionKeyActive)
          let inviteCode = invite_code.normalizeInviteCode(
            model.ui.entryModal.inviteCode()
          )
          if inviteCode.len == 0:
            model.ui.lobbyJoinStatus = JoinStatus.Failed
            model.ui.lobbyJoinError = "Invite code required"
            model.ui.statusMessage = model.ui.lobbyJoinError
          elif model.ui.lobbyGameId.len == 0:
            model.ui.lobbyJoinStatus = JoinStatus.Failed
            model.ui.lobbyJoinError = "Game ID missing"
            model.ui.statusMessage = model.ui.lobbyJoinError
          else:
            model.ui.nostrJoinRequested = true
            model.ui.nostrJoinSent = false
            model.ui.nostrJoinInviteCode = inviteCode
            model.ui.nostrJoinGameId = model.ui.lobbyGameId
            model.ui.nostrJoinPubkey =
              model.ui.lobbyProfilePubkeyInput.value()
            model.ui.lobbyJoinStatus = JoinStatus.WaitingResponse
            model.ui.statusMessage = "Submitting join request"
    of ActionKind.lobbyJoinPoll:
      if model.ui.lobbyJoinStatus == JoinStatus.WaitingResponse:
        model.ui.statusMessage = "Waiting for join response..."
    of ActionKind.lobbyReturn:
      model.ui.appPhase = AppPhase.Lobby
      model.ui.statusMessage = "Returned to lobby"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditPubkey:
      model.ui.lobbyInputMode = LobbyInputMode.Pubkey
      model.ui.lobbyProfilePubkeyInput.moveCursorEnd()
      model.ui.statusMessage = "Enter Nostr pubkey"
      # Active games already in model from TUI cache
    of ActionKind.lobbyEditName:
      model.ui.lobbyInputMode = LobbyInputMode.Name
      model.ui.lobbyProfileNameInput.moveCursorEnd()
      model.ui.statusMessage = "Enter player name"
    of ActionKind.lobbyBackspace:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.ui.lobbyProfilePubkeyInput.backspace()
        # Active games filtered by pubkey from TUI cache
      of LobbyInputMode.Name:
        model.ui.lobbyProfileNameInput.backspace()
      else:
        discard
    of ActionKind.lobbyDelete:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.ui.lobbyProfilePubkeyInput.delete()
      of LobbyInputMode.Name:
        model.ui.lobbyProfileNameInput.delete()
      else:
        discard
    of ActionKind.lobbyCursorLeft:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.ui.lobbyProfilePubkeyInput.moveCursorLeft()
      of LobbyInputMode.Name:
        model.ui.lobbyProfileNameInput.moveCursorLeft()
      else:
        discard
    of ActionKind.lobbyCursorRight:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        model.ui.lobbyProfilePubkeyInput.moveCursorRight()
      of LobbyInputMode.Name:
        model.ui.lobbyProfileNameInput.moveCursorRight()
      else:
        discard
    of ActionKind.lobbyInputAppend:
      case model.ui.lobbyInputMode
      of LobbyInputMode.Pubkey:
        discard model.ui.lobbyProfilePubkeyInput.appendText(
          proposal.gameActionData
        )
      of LobbyInputMode.Name:
        discard model.ui.lobbyProfileNameInput.appendText(
          proposal.gameActionData
        )
      else:
        discard
    # Entry modal actions
    of ActionKind.entryUp:
      if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
        model.ui.entryModal.moveIdentitySelection(-1)
      elif model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
        model.ui.entryModal.movePlayerGameSelection(-1)
      else:
        model.ui.entryModal.moveUp()
    of ActionKind.entryDown:
      if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
        model.ui.entryModal.moveIdentitySelection(1)
      elif model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
        model.ui.entryModal.movePlayerGameSelection(1)
      else:
        model.ui.entryModal.moveDown()
    of ActionKind.entryPageUp:
      if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
        model.ui.entryModal.moveIdentitySelection(-10)
      elif model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
        model.ui.entryModal.movePlayerGameSelection(-10)
    of ActionKind.entryPageDown:
      if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
        model.ui.entryModal.moveIdentitySelection(10)
      elif model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
        model.ui.entryModal.movePlayerGameSelection(10)
    of ActionKind.entrySelect:
      # Enter selected game from game list
      let gameOpt = model.ui.entryModal.selectedGame()
      if gameOpt.isSome:
        let game = gameOpt.get()
        model.ui.loadGameRequested = true
        model.ui.loadGameId = game.id
        model.ui.loadHouseId = game.houseId
        model.ui.statusMessage = "Loading game..."
    of ActionKind.entryPlayerGamesMenu:
      if model.ui.entryModal.mode == EntryModalMode.ManagePlayerGames:
        model.ui.entryModal.closePlayerGamesManager()
      else:
        model.ui.entryModal.openPlayerGamesManager()
      model.ui.statusMessage = ""
    of ActionKind.entryPlayerGamesSelect:
      let gameOpt = model.ui.entryModal.selectedGame()
      if gameOpt.isSome:
        let game = gameOpt.get()
        model.ui.loadGameRequested = true
        model.ui.loadGameId = game.id
        model.ui.loadHouseId = game.houseId
        model.ui.statusMessage = "Loading game..."
        model.ui.entryModal.closePlayerGamesManager()
    of ActionKind.entryImport:
      model.ui.entryModal.startImport()
      model.ui.statusMessage = "Enter nsec or hex secret key"
    of ActionKind.entryImportConfirm:
      if model.ui.entryModal.confirmImport():
        model.ui.statusMessage = "Identity imported successfully"
      else:
        model.ui.statusMessage =
          "Import failed: " & model.ui.entryModal.importError
    of ActionKind.entryImportCancel:
      model.ui.entryModal.cancelImport()
      model.ui.statusMessage = ""
    of ActionKind.entryToggleMask:
      model.ui.entryModal.toggleMask()
    of ActionKind.entryPasswordAppend:
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.passwordInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryPasswordBackspace:
      model.ui.entryModal.passwordInput.backspace()
    of ActionKind.entryPasswordConfirm:
      if model.ui.entryModal.unlockWallet():
        model.ui.statusMessage = "Wallet unlocked successfully"
      else:
        model.ui.statusMessage = "Unlock failed: " & model.ui.entryModal.importError
    of ActionKind.entryImportAppend:
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.importInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryImportBackspace:
      model.ui.entryModal.importInput.backspace()
    of ActionKind.entryIdentityCreate:
      model.ui.entryModal.createIdentity()
      model.ui.statusMessage = "Created and selected new local identity"
    of ActionKind.entryIdentityMenu:
      if model.ui.entryModal.mode == EntryModalMode.ManageIdentities:
        model.ui.entryModal.closeIdentityManager()
      elif model.ui.entryModal.mode == EntryModalMode.ChangePasswordPrompt:
        model.ui.entryModal.cancelChangePassword()
      else:
        model.ui.entryModal.openIdentityManager()
      model.ui.statusMessage = ""
    of ActionKind.entryIdentityDelete:
      # Only open popup if there is more than one identity to delete
      let wallet = model.ui.entryModal.wallet
      if wallet.identities.len <= 1:
        model.ui.statusMessage = "Cannot delete last identity"
      else:
        model.ui.identityDeleteConfirmActive = true
        model.ui.statusMessage = "Confirm identity removal"
    of ActionKind.entryIdentityDeleteConfirm:
      if model.ui.entryModal.deleteSelectedIdentity():
        model.ui.statusMessage = "Identity removed"
      else:
        model.ui.statusMessage = "Cannot delete last identity"
      model.ui.identityDeleteConfirmActive = false
    of ActionKind.entryIdentityDeleteCancel:
      model.ui.identityDeleteConfirmActive = false
      model.ui.statusMessage = ""
    of ActionKind.entryIdentityActivate:
      discard model.ui.entryModal.applyIdentitySelection()
      model.ui.entryModal.closeIdentityManager()
      model.ui.statusMessage = "Identity activated"
    of ActionKind.entryCreatePasswordAppend:
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.createPasswordInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryCreatePasswordBackspace:
      model.ui.entryModal.createPasswordInput.backspace()
    of ActionKind.entryCreatePasswordConfirm:
      if model.ui.entryModal.confirmCreatePassword():
        model.ui.statusMessage = "Wallet created successfully"
        model.ui.entryModal.identityNeedsRefresh = true
      else:
        model.ui.statusMessage =
          "Failed to create wallet: " & model.ui.entryModal.importError
    of ActionKind.entryChangePassword:
      model.ui.entryModal.openChangePassword()
      model.ui.statusMessage = ""
    of ActionKind.entryChangePasswordAppend:
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.changePasswordInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryChangePasswordBackspace:
      model.ui.entryModal.changePasswordInput.backspace()
    of ActionKind.entryChangePasswordConfirm:
      model.ui.entryModal.confirmChangePassword()
      model.ui.statusMessage = "Wallet password updated"
    of ActionKind.entryDelete:
      if model.ui.entryModal.mode == EntryModalMode.PasswordPrompt:
        model.ui.entryModal.passwordInput.delete()
      elif model.ui.entryModal.mode == EntryModalMode.CreatePasswordPrompt:
        model.ui.entryModal.createPasswordInput.delete()
      elif model.ui.entryModal.mode == EntryModalMode.ChangePasswordPrompt:
        model.ui.entryModal.changePasswordInput.delete()
      elif model.ui.entryModal.mode == EntryModalMode.ImportNsec:
        model.ui.entryModal.importInput.delete()
      elif model.ui.entryModal.editingRelay:
        model.ui.entryModal.relayInput.delete()
      elif model.ui.entryModal.mode == EntryModalMode.CreateGame and
          model.ui.entryModal.createField == CreateGameField.GameName:
        model.ui.entryModal.createNameInput.delete()
      elif model.ui.entryModal.mode == EntryModalMode.Normal:
        case model.ui.entryModal.focus
        of EntryModalFocus.InviteCode:
          model.ui.entryModal.inviteInput.delete()
        of EntryModalFocus.RelayUrl:
          model.ui.entryModal.relayInput.delete()
        else:
          discard
    of ActionKind.entryCursorLeft:
      if model.ui.entryModal.mode == EntryModalMode.PasswordPrompt:
        model.ui.entryModal.passwordInput.moveCursorLeft()
      elif model.ui.entryModal.mode == EntryModalMode.CreatePasswordPrompt:
        model.ui.entryModal.createPasswordInput.moveCursorLeft()
      elif model.ui.entryModal.mode == EntryModalMode.ChangePasswordPrompt:
        model.ui.entryModal.changePasswordInput.moveCursorLeft()
      elif model.ui.entryModal.mode == EntryModalMode.ImportNsec:
        model.ui.entryModal.importInput.moveCursorLeft()
      elif model.ui.entryModal.editingRelay:
        model.ui.entryModal.relayInput.moveCursorLeft()
      elif model.ui.entryModal.mode == EntryModalMode.CreateGame and
          model.ui.entryModal.createField == CreateGameField.GameName:
        model.ui.entryModal.createNameInput.moveCursorLeft()
      elif model.ui.entryModal.mode == EntryModalMode.Normal:
        case model.ui.entryModal.focus
        of EntryModalFocus.InviteCode:
          model.ui.entryModal.inviteInput.moveCursorLeft()
        of EntryModalFocus.RelayUrl:
          model.ui.entryModal.relayInput.moveCursorLeft()
        else:
          discard
    of ActionKind.entryCursorRight:
      if model.ui.entryModal.mode == EntryModalMode.PasswordPrompt:
        model.ui.entryModal.passwordInput.moveCursorRight()
      elif model.ui.entryModal.mode == EntryModalMode.CreatePasswordPrompt:
        model.ui.entryModal.createPasswordInput.moveCursorRight()
      elif model.ui.entryModal.mode == EntryModalMode.ChangePasswordPrompt:
        model.ui.entryModal.changePasswordInput.moveCursorRight()
      elif model.ui.entryModal.mode == EntryModalMode.ImportNsec:
        model.ui.entryModal.importInput.moveCursorRight()
      elif model.ui.entryModal.editingRelay:
        model.ui.entryModal.relayInput.moveCursorRight()
      elif model.ui.entryModal.mode == EntryModalMode.CreateGame and
          model.ui.entryModal.createField == CreateGameField.GameName:
        model.ui.entryModal.createNameInput.moveCursorRight()
      elif model.ui.entryModal.mode == EntryModalMode.Normal:
        case model.ui.entryModal.focus
        of EntryModalFocus.InviteCode:
          model.ui.entryModal.inviteInput.moveCursorRight()
        of EntryModalFocus.RelayUrl:
          model.ui.entryModal.relayInput.moveCursorRight()
        else:
          discard
    of ActionKind.entryInviteAppend:
      if proposal.gameActionData.len > 0:
        # Validate: allow lowercase letters, hyphen, @, :, ., and digits
        # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
        let ch = proposal.gameActionData[0].toLowerAscii()
        if ch in 'a'..'z' or ch in '0'..'9' or ch in {'-', '@', ':', '.'}:
          discard model.ui.entryModal.inviteInput.appendChar(ch)
          model.ui.entryModal.inviteError = ""
          # Focus invite code field when typing starts
          model.ui.entryModal.focusInviteCode()
    of ActionKind.entryInviteBackspace:
      model.ui.entryModal.inviteInput.backspace()
      model.ui.entryModal.inviteError = ""
    of ActionKind.entryInviteSubmit:
      # Submit invite code to server
      # Format: code@host:port (e.g., velvet-mountain@play.ec4x.io:8080)
      if model.ui.entryModal.inviteInput.isEmpty():
        model.ui.entryModal.setInviteError("Enter an invite code")
      else:
        let input = model.ui.entryModal.inviteCode()
        let parsed = parseInviteCode(input)

        if not isValidInviteCodeFormat(parsed.code):
          model.ui.entryModal.setInviteError("Invalid code format")
        elif not parsed.hasRelay() and model.ui.nostrRelayUrl.len == 0:
          model.ui.entryModal.setInviteError("No relay in code, none configured")
        else:
          let identity = model.ui.entryModal.identity
          model.ui.nostrJoinRequested = true
          model.ui.nostrJoinSent = false
          model.ui.nostrJoinInviteCode = parsed.code
          model.ui.nostrJoinRelayUrl = if parsed.hasRelay():
            parsed.relayUrl
          else:
            model.ui.nostrRelayUrl
          model.ui.nostrJoinGameId = "invite"
          model.ui.nostrJoinPubkey = identity.npubHex
          logInfo("JOIN", "FLAGS SET: requested=true, inviteCode=",
            model.ui.nostrJoinInviteCode,
            " relayUrl=", model.ui.nostrJoinRelayUrl,
            " gameId=", model.ui.nostrJoinGameId)
          model.ui.entryModal.setInviteError(
            "Joining... game will appear in YOUR GAMES")
          model.ui.entryModal.clearInviteCode()
          model.ui.lobbyJoinStatus = JoinStatus.WaitingResponse
          model.ui.statusMessage = "Join request sent - " &
            "game will appear when confirmed"

    of ActionKind.entryAdminSelect:
      # Dispatch based on selected admin menu item
      let menuItem = model.ui.entryModal.selectedAdminMenuItem()
      if menuItem.isSome:
        case menuItem.get()
        of AdminMenuItem.CreateGame:
          # Switch to game creation mode
          model.ui.entryModal.mode = EntryModalMode.CreateGame
          model.ui.statusMessage = "Create a new game"
        of AdminMenuItem.ManageGames:
          # Switch to manage games mode
          model.ui.entryModal.mode = EntryModalMode.ManageGames
          model.ui.statusMessage = "Manage your games"
    of ActionKind.entryAdminCreateGame:
      # Direct action to enter game creation mode
      model.ui.entryModal.mode = EntryModalMode.CreateGame
      model.ui.statusMessage = "Create a new game"
    of ActionKind.entryAdminManageGames:
      # Direct action to enter manage games mode
      model.ui.entryModal.mode = EntryModalMode.ManageGames
      model.ui.statusMessage = "Manage your games"
    of ActionKind.entryRelayEdit:
      # Start editing relay URL
      model.ui.entryModal.startEditingRelay()
      model.ui.statusMessage = "Edit relay URL"
    of ActionKind.entryRelayAppend:
      # Append character to relay URL
      if proposal.gameActionData.len > 0:
        discard model.ui.entryModal.relayInput.appendChar(
          proposal.gameActionData[0])
    of ActionKind.entryRelayBackspace:
      # Backspace in relay URL
      model.ui.entryModal.relayInput.backspace()
    of ActionKind.entryRelayConfirm:
      # Confirm relay URL edit
      model.ui.entryModal.stopEditingRelay()
      model.ui.statusMessage = "Relay: " & model.ui.entryModal.relayUrl()
    # Game creation actions
    of ActionKind.createGameUp:
      model.ui.entryModal.createFieldUp()
    of ActionKind.createGameDown:
      model.ui.entryModal.createFieldDown()
    of ActionKind.createGameLeft:
      if model.ui.entryModal.createField == CreateGameField.PlayerCount:
        model.ui.entryModal.decrementPlayerCount()
    of ActionKind.createGameRight:
      if model.ui.entryModal.createField == CreateGameField.PlayerCount:
        model.ui.entryModal.incrementPlayerCount()
    of ActionKind.createGameAppend:
      if model.ui.entryModal.createField == CreateGameField.GameName:
        if proposal.gameActionData.len > 0:
          if model.ui.entryModal.createNameInput.appendChar(
               proposal.gameActionData[0]):
            model.ui.entryModal.createError = ""
    of ActionKind.createGameBackspace:
      if model.ui.entryModal.createField == CreateGameField.GameName:
        model.ui.entryModal.createNameInput.backspace()
        model.ui.entryModal.createError = ""
    of ActionKind.createGameConfirm:
      if model.ui.entryModal.createField == CreateGameField.ConfirmCreate:
        # Validate and create game
        if model.ui.entryModal.createNameInput.isEmpty():
          model.ui.entryModal.setCreateError("Game name is required")
        else:
          # TODO: implement game creation protocol (or remove if handled entirely via CLI)
          model.ui.statusMessage = "Creating game: " &
            model.ui.entryModal.createGameName() &
            " (" & $model.ui.entryModal.createPlayerCount & " players)"
          model.ui.entryModal.cancelGameCreation()
      elif model.ui.entryModal.createField == CreateGameField.PlayerCount:
        # Enter on player count field moves to next field
        model.ui.entryModal.createFieldDown()
      elif model.ui.entryModal.createField == CreateGameField.GameName:
        # Enter on game name field moves to next field
        model.ui.entryModal.createFieldDown()
    of ActionKind.createGameCancel:
      model.ui.entryModal.cancelGameCreation()
      model.ui.statusMessage = "Game creation cancelled"
    of ActionKind.manageGamesCancel:
      model.ui.entryModal.mode = EntryModalMode.Normal
      model.ui.statusMessage = ""
    of ActionKind.enterExpertMode:
      model.enterExpertMode()
      model.ui.statusMessage =
        "Expert mode active (type command, ESC to cancel)"
    of ActionKind.exitExpertMode:
      model.exitExpertMode()
      model.ui.statusMessage = ""
    of ActionKind.expertSubmit:
      let inputStr = model.ui.expertModeInput.value()
      let matches = getAutocompleteSuggestions(model, inputStr)
      if matches.len > 0:
        clampExpertPaletteSelection(model)
        let selection = model.ui.expertPaletteSelection
        if selection >= 0 and selection < matches.len:
          let chosen = matches[selection]
          
          # Basic auto-complete insertion
          let tokens = tokenize(inputStr)
          if tokens.len > 0:
            var targetToken = tokens[^1]
            if inputStr.endsWith(" "): targetToken = ""
            
            var newInput = inputStr
            if targetToken.len > 0:
              newInput = inputStr[0 ..< inputStr.len - targetToken.len]
            
            let appendText = if chosen.text.contains(" "): "\"" & chosen.text & "\"" else: chosen.text
            model.ui.expertModeInput.setText(newInput & appendText & " ")
            model.clearExpertFeedback()
            model.ui.expertPaletteSelection = 0
            return

      # Parse and execute expert mode command
      let cmdAst = parseExpertCommand(inputStr)
      
      case cmdAst.kind
      of ExpertCommandKind.ParseError:
        model.setExpertFeedback("Error: " & cmdAst.errorMessage)
      of ExpertCommandKind.MetaHelp:
        model.setExpertFeedback("Commands: fleet, colony, tech, spy, gov, map | Meta: clear, list, drop, submit")
        model.addToExpertHistory(inputStr)
      of ExpertCommandKind.MetaClear:
        let count = model.stagedCommandCount()
        model.ui.stagedFleetCommands.clear()
        model.ui.stagedBuildCommands.setLen(0)
        model.ui.stagedRepairCommands.setLen(0)
        model.ui.stagedScrapCommands.setLen(0)
        model.ui.stagedColonyManagement.setLen(0)
        model.ui.modifiedSinceSubmit = true
        model.setExpertFeedback("Cleared " & $count & " staged commands")
        model.addToExpertHistory(inputStr)
      of ExpertCommandKind.MetaList:
        model.setExpertFeedback(model.stagedCommandsSummary())
        model.addToExpertHistory(inputStr)
      of ExpertCommandKind.MetaDrop:
        let dropIdx = cmdAst.dropIndex
        let entries = model.stagedCommandEntries()
        if dropIdx <= 0 or dropIdx > entries.len:
          model.setExpertFeedback("Invalid command index")
        else:
          let entry = entries[dropIdx - 1]
          if model.dropStagedCommand(entry):
            model.ui.modifiedSinceSubmit = true
            model.setExpertFeedback("Dropped command " & $dropIdx)
          else:
            model.setExpertFeedback("Failed to drop command")
        model.addToExpertHistory(inputStr)
      of ExpertCommandKind.MetaSubmit:
        if model.stagedCommandCount() > 0:
          model.ui.turnSubmissionPending = true
          let count = model.stagedCommandCount()
          model.setExpertFeedback("Submitting " & $count & " commands...")
        else:
          model.setExpertFeedback("No commands to submit")
        model.addToExpertHistory(inputStr)
      else:
        let execResult = executeExpertCommand(model, cmdAst)
        if execResult.success:
          model.setExpertFeedback(execResult.message)
        else:
          model.setExpertFeedback("Error: " & execResult.message)
        model.addToExpertHistory(inputStr)

      # Keep expert mode active after submit
      model.ui.expertModeInput.clear()
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputAppend:
      # Append character to expert mode input
      discard model.ui.expertModeInput.appendText(proposal.gameActionData)
      resetExpertPaletteSelection(model)
    of ActionKind.expertInputBackspace:
      # Remove last character
      model.ui.expertModeInput.backspace()
      resetExpertPaletteSelection(model)
    of ActionKind.expertCursorLeft:
      model.ui.expertModeInput.moveCursorLeft()
      resetExpertPaletteSelection(model)
    of ActionKind.expertCursorRight:
      model.ui.expertModeInput.moveCursorRight()
      resetExpertPaletteSelection(model)
    of ActionKind.expertHistoryPrev:
      clampExpertPaletteSelection(model)
      if model.ui.expertPaletteSelection > 0:
        model.ui.expertPaletteSelection -= 1
    of ActionKind.expertHistoryNext:
      clampExpertPaletteSelection(model)
      let matches = getAutocompleteSuggestions(model, model.ui.expertModeInput.value())
      if matches.len == 0:
        model.ui.expertPaletteSelection = -1
      elif model.ui.expertPaletteSelection < matches.len - 1:
        model.ui.expertPaletteSelection += 1
    of ActionKind.submitTurn:
      # Open confirmation modal (if commands are staged)
      if model.stagedCommandCount() > 0:
        model.ui.submitConfirmActive = true
      else:
        model.ui.statusMessage = "No commands staged - nothing to submit"
    of ActionKind.submitConfirm:
      # User confirmed in the dialog - trigger submission
      model.ui.submitConfirmActive = false
      model.ui.turnSubmissionPending = true
    of ActionKind.submitCancel:
      # User cancelled the dialog
      model.ui.submitConfirmActive = false
      model.ui.statusMessage = "Submission cancelled"
    of ActionKind.quitConfirm:
      model.ui.running = false
      model.ui.quitConfirmationActive = false
      model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.ui.statusMessage = "Exiting..."
    of ActionKind.quitCancel:
      model.ui.quitConfirmationActive = false
      model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
      model.ui.statusMessage = "Quit cancelled"
    of ActionKind.quitToggle:
      if model.ui.quitConfirmationChoice == QuitConfirmationChoice.QuitStay:
        model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitExit
      else:
        model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
    of ActionKind.fleetBatchCommand:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            let roe = model.getCursorFleetRoe()
            # Open FleetDetail modal in CommandPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.roeValue = roe
            model.openCommandPicker()
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.fleetId = 0
          model.openCommandPicker()
          model.ui.fleetDetailModal.directSubModal = true
    of ActionKind.fleetBatchROE:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            let roe = model.getCursorFleetRoe()
            # Open FleetDetail modal in ROEPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.roeValue = roe
            model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
          model.ui.fleetDetailModal.fleetId = 0
          model.ui.fleetDetailModal.roeValue = 6
          model.ui.fleetDetailModal.directSubModal = true
    of ActionKind.fleetBatchZeroTurn:
      if model.ui.mode == ViewMode.Fleets:
        if model.ui.fleetViewMode == FleetViewMode.SystemView and
           model.ui.fleetConsoleFocus != FleetConsoleFocus.FleetsPane:
          discard  # No-op when system pane is focused
        # Cursor-implicit selection: if no X-selection exists, use cursor-row fleet
        elif model.ui.selectedFleetIds.len == 0:
          let fleetIdOpt = model.getCursorFleetId()
          if fleetIdOpt.isSome:
            let fleetId = fleetIdOpt.get()
            # Open FleetDetail modal in ZTCPicker sub-modal
            model.ui.mode = ViewMode.FleetDetail
            model.resetBreadcrumbs(ViewMode.FleetDetail)
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
            model.ui.fleetDetailModal.ztcPickerCommands =
              model.buildZtcPickerList()
            if model.ui.fleetDetailModal.ztcPickerCommands.len == 0:
              model.ui.mode = ViewMode.Fleets
              model.resetBreadcrumbs(ViewMode.Fleets)
              model.ui.statusMessage =
                "No applicable zero-turn commands"
              return
            model.ui.fleetDetailModal.ztcIdx = 0
            model.ui.fleetDetailModal.ztcDigitBuffer = ""
            model.ui.fleetDetailModal.ztcType = none(ZeroTurnCommandType)
            model.ui.fleetDetailModal.directSubModal = true
        else:
          # Batch mode: act on all X-selected fleets
          model.ui.mode = ViewMode.FleetDetail
          model.resetBreadcrumbs(ViewMode.FleetDetail)
          model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
          model.ui.fleetDetailModal.ztcPickerCommands =
            model.buildZtcPickerList()
          if model.ui.fleetDetailModal.ztcPickerCommands.len == 0:
            model.ui.mode = ViewMode.Fleets
            model.resetBreadcrumbs(ViewMode.Fleets)
            model.ui.statusMessage =
              "No applicable zero-turn commands"
            return
          model.ui.fleetDetailModal.fleetId = 0
          model.ui.fleetDetailModal.ztcIdx = 0
          model.ui.fleetDetailModal.ztcDigitBuffer = ""
          model.ui.fleetDetailModal.ztcType = none(ZeroTurnCommandType)
          model.ui.fleetDetailModal.directSubModal = true
    else:
      model.ui.statusMessage = "Action: " & actionKindToStr(proposal.actionKind)
  of ProposalKind.pkSelection:
    if proposal.actionKind == ActionKind.lobbyEnterGame:
      if model.ui.lobbySelectedIdx < model.view.lobbyActiveGames.len:
        let game = model.view.lobbyActiveGames[model.ui.lobbySelectedIdx]
        model.ui.loadGameRequested = true
        model.ui.loadGameId = game.id
        model.ui.loadHouseId = game.houseId
        model.ui.statusMessage = "Loading game..."
        model.ui.lobbyInputMode = LobbyInputMode.None
    elif model.ui.mode == ViewMode.Planets and proposal.selectIdx == -1:
      if model.ui.selectedIdx < 0 or
          model.ui.selectedIdx >= model.view.planetsRows.len:
        model.ui.statusMessage = "No colony selected"
      else:
        let row = model.view.planetsRows[model.ui.selectedIdx]
        if row.colonyId.isSome and row.isOwned:
          model.ui.previousMode = model.ui.mode
          model.ui.mode = ViewMode.PlanetDetail
          let colonyId = row.colonyId.get()
          model.ui.selectedColonyId = colonyId
          # Push breadcrumb with system name (colony at that location)
          model.pushBreadcrumb(row.systemName, ViewMode.PlanetDetail, colonyId)
        else:
          model.ui.statusMessage = "No colony selected"
    # NOTE: Fleet selection now handled by openFleetDetailModal action (Enter key)
    # Old ViewMode.FleetDetail inline view removed in favor of popup modal
    else:
      discard
  else:
    discard


# ============================================================================
# Error Acceptor
# ============================================================================

proc errorAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle error proposals
  if proposal.kind == ProposalKind.pkError:
    model.ui.statusMessage = "Error: " & proposal.errorMsg

proc quitAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle quit proposals by showing confirmation
  if proposal.kind != ProposalKind.pkQuit:
    return
  model.ui.quitConfirmationActive = true
  model.ui.quitConfirmationChoice = QuitConfirmationChoice.QuitStay
  model.ui.statusMessage = "Quit? (Y/N)"

# ============================================================================
# Build Modal Acceptor
# ============================================================================

proc buildRowCountForCategory(category: BuildCategory): int =
  buildRowCount(category)

proc buildRowKeyAt(state: BuildModalState, idx: int): BuildRowKey =
  buildRowKey(state.category, idx)

proc buildOptionMatchesRow(opt: BuildOption, key: BuildRowKey): bool =
  case opt.kind
  of BuildOptionKind.Ship:
    if key.shipClass.isNone:
      return false
    try:
      let cls =
        parseEnum[ShipClass](opt.name.replace(" ", ""))
      cls == key.shipClass.get()
    except:
      false
  of BuildOptionKind.Ground:
    if key.groundClass.isNone:
      return false
    try:
      let cls =
        parseEnum[GroundClass](opt.name.replace(" ", ""))
      cls == key.groundClass.get()
    except:
      false
  of BuildOptionKind.Facility:
    if key.facilityClass.isNone:
      return false
    try:
      let cls =
        parseEnum[FacilityClass](opt.name.replace(" ", ""))
      cls == key.facilityClass.get()
    except:
      false

proc isBuildable(state: BuildModalState, key: BuildRowKey): bool =
  if buildRowCst(key) > state.cstLevel:
    return false
  for opt in state.availableOptions:
    if buildOptionMatchesRow(opt, key):
      if key.kind == BuildOptionKind.Ship and key.shipClass.isSome:
        let cls = key.shipClass.get()
        if construction_docks.shipRequiresDock(cls):
          var pendingUsed = 0
          let colonyId = ColonyId(state.colonyId.uint32)
          for cmd in state.stagedBuildCommands:
            if cmd.colonyId != colonyId:
              continue
            if cmd.buildType == BuildType.Ship and
                cmd.shipClass.isSome and
                construction_docks.shipRequiresDock(cmd.shipClass.get()):
              pendingUsed += cmd.quantity.int
          let available =
            state.dockSummary.constructionAvailable - pendingUsed
          if available <= 0:
            return false
      return true
  false

proc pendingPpCost(state: BuildModalState): int =
  var total = 0
  let colonyId = ColonyId(state.colonyId.uint32)
  for cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    var itemCost = 0
    case cmd.buildType
    of BuildType.Ship:
      if cmd.shipClass.isSome:
        itemCost = buildRowCost(BuildRowKey(
          kind: BuildOptionKind.Ship,
          shipClass: cmd.shipClass,
          groundClass: none(GroundClass),
          facilityClass: none(FacilityClass)
        ))
    of BuildType.Ground:
      if cmd.groundClass.isSome:
        itemCost = buildRowCost(BuildRowKey(
          kind: BuildOptionKind.Ground,
          shipClass: none(ShipClass),
          groundClass: cmd.groundClass,
          facilityClass: none(FacilityClass)
        ))
    of BuildType.Facility:
      if cmd.facilityClass.isSome:
        itemCost = buildRowCost(BuildRowKey(
          kind: BuildOptionKind.Facility,
          shipClass: none(ShipClass),
          groundClass: none(GroundClass),
          facilityClass: cmd.facilityClass
        ))
    else:
      discard
    total += itemCost * cmd.quantity.int
  total

proc stagedBuildIdx(
    state: BuildModalState, key: BuildRowKey
): int =
  let colonyId = ColonyId(state.colonyId.uint32)
  for idx, cmd in state.stagedBuildCommands:
    if cmd.colonyId != colonyId:
      continue
    case key.kind
    of BuildOptionKind.Ship:
      if cmd.buildType == BuildType.Ship and
          cmd.shipClass.isSome and key.shipClass.isSome and
          cmd.shipClass.get() == key.shipClass.get():
        return idx
    of BuildOptionKind.Ground:
      if cmd.buildType == BuildType.Ground and
          cmd.groundClass.isSome and key.groundClass.isSome and
          cmd.groundClass.get() == key.groundClass.get():
        return idx
    of BuildOptionKind.Facility:
      if cmd.buildType == BuildType.Facility and
          cmd.facilityClass.isSome and key.facilityClass.isSome and
          cmd.facilityClass.get() == key.facilityClass.get():
        return idx
  -1

proc incSelectedQty(model: var TuiModel) =
  if model.ui.buildModal.focus != BuildModalFocus.BuildList:
    return
  let maxIdx = buildRowCountForCategory(
    model.ui.buildModal.category
  ) - 1
  if model.ui.buildModal.selectedBuildIdx < 0 or
      model.ui.buildModal.selectedBuildIdx > maxIdx:
    return
  let key = buildRowKeyAt(
    model.ui.buildModal,
    model.ui.buildModal.selectedBuildIdx
  )
  if not isBuildable(model.ui.buildModal, key):
    model.ui.statusMessage = "Not buildable"
    return
  let cost = buildRowCost(key)
  let pendingCost = pendingPpCost(model.ui.buildModal)
  if model.ui.buildModal.ppAvailable >= 0 and
      pendingCost + cost > model.ui.buildModal.ppAvailable:
    model.ui.statusMessage = "Insufficient PP"
    return
  var candidate = BuildCommand(
    colonyId: ColonyId(model.ui.buildModal.colonyId.uint32),
    buildType: BuildType.Ship,
    quantity: 1,
    shipClass: none(ShipClass),
    facilityClass: none(FacilityClass),
    groundClass: none(GroundClass),
    industrialUnits: 0
  )
  case key.kind
  of BuildOptionKind.Ship:
    candidate.buildType = BuildType.Ship
    candidate.shipClass = key.shipClass
  of BuildOptionKind.Ground:
    candidate.buildType = BuildType.Ground
    candidate.groundClass = key.groundClass
  of BuildOptionKind.Facility:
    candidate.buildType = BuildType.Facility
    candidate.facilityClass = key.facilityClass
  let limitErr = validateBuildIncrement(model, candidate)
  if limitErr.isSome:
    model.ui.statusMessage = limitErr.get()
    return
  let existingIdx = stagedBuildIdx(model.ui.buildModal, key)
  if existingIdx >= 0:
    model.ui.stagedBuildCommands[existingIdx].quantity += 1
  else:
    model.ui.stagedBuildCommands.add(candidate)
  model.ui.buildModal.stagedBuildCommands = model.ui.stagedBuildCommands
  if model.ui.queueModal.active:
    model.ui.queueModal.stagedBuildCommands = model.ui.stagedBuildCommands
  let c2Used = optimisticC2Used(
    model.view.commandUsed,
    model.ui.stagedBuildCommands,
  )
  let c2Excess = max(0, c2Used - model.view.commandMax)
  if model.view.commandMax > 0 and c2Excess > 0:
    model.ui.statusMessage = "Qty +1 (C2 +" & $c2Excess & " over)"
  else:
    model.ui.statusMessage = "Qty +1"

proc decSelectedQty(model: var TuiModel) =
  if model.ui.buildModal.focus != BuildModalFocus.BuildList:
    return
  let maxIdx = buildRowCountForCategory(
    model.ui.buildModal.category
  ) - 1
  if model.ui.buildModal.selectedBuildIdx < 0 or
      model.ui.buildModal.selectedBuildIdx > maxIdx:
    return
  let key = buildRowKeyAt(
    model.ui.buildModal,
    model.ui.buildModal.selectedBuildIdx
  )
  let existingIdx = stagedBuildIdx(model.ui.buildModal, key)
  if existingIdx < 0:
    return
  if model.ui.stagedBuildCommands[existingIdx].quantity > 1:
    model.ui.stagedBuildCommands[existingIdx].quantity -= 1
  else:
    model.ui.stagedBuildCommands.delete(existingIdx)
  model.ui.buildModal.stagedBuildCommands = model.ui.stagedBuildCommands
  if model.ui.queueModal.active:
    model.ui.queueModal.stagedBuildCommands = model.ui.stagedBuildCommands
  model.ui.statusMessage = "Qty -1"

proc switchBuildCategory(model: var TuiModel, reverse: bool) =
  if reverse:
    case model.ui.buildModal.category
    of BuildCategory.Ships:
      model.ui.buildModal.category = BuildCategory.Ground
    of BuildCategory.Facilities:
      model.ui.buildModal.category = BuildCategory.Ships
    of BuildCategory.Ground:
      model.ui.buildModal.category = BuildCategory.Facilities
  else:
    case model.ui.buildModal.category
    of BuildCategory.Ships:
      model.ui.buildModal.category = BuildCategory.Facilities
    of BuildCategory.Facilities:
      model.ui.buildModal.category = BuildCategory.Ground
    of BuildCategory.Ground:
      model.ui.buildModal.category = BuildCategory.Ships
  model.ui.buildModal.selectedBuildIdx = 0
  model.ui.buildModal.focus = BuildModalFocus.BuildList

proc buildModalAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle build modal proposals
  if proposal.kind != ProposalKind.pkGameAction:
    return

  case proposal.actionKind
  of ActionKind.openBuildModal:
    # Open the build modal for the currently selected colony
    if model.ui.mode == ViewMode.PlanetDetail or
        model.ui.mode == ViewMode.Planets:
      if model.ui.mode == ViewMode.Planets:
        let selectedOpt = model.selectedColony()
        if selectedOpt.isNone:
          model.ui.statusMessage = "No colony selected"
          return
        model.ui.selectedColonyId = selectedOpt.get().colonyId
      model.ui.buildModal.active = true
      model.ui.buildModal.colonyId = model.ui.selectedColonyId
      model.ui.buildModal.category = BuildCategory.Ships
      model.ui.buildModal.focus = BuildModalFocus.BuildList
      model.ui.buildModal.selectedBuildIdx = 0
      model.ui.buildModal.selectedQueueIdx = 0
      model.ui.buildModal.ppAvailable = model.view.treasury
      if model.view.techLevels.isSome:
        model.ui.buildModal.cstLevel = model.view.techLevels.get().cst
      else:
        model.ui.buildModal.cstLevel = 1
      model.ui.buildModal.stagedBuildCommands =
        model.ui.stagedBuildCommands
      # Note: availableOptions and dockSummary will be populated by the reactor
      model.ui.statusMessage = "Build modal opened"
  of ActionKind.closeBuildModal:
    model.ui.buildModal.active = false
    model.ui.statusMessage = "Build modal closed"
  of ActionKind.buildCategorySwitch:
    switchBuildCategory(model, reverse = false)
    # Note: availableOptions will be refreshed by reactor
  of ActionKind.buildCategoryPrev:
    switchBuildCategory(model, reverse = true)
    # Note: availableOptions will be refreshed by reactor
  of ActionKind.buildListUp:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      let maxIdx = max(0, buildRowCountForCategory(
        model.ui.buildModal.category
      ) - 1)
      if model.ui.buildModal.selectedBuildIdx > 0:
        model.ui.buildModal.selectedBuildIdx -= 1
      else:
        model.ui.buildModal.selectedBuildIdx = maxIdx
  of ActionKind.buildListDown:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      let maxIdx = max(0, buildRowCountForCategory(
        model.ui.buildModal.category
      ) - 1)
      if model.ui.buildModal.selectedBuildIdx < maxIdx:
        model.ui.buildModal.selectedBuildIdx += 1
      else:
        model.ui.buildModal.selectedBuildIdx = 0
  of ActionKind.buildQueueUp:
    discard
  of ActionKind.buildQueueDown:
    discard
  of ActionKind.buildListPageUp:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      let pageSize = max(1, model.ui.termHeight - 12)
      model.ui.buildModal.selectedBuildIdx = max(
        0, model.ui.buildModal.selectedBuildIdx - pageSize
      )
  of ActionKind.buildListPageDown:
    if model.ui.buildModal.focus == BuildModalFocus.BuildList:
      let maxIdx = buildRowCountForCategory(
        model.ui.buildModal.category
      ) - 1
      let pageSize = max(1, model.ui.termHeight - 12)
      model.ui.buildModal.selectedBuildIdx = min(
        maxIdx, model.ui.buildModal.selectedBuildIdx + pageSize
      )
  of ActionKind.buildFocusSwitch:
    # Queue list no longer shown in build modal
    model.ui.buildModal.focus = BuildModalFocus.BuildList
  of ActionKind.buildAddToQueue:
    # Legacy add action: treat as qty increment
    incSelectedQty(model)
  of ActionKind.buildRemoveFromQueue:
    # Legacy remove action: treat as qty decrement
    decSelectedQty(model)
  of ActionKind.buildConfirmQueue:
    model.ui.statusMessage = "Build commands staged"
    model.ui.buildModal.active = false
  of ActionKind.buildQtyInc:
    incSelectedQty(model)
  of ActionKind.buildQtyDec:
    decSelectedQty(model)
  else:
    discard

# ============================================================================
# Queue Modal Acceptor
# ============================================================================

proc queueStagedIndices(model: TuiModel): seq[int] =
  let colonyId = ColonyId(model.ui.queueModal.colonyId.uint32)
  for idx, cmd in model.ui.stagedBuildCommands:
    if cmd.colonyId == colonyId and cmd.quantity > 0:
      result.add(idx)

proc queueModalAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle queue modal proposals
  if proposal.kind != ProposalKind.pkGameAction:
    return

  case proposal.actionKind
  of ActionKind.openQueueModal:
    if model.ui.mode == ViewMode.Planets or
        model.ui.mode == ViewMode.PlanetDetail:
      if model.ui.mode == ViewMode.Planets:
        let selectedOpt = model.selectedColony()
        if selectedOpt.isNone:
          model.ui.statusMessage = "No colony selected"
          return
        let selected = selectedOpt.get()
        model.ui.queueModal.colonyId = selected.colonyId
        model.ui.queueModal.colonyName = selected.systemName
        model.ui.selectedColonyId = selected.colonyId
      else:
        let colonyId = model.ui.selectedColonyId
        if colonyId <= 0:
          model.ui.statusMessage = "No colony selected"
          return
        let infoOpt = model.colonyInfoById(colonyId)
        if infoOpt.isSome:
          model.ui.queueModal.colonyName = infoOpt.get().systemName
        model.ui.queueModal.colonyId = colonyId
      model.ui.queueModal.selectedIdx = 0
      model.ui.queueModal.stagedBuildCommands =
        model.ui.stagedBuildCommands
      model.ui.queueModal.active = true
      model.ui.statusMessage = "Queue opened"
  of ActionKind.closeQueueModal:
    model.ui.queueModal.active = false
    model.ui.statusMessage = "Queue closed"
  of ActionKind.queueListUp:
    let indices = model.queueStagedIndices()
    if indices.len == 0:
      return
    if model.ui.queueModal.selectedIdx > 0:
      model.ui.queueModal.selectedIdx -= 1
    else:
      model.ui.queueModal.selectedIdx = indices.len - 1
  of ActionKind.queueListDown:
    let indices = model.queueStagedIndices()
    if indices.len == 0:
      return
    if model.ui.queueModal.selectedIdx < indices.len - 1:
      model.ui.queueModal.selectedIdx += 1
    else:
      model.ui.queueModal.selectedIdx = 0
  of ActionKind.queueListPageUp:
    let indices = model.queueStagedIndices()
    if indices.len == 0:
      return
    let pageSize = max(1, model.ui.termHeight - 12)
    model.ui.queueModal.selectedIdx = max(
      0, model.ui.queueModal.selectedIdx - pageSize
    )
  of ActionKind.queueListPageDown:
    let indices = model.queueStagedIndices()
    if indices.len == 0:
      return
    let pageSize = max(1, model.ui.termHeight - 12)
    model.ui.queueModal.selectedIdx = min(
      indices.len - 1, model.ui.queueModal.selectedIdx + pageSize
    )
  of ActionKind.queueDelete:
    let indices = model.queueStagedIndices()
    if model.ui.queueModal.selectedIdx < 0 or
        model.ui.queueModal.selectedIdx >= indices.len:
      return
    let idx = indices[model.ui.queueModal.selectedIdx]
    if model.ui.stagedBuildCommands[idx].quantity > 1:
      model.ui.stagedBuildCommands[idx].quantity -= 1
    else:
      model.ui.stagedBuildCommands.delete(idx)
      let newCount = max(0, indices.len - 1)
      if newCount == 0:
        model.ui.queueModal.selectedIdx = 0
      else:
        model.ui.queueModal.selectedIdx = min(
          model.ui.queueModal.selectedIdx, newCount - 1
        )
    model.ui.queueModal.stagedBuildCommands =
      model.ui.stagedBuildCommands
    if model.ui.buildModal.active:
      model.ui.buildModal.stagedBuildCommands =
        model.ui.stagedBuildCommands
    model.ui.statusMessage = "Deleted"
  else:
    discard

# ============================================================================
# Fleet Detail Modal Acceptor
# ============================================================================

proc fleetDetailModalAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle fleet detail modal interactions
  case proposal.actionKind
  of ActionKind.openFleetDetailModal:
    # Open fleet detail view for selected fleet
    model.clearFleetSelection()
    if model.ui.mode == ViewMode.Fleets and model.ui.fleetViewMode == FleetViewMode.SystemView:
      # SystemView: Get fleet from cached console data
      let systems = model.ui.fleetConsoleSystems
      if systems.len > 0:
        let sysIdx = clamp(model.ui.fleetConsoleSystemIdx, 0, systems.len - 1)
        let systemId = systems[sysIdx].systemId
        # Get fleets for that system
        if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
          let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
          let fleetIdx = model.ui.fleetConsoleFleetIdx
          if fleetIdx >= 0 and fleetIdx < fleets.len:
            let fleetId = fleets[fleetIdx].fleetId
            let fleetName = fleets[fleetIdx].name
            # Transition to FleetDetail ViewMode with breadcrumb
            model.ui.mode = ViewMode.FleetDetail
            model.pushBreadcrumb("Fleet " & fleetName, ViewMode.FleetDetail, fleetId)
            # Initialize fleet detail state
            model.ui.fleetDetailModal.fleetId = fleetId
            model.ui.fleetDetailModal.subModal = FleetSubModal.None
            model.ui.fleetDetailModal.commandCategory = CommandCategory.Movement
            model.ui.fleetDetailModal.commandIdx = 0
            model.ui.fleetDetailModal.roeValue = 6  # Standard
            model.ui.fleetDetailModal.confirmPending = false
            model.ui.fleetDetailModal.confirmMessage = ""
            model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
            model.ui.fleetDetailModal.shipScroll = initScrollState()
            model.ui.fleetDetailModal.shipCount = fleets[fleetIdx].shipCount
            model.ui.fleetDetailModal.fleetPickerCandidates = @[]
            model.ui.fleetDetailModal.fleetPickerIdx = 0
            model.ui.fleetDetailModal.fleetPickerScroll = initScrollState()
            model.ui.fleetDetailModal.directSubModal = false
            discard model.updateFleetDetailScroll()
            model.ui.statusMessage = "Fleet detail opened"
          else:
            model.ui.statusMessage = "No fleet selected"
        else:
          model.ui.statusMessage = "No fleets at this system"
      else:
        model.ui.statusMessage = "No systems with fleets"
    elif model.ui.mode == ViewMode.Fleets and model.ui.fleetViewMode == FleetViewMode.ListView:
      # ListView: Get fleet from filtered list
      let fleets = model.filteredFleets()
      if model.ui.selectedIdx < fleets.len:
        let fleet = fleets[model.ui.selectedIdx]
        let fleetId = fleet.id
        # Transition to FleetDetail ViewMode with breadcrumb
        model.ui.mode = ViewMode.FleetDetail
        model.pushBreadcrumb("Fleet " & fleet.name, ViewMode.FleetDetail, fleetId)
        # Initialize fleet detail state
        model.ui.fleetDetailModal.fleetId = fleetId
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
        model.ui.fleetDetailModal.commandCategory = CommandCategory.Movement
        model.ui.fleetDetailModal.commandIdx = 0
        model.ui.fleetDetailModal.roeValue = fleet.roe  # Use actual fleet ROE
        model.ui.fleetDetailModal.confirmPending = false
        model.ui.fleetDetailModal.confirmMessage = ""
        model.ui.fleetDetailModal.pendingCommandType = FleetCommandType.Hold
        model.ui.fleetDetailModal.shipScroll = initScrollState()
        model.ui.fleetDetailModal.shipCount = fleet.shipCount
        model.ui.fleetDetailModal.fleetPickerCandidates = @[]
        model.ui.fleetDetailModal.fleetPickerIdx = 0
        model.ui.fleetDetailModal.fleetPickerScroll = initScrollState()
        model.ui.fleetDetailModal.directSubModal = false
        discard model.updateFleetDetailScroll()
        model.ui.statusMessage = "Fleet detail opened"
  of ActionKind.closeFleetDetailModal:
    # Close fleet detail view (only if no sub-modal active)
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      # Always navigate back to Fleets view
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.clearFleetSelection()
      model.resetBreadcrumbs(ViewMode.Fleets)
      model.ui.statusMessage = ""
  of ActionKind.fleetDetailNextCategory:
    # DEPRECATED: Category navigation removed, now using flat list
    discard
  of ActionKind.fleetDetailPrevCategory:
    # DEPRECATED: Category navigation removed, now using flat list
    discard
  of ActionKind.fleetDetailListUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Navigate filtered command list
      let maxIdx = max(0,
        model.ui.fleetDetailModal.commandPickerCommands.len - 1)
      if model.ui.fleetDetailModal.commandIdx > 0:
        model.ui.fleetDetailModal.commandIdx -= 1
        model.ui.fleetDetailModal.commandDigitBuffer = ""
      else:
        model.ui.fleetDetailModal.commandIdx = maxIdx
        model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue > 0:
        model.ui.fleetDetailModal.roeValue -= 1  # Up decreases value (moves toward 0)
        model.ui.fleetDetailModal.commandDigitBuffer = ""
      else:
        model.ui.fleetDetailModal.roeValue = 10  # Wrap to max
        model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      let maxIdx = max(0,
        model.ui.fleetDetailModal.ztcPickerCommands.len - 1)
      if model.ui.fleetDetailModal.ztcIdx > 0:
        model.ui.fleetDetailModal.ztcIdx -= 1
      else:
        model.ui.fleetDetailModal.ztcIdx = maxIdx
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector:
      let maxIdx = max(0,
        model.ui.fleetDetailModal.shipSelectorShipIds.len - 1)
      if model.ui.fleetDetailModal.shipSelectorIdx > 0:
        model.ui.fleetDetailModal.shipSelectorIdx -= 1
      else:
        model.ui.fleetDetailModal.shipSelectorIdx = maxIdx
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      let maxIdx = max(0,
        model.ui.fleetDetailModal.fleetPickerCandidates.len - 1)
      if model.ui.fleetDetailModal.fleetPickerIdx > 0:
        model.ui.fleetDetailModal.fleetPickerIdx -= 1
      else:
        model.ui.fleetDetailModal.fleetPickerIdx = maxIdx
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CargoParams:
      discard
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FighterParams:
      let current = max(0, parseInputQuantity(
        model.ui.fleetDetailModal.fighterQuantityInput
      ))
      if current > 0:
        model.ui.fleetDetailModal.fighterQuantityInput.clear()
        for ch in $(current - 1):
          discard model.ui.fleetDetailModal.fighterQuantityInput.appendChar(ch)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let maxIdx = max(0,
        model.ui.fleetDetailModal.systemPickerSystems.len - 1)
      if model.ui.fleetDetailModal.systemPickerIdx > 0:
        model.ui.fleetDetailModal.systemPickerIdx -= 1
      else:
        model.ui.fleetDetailModal.systemPickerIdx = maxIdx
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      discard model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = max(0,
        scroll.verticalOffset - 1)
  of ActionKind.fleetDetailListDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Navigate filtered command list
      let maxIdx =
        model.ui.fleetDetailModal.commandPickerCommands.len - 1
      if maxIdx >= 0 and
          model.ui.fleetDetailModal.commandIdx < maxIdx:
        model.ui.fleetDetailModal.commandIdx += 1
        model.ui.fleetDetailModal.commandDigitBuffer = ""
      elif maxIdx >= 0:
        model.ui.fleetDetailModal.commandIdx = 0
        model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue < 10:
        model.ui.fleetDetailModal.roeValue += 1  # Down increases value (moves toward 10)
        model.ui.fleetDetailModal.commandDigitBuffer = ""
      else:
        model.ui.fleetDetailModal.roeValue = 0  # Wrap to min
        model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      let maxZtc =
        model.ui.fleetDetailModal.ztcPickerCommands.len - 1
      if model.ui.fleetDetailModal.ztcIdx < maxZtc:
        model.ui.fleetDetailModal.ztcIdx += 1
      elif maxZtc >= 0:
        model.ui.fleetDetailModal.ztcIdx = 0
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector:
      let maxIdx =
        model.ui.fleetDetailModal.shipSelectorShipIds.len - 1
      if model.ui.fleetDetailModal.shipSelectorIdx < maxIdx:
        model.ui.fleetDetailModal.shipSelectorIdx += 1
      elif maxIdx >= 0:
        model.ui.fleetDetailModal.shipSelectorIdx = 0
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      let maxIdx = model.ui.fleetDetailModal.fleetPickerCandidates.len - 1
      if model.ui.fleetDetailModal.fleetPickerIdx < maxIdx:
        model.ui.fleetDetailModal.fleetPickerIdx += 1
      elif maxIdx >= 0:
        model.ui.fleetDetailModal.fleetPickerIdx = 0
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CargoParams:
      discard
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FighterParams:
      let current = max(0, parseInputQuantity(
        model.ui.fleetDetailModal.fighterQuantityInput
      ))
      model.ui.fleetDetailModal.fighterQuantityInput.clear()
      for ch in $(current + 1):
        discard model.ui.fleetDetailModal.fighterQuantityInput.appendChar(ch)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let maxIdx = model.ui.fleetDetailModal.systemPickerSystems.len - 1
      if model.ui.fleetDetailModal.systemPickerIdx < maxIdx:
        model.ui.fleetDetailModal.systemPickerIdx += 1
      elif maxIdx >= 0:
        model.ui.fleetDetailModal.systemPickerIdx = 0
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (_, maxOffset) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = min(maxOffset,
        scroll.verticalOffset + 1)
  of ActionKind.fleetDetailSelectCommand:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Check if there's a pending single digit - map to command code
      if model.ui.fleetDetailModal.commandDigitBuffer.len == 1:
        let digit = model.ui.fleetDetailModal.commandDigitBuffer[0]
        if digit >= '0' and digit <= '9':
          let cmdNum = parseInt("0" & $digit)
          let commands =
            model.ui.fleetDetailModal.commandPickerCommands
          let idx = commandIndexForCode(commands, cmdNum)
          if idx >= 0:
            model.ui.fleetDetailModal.commandIdx = idx
          model.ui.fleetDetailModal.commandDigitBuffer = ""
          # Fall through to select the command
      
      let commands = model.ui.fleetDetailModal.commandPickerCommands
      let idx = model.ui.fleetDetailModal.commandIdx
      
      if idx >= 0 and idx < commands.len:
        let cmdType = commands[idx]

        # Batch command for selected fleets
        if model.ui.selectedFleetIds.len > 0:
          if cmdType == FleetCommandType.JoinFleet:
            model.ui.statusMessage = "JoinFleet: use single fleet mode"
            return
          # Validate all fleets in batch meet command requirements
          for fleetId in model.ui.selectedFleetIds:
            for fleet in model.view.fleets:
              if fleet.id == fleetId:
                let err = validateFleetCommand(fleet, cmdType)
                if err.len > 0:
                  model.ui.statusMessage = $cmdType & ": " & err &
                    " (fleet " & fleet.name & ")"
                  return
          # Hold: auto-target each fleet's current location
          if int(cmdType) == CmdHold:
            for fleetId in model.ui.selectedFleetIds:
              var loc = 0
              for fleet in model.view.fleets:
                if fleet.id == fleetId:
                  loc = fleet.location
                  break
              let cmd = FleetCommand(
                fleetId: FleetId(fleetId),
                commandType: cmdType,
                targetSystem: some(SystemId(loc.uint32)),
                targetFleet: none(FleetId),
                roe: some(int32(
                  model.ui.fleetDetailModal.roeValue))
              )
              model.stageFleetCommand(cmd)
            model.ui.statusMessage = "Staged " &
              $model.ui.selectedFleetIds.len &
              " Hold command(s)"
            resetFleetDetailSubModal(model)
            model.ui.mode = ViewMode.Fleets
            model.clearFleetSelection()
            model.resetBreadcrumbs(ViewMode.Fleets)
            return
          # SeekHome: auto-target nearest drydock colony
          if int(cmdType) == CmdSeekHome:
            for fleetId in model.ui.selectedFleetIds:
              var target = none(int)
              for fleet in model.view.fleets:
                if fleet.id == fleetId:
                  target = fleet.seekHomeTarget
                  break
              if target.isNone:
                model.ui.statusMessage =
                  "SeekHome: no friendly colony found"
                return
              let cmd = FleetCommand(
                fleetId: FleetId(fleetId),
                commandType: cmdType,
                targetSystem: some(
                  SystemId(target.get().uint32)),
                targetFleet: none(FleetId),
                roe: some(int32(
                  model.ui.fleetDetailModal.roeValue))
              )
              model.stageFleetCommand(cmd)
            model.ui.statusMessage = "Staged " &
              $model.ui.selectedFleetIds.len &
              " Seek Home command(s)"
            resetFleetDetailSubModal(model)
            model.ui.mode = ViewMode.Fleets
            model.clearFleetSelection()
            model.resetBreadcrumbs(ViewMode.Fleets)
            return
          if needsTargetSystem(int(cmdType)):
            # Open SystemPicker sub-modal for batch
            model.openSystemPickerForCommand(
              cmdType,
              FleetSubModal.CommandPicker
            )
            return
          for fleetId in model.ui.selectedFleetIds:
            let cmd = FleetCommand(
              fleetId: FleetId(fleetId),
              commandType: cmdType,
              targetSystem: none(SystemId),
              targetFleet: none(FleetId),
              roe: some(int32(model.ui.fleetDetailModal.roeValue))
            )
            model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " & $model.ui.selectedFleetIds.len &
            " fleet command(s)"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.clearFleetSelection()
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        
        # Look up fleet and validate command requirements
        var currentFleet: Option[FleetInfo]
        for fleet in model.view.fleets:
          if fleet.id == model.ui.fleetDetailModal.fleetId:
            currentFleet = some(fleet)
            break
        if currentFleet.isNone:
          model.ui.statusMessage = "Fleet not found"
          resetFleetDetailSubModal(model)
          return
        let current = currentFleet.get()
        let err = validateFleetCommand(current, cmdType)
        if err.len > 0:
          model.ui.statusMessage = $cmdType & ": " & err
          return
        
        # Hold: auto-target fleet's current location
        if int(cmdType) == CmdHold:
          let cmd = FleetCommand(
            fleetId: FleetId(current.id),
            commandType: cmdType,
            targetSystem: some(
              SystemId(current.location.uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: Hold"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.clearFleetSelection()
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        # SeekHome: auto-target nearest drydock colony
        if int(cmdType) == CmdSeekHome:
          if current.seekHomeTarget.isNone:
            model.ui.statusMessage =
              "SeekHome: no friendly colony found"
            return
          let cmd = FleetCommand(
            fleetId: FleetId(current.id),
            commandType: cmdType,
            targetSystem: some(
              SystemId(current.seekHomeTarget.get().uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: Seek Home"
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.clearFleetSelection()
          model.resetBreadcrumbs(ViewMode.Fleets)
          return
        
        if cmdType == FleetCommandType.JoinFleet:
          model.ui.fleetDetailModal.fleetPickerCandidates = @[]
          for fleet in model.view.fleets:
            if fleet.id == current.id:
              continue
            if fleet.location == current.location and
                fleet.owner == current.owner:
              model.ui.fleetDetailModal.fleetPickerCandidates.add(
                FleetConsoleFleet(
                  fleetId: fleet.id,
                  name: fleet.name,
                  shipCount: fleet.shipCount,
                  attackStrength: fleet.attackStrength,
                  defenseStrength: fleet.defenseStrength,
                  troopTransports: 0,
                  etacs: 0,
                  commandLabel: fleet.commandLabel,
                  destinationLabel: fleet.destinationLabel,
                  eta: fleet.eta,
                  roe: fleet.roe,
                  status: fleet.statusLabel,
                  needsAttention: fleet.needsAttention
                )
              )
          if model.ui.fleetDetailModal.fleetPickerCandidates.len == 0:
            model.ui.statusMessage = "JoinFleet: no fleets at system"
            resetFleetDetailSubModal(model)
            return
          model.ui.fleetDetailModal.fleetPickerIdx = 0
          model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
          return

        # Check if command requires target system selection
        if needsTargetSystem(int(cmdType)):
          # Open SystemPicker sub-modal for single fleet
          model.openSystemPickerForCommand(
            cmdType,
            FleetSubModal.CommandPicker
          )
        else:
          # Stage command immediately (no target needed)
          let cmd = FleetCommand(
            fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
            commandType: cmdType,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId),
            roe: some(int32(model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged command: " & $cmdType
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.clearFleetSelection()
          model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      let ztcCommands = model.ui.fleetDetailModal.ztcPickerCommands
      let idx = model.ui.fleetDetailModal.ztcIdx
      if idx >= 0 and idx < ztcCommands.len:
        let ztcType = ztcCommands[idx]
        let sourceFleetIds = model.ztcSourceFleetIds()
        if sourceFleetIds.len == 0:
          model.ui.statusMessage = "No source fleet selected"
          return
        model.ui.fleetDetailModal.ztcType = some(ztcType)
        if sourceFleetIds.len == 1:
          model.ui.fleetDetailModal.fleetId = sourceFleetIds[0]
        case ztcType
        of ZeroTurnCommandType.Reactivate:
          let houseId = HouseId(model.view.viewingHouse.uint32)
          for sourceFleetId in sourceFleetIds:
            if sourceFleetId notin model.view.ownFleetsById:
              model.ui.statusMessage = "Fleet not found: " & $sourceFleetId
              return
            let fleet = model.view.ownFleetsById[sourceFleetId]
            let cmd = ZeroTurnCommand(
              houseId: houseId,
              commandType: ZeroTurnCommandType.Reactivate,
              colonySystem: some(SystemId(fleet.location.uint32)),
              sourceFleetId: some(FleetId(sourceFleetId)),
              targetFleetId: none(FleetId),
              shipIndices: @[],
              shipIds: @[],
              cargoType: none(CargoClass),
              cargoQuantity: none(int),
              fighterIds: @[],
              carrierShipId: none(ShipId),
              sourceCarrierShipId: none(ShipId),
              targetCarrierShipId: none(ShipId),
              newFleetId: none(FleetId),
            )
            model.stageZeroTurnCommand(
              cmd,
              "Staged Reactivate for " & $sourceFleetIds.len & " fleet(s)",
            )
        of ZeroTurnCommandType.DetachShips, ZeroTurnCommandType.TransferShips:
          if sourceFleetIds.len != 1:
            model.ui.statusMessage = "Select exactly one source fleet"
            return
          model.openShipSelectorForZtc(sourceFleetIds[0], ztcType)
        of ZeroTurnCommandType.MergeFleets:
          if sourceFleetIds.len != 1:
            model.ui.statusMessage = "Select exactly one source fleet"
            return
          if not model.buildFleetPickerCandidatesForZtc(sourceFleetIds[0]):
            return
          model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
        of ZeroTurnCommandType.LoadCargo, ZeroTurnCommandType.UnloadCargo:
          model.ui.fleetDetailModal.cargoType = CargoClass.Marines
          model.ui.fleetDetailModal.cargoQuantityInput.clear()
          model.ui.fleetDetailModal.subModal = FleetSubModal.CargoParams
        of ZeroTurnCommandType.LoadFighters, ZeroTurnCommandType.UnloadFighters:
          if sourceFleetIds.len != 1:
            model.ui.statusMessage = "Select exactly one source fleet"
            return
          model.ui.fleetDetailModal.fighterQuantityInput.clear()
          model.ui.fleetDetailModal.subModal = FleetSubModal.FighterParams
        of ZeroTurnCommandType.TransferFighters:
          if sourceFleetIds.len != 1:
            model.ui.statusMessage = "Select exactly one source fleet"
            return
          if not model.buildFleetPickerCandidatesForZtc(sourceFleetIds[0]):
            return
          model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector:
      if model.ui.fleetDetailModal.ztcType.isNone:
        model.ui.statusMessage = "No ZTC command selected"
        return
      let sourceFleetId = model.ui.fleetDetailModal.fleetId
      if sourceFleetId notin model.view.ownFleetsById:
        model.ui.statusMessage = "Source fleet not found"
        return
      let sourceFleet = model.view.ownFleetsById[sourceFleetId]
      var selectedShipIds: seq[ShipId] = @[]
      for shipId in model.ui.fleetDetailModal.shipSelectorShipIds:
        if shipId in model.ui.fleetDetailModal.shipSelectorSelected:
          selectedShipIds.add(shipId)
      if selectedShipIds.len == 0:
        let idx = model.ui.fleetDetailModal.shipSelectorIdx
        if idx >= 0 and idx < model.ui.fleetDetailModal.shipSelectorShipIds.len:
          selectedShipIds.add(
            model.ui.fleetDetailModal.shipSelectorShipIds[idx]
          )
      if selectedShipIds.len == 0:
        model.ui.statusMessage = "Select at least one ship"
        return
      var shipIndices: seq[int] = @[]
      for idx, shipId in sourceFleet.ships:
        if shipId in model.ui.fleetDetailModal.shipSelectorSelected or
            shipId in selectedShipIds:
          shipIndices.add(idx)
      if shipIndices.len == 0:
        model.ui.statusMessage = "Selected ships not available"
        return
      let houseId = HouseId(model.view.viewingHouse.uint32)
      let ztcType = model.ui.fleetDetailModal.ztcType.get()
      if ztcType == ZeroTurnCommandType.TransferShips:
        if not model.buildFleetPickerCandidatesForZtc(sourceFleetId):
          return
        model.ui.fleetDetailModal.subModal = FleetSubModal.FleetPicker
      elif ztcType == ZeroTurnCommandType.DetachShips:
        let cmd = ZeroTurnCommand(
          houseId: houseId,
          commandType: ZeroTurnCommandType.DetachShips,
          colonySystem: some(SystemId(sourceFleet.location.uint32)),
          sourceFleetId: some(FleetId(sourceFleetId)),
          targetFleetId: none(FleetId),
          shipIndices: shipIndices,
          shipIds: selectedShipIds,
          cargoType: none(CargoClass),
          cargoQuantity: none(int),
          fighterIds: @[],
          carrierShipId: none(ShipId),
          sourceCarrierShipId: none(ShipId),
          targetCarrierShipId: none(ShipId),
          newFleetId: none(FleetId),
        )
        model.stageZeroTurnCommand(cmd, "Staged Detach Ships")
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      let candidates = model.ui.fleetDetailModal.fleetPickerCandidates
      let idx = model.ui.fleetDetailModal.fleetPickerIdx
      if idx >= 0 and idx < candidates.len:
        let target = candidates[idx]
        if model.ui.fleetDetailModal.ztcType.isSome and
            model.ui.fleetDetailModal.ztcType.get() in {
              ZeroTurnCommandType.MergeFleets,
              ZeroTurnCommandType.TransferShips,
              ZeroTurnCommandType.TransferFighters
            }:
          let houseId = HouseId(model.view.viewingHouse.uint32)
          let sourceFleetId = model.ui.fleetDetailModal.fleetId
          if sourceFleetId notin model.view.ownFleetsById:
            model.ui.statusMessage = "Source fleet not found"
            return
          let sourceFleet = model.view.ownFleetsById[sourceFleetId]
          let ztcType = model.ui.fleetDetailModal.ztcType.get()
          if ztcType == ZeroTurnCommandType.TransferShips:
            var selectedShipIds: seq[ShipId] = @[]
            for shipId in model.ui.fleetDetailModal.shipSelectorShipIds:
              if shipId in model.ui.fleetDetailModal.shipSelectorSelected:
                selectedShipIds.add(shipId)
            var shipIndices: seq[int] = @[]
            for sidx, shipId in sourceFleet.ships:
              if shipId in selectedShipIds:
                shipIndices.add(sidx)
            if selectedShipIds.len == 0 or shipIndices.len == 0:
              model.ui.statusMessage = "Select at least one ship"
              return
            let cmd = ZeroTurnCommand(
              houseId: houseId,
              commandType: ZeroTurnCommandType.TransferShips,
              colonySystem: some(SystemId(sourceFleet.location.uint32)),
              sourceFleetId: some(FleetId(sourceFleetId)),
              targetFleetId: some(FleetId(target.fleetId)),
              shipIndices: shipIndices,
              shipIds: selectedShipIds,
              cargoType: none(CargoClass),
              cargoQuantity: none(int),
              fighterIds: @[],
              carrierShipId: none(ShipId),
              sourceCarrierShipId: none(ShipId),
              targetCarrierShipId: none(ShipId),
              newFleetId: none(FleetId),
            )
            model.stageZeroTurnCommand(
              cmd,
              "Staged Transfer Ships -> " & target.name
            )
          elif ztcType == ZeroTurnCommandType.MergeFleets:
            let cmd = ZeroTurnCommand(
              houseId: houseId,
              commandType: ZeroTurnCommandType.MergeFleets,
              colonySystem: some(SystemId(sourceFleet.location.uint32)),
              sourceFleetId: some(FleetId(sourceFleetId)),
              targetFleetId: some(FleetId(target.fleetId)),
              shipIndices: @[],
              shipIds: @[],
              cargoType: none(CargoClass),
              cargoQuantity: none(int),
              fighterIds: @[],
              carrierShipId: none(ShipId),
              sourceCarrierShipId: none(ShipId),
              targetCarrierShipId: none(ShipId),
              newFleetId: none(FleetId),
            )
            model.stageZeroTurnCommand(
              cmd,
              "Staged Merge Fleets -> " & target.name
            )
          elif ztcType == ZeroTurnCommandType.TransferFighters:
            model.ui.fleetDetailModal.ztcTargetFleetId = target.fleetId
            model.ui.fleetDetailModal.fighterQuantityInput.clear()
            model.ui.fleetDetailModal.subModal = FleetSubModal.FighterParams
        else:
          let fcErr = validateJoinFleetFc(
            model,
            model.ui.fleetDetailModal.fleetId,
            target.fleetId,
          )
          if fcErr.isSome:
            model.ui.statusMessage = fcErr.get()
            return
          let cmd = FleetCommand(
            fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
            commandType: FleetCommandType.JoinFleet,
            targetSystem: none(SystemId),
            targetFleet: some(FleetId(target.fleetId)),
            roe: some(int32(model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged JoinFleet: " & target.name
          resetFleetDetailSubModal(model)
          model.ui.mode = ViewMode.Fleets
          model.clearFleetSelection()
          model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CargoParams:
      if model.ui.fleetDetailModal.ztcType.isNone:
        model.ui.statusMessage = "No ZTC command selected"
        return
      let ztcType = model.ui.fleetDetailModal.ztcType.get()
      if ztcType notin {
          ZeroTurnCommandType.LoadCargo,
          ZeroTurnCommandType.UnloadCargo
      }:
        model.ui.statusMessage = "Invalid cargo command"
        return
      let sourceFleetIds = model.ztcSourceFleetIds()
      if sourceFleetIds.len == 0:
        model.ui.statusMessage = "No source fleet selected"
        return
      let houseId = HouseId(model.view.viewingHouse.uint32)
      let qty = parseInputQuantity(model.ui.fleetDetailModal.cargoQuantityInput)
      var pending: seq[ZeroTurnCommand] = @[]
      for sourceFleetId in sourceFleetIds:
        if sourceFleetId notin model.view.ownFleetsById:
          model.ui.statusMessage = "Fleet not found: " & $sourceFleetId
          return
        let sourceFleet = model.view.ownFleetsById[sourceFleetId]
        pending.add(ZeroTurnCommand(
          houseId: houseId,
          commandType: ztcType,
          colonySystem: some(SystemId(sourceFleet.location.uint32)),
          sourceFleetId: some(FleetId(sourceFleetId)),
          targetFleetId: none(FleetId),
          shipIndices: @[],
          shipIds: @[],
          cargoType: some(CargoClass.Marines),
          cargoQuantity: some(qty),
          fighterIds: @[],
          carrierShipId: none(ShipId),
          sourceCarrierShipId: none(ShipId),
          targetCarrierShipId: none(ShipId),
          newFleetId: none(FleetId),
        ))
      for cmd in pending:
        model.ui.stagedZeroTurnCommands.add(cmd)
      model.ui.modifiedSinceSubmit = true
      model.ui.statusMessage = "Staged " & $ztcType & " for " &
        $pending.len & " fleet(s)"
      model.ztcCloseToFleets()
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FighterParams:
      if model.ui.fleetDetailModal.ztcType.isNone:
        model.ui.statusMessage = "No ZTC command selected"
        return
      let sourceFleetId = model.ui.fleetDetailModal.fleetId
      if sourceFleetId notin model.view.ownFleetsById:
        model.ui.statusMessage = "Source fleet not found"
        return
      let sourceFleet = model.view.ownFleetsById[sourceFleetId]
      let ztcType = model.ui.fleetDetailModal.ztcType.get()
      let houseId = HouseId(model.view.viewingHouse.uint32)
      let qty = parseInputQuantity(model.ui.fleetDetailModal.fighterQuantityInput)
      var sourceCarrier = none(ShipId)
      for shipId in sourceFleet.ships:
        if int(shipId) notin model.view.ownShipsById:
          continue
        let ship = model.view.ownShipsById[int(shipId)]
        if ship.state == CombatState.Destroyed:
          continue
        if ship.shipClass in {ShipClass.Carrier, ShipClass.SuperCarrier}:
          sourceCarrier = some(ship.id)
          break
      if sourceCarrier.isNone:
        model.ui.statusMessage = "No operational carrier in source fleet"
        return
      if ztcType == ZeroTurnCommandType.LoadFighters:
        if int(sourceFleet.location) notin model.view.ownColoniesBySystem:
          model.ui.statusMessage = "No friendly colony at source location"
          return
        let colony = model.view.ownColoniesBySystem[int(sourceFleet.location)]
        var fighterIds = colony.fighterIds
        if qty > 0 and qty < fighterIds.len:
          fighterIds = fighterIds[0 ..< qty]
        if fighterIds.len == 0:
          model.ui.statusMessage = "No colony fighters available"
          return
        let cmd = ZeroTurnCommand(
          houseId: houseId,
          commandType: ZeroTurnCommandType.LoadFighters,
          colonySystem: some(SystemId(sourceFleet.location.uint32)),
          sourceFleetId: some(FleetId(sourceFleetId)),
          targetFleetId: none(FleetId),
          shipIndices: @[],
          shipIds: @[],
          cargoType: none(CargoClass),
          cargoQuantity: none(int),
          fighterIds: fighterIds,
          carrierShipId: sourceCarrier,
          sourceCarrierShipId: none(ShipId),
          targetCarrierShipId: none(ShipId),
          newFleetId: none(FleetId),
        )
        model.stageZeroTurnCommand(cmd, "Staged Load Fighters")
      elif ztcType == ZeroTurnCommandType.UnloadFighters:
        let carrier = model.view.ownShipsById[int(sourceCarrier.get())]
        var fighterIds = carrier.embarkedFighters
        if qty > 0 and qty < fighterIds.len:
          fighterIds = fighterIds[0 ..< qty]
        if fighterIds.len == 0:
          model.ui.statusMessage = "No embarked fighters on carrier"
          return
        let cmd = ZeroTurnCommand(
          houseId: houseId,
          commandType: ZeroTurnCommandType.UnloadFighters,
          colonySystem: some(SystemId(sourceFleet.location.uint32)),
          sourceFleetId: some(FleetId(sourceFleetId)),
          targetFleetId: none(FleetId),
          shipIndices: @[],
          shipIds: @[],
          cargoType: none(CargoClass),
          cargoQuantity: none(int),
          fighterIds: fighterIds,
          carrierShipId: sourceCarrier,
          sourceCarrierShipId: none(ShipId),
          targetCarrierShipId: none(ShipId),
          newFleetId: none(FleetId),
        )
        model.stageZeroTurnCommand(cmd, "Staged Unload Fighters")
      elif ztcType == ZeroTurnCommandType.TransferFighters:
        if model.ui.fleetDetailModal.ztcTargetFleetId notin
            model.view.ownFleetsById:
          model.ui.statusMessage = "Target fleet not selected"
          return
        let targetFleet = model.view.ownFleetsById[
          model.ui.fleetDetailModal.ztcTargetFleetId]
        var targetCarrier = none(ShipId)
        for shipId in targetFleet.ships:
          if int(shipId) notin model.view.ownShipsById:
            continue
          let ship = model.view.ownShipsById[int(shipId)]
          if ship.state == CombatState.Destroyed:
            continue
          if ship.shipClass in {ShipClass.Carrier, ShipClass.SuperCarrier}:
            targetCarrier = some(ship.id)
            break
        if targetCarrier.isNone:
          model.ui.statusMessage = "No operational carrier in target fleet"
          return
        let sourceCarrierShip = model.view.ownShipsById[int(sourceCarrier.get())]
        var fighterIds = sourceCarrierShip.embarkedFighters
        if qty > 0 and qty < fighterIds.len:
          fighterIds = fighterIds[0 ..< qty]
        if fighterIds.len == 0:
          model.ui.statusMessage = "No embarked fighters to transfer"
          return
        let cmd = ZeroTurnCommand(
          houseId: houseId,
          commandType: ZeroTurnCommandType.TransferFighters,
          colonySystem: some(SystemId(sourceFleet.location.uint32)),
          sourceFleetId: some(FleetId(sourceFleetId)),
          targetFleetId: some(FleetId(targetFleet.id.int)),
          shipIndices: @[],
          shipIds: @[],
          cargoType: none(CargoClass),
          cargoQuantity: none(int),
          fighterIds: fighterIds,
          carrierShipId: none(ShipId),
          sourceCarrierShipId: sourceCarrier,
          targetCarrierShipId: targetCarrier,
          newFleetId: none(FleetId),
        )
        model.stageZeroTurnCommand(cmd, "Staged Transfer Fighters")
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let systems = model.ui.fleetDetailModal.systemPickerSystems
      let idx = model.ui.fleetDetailModal.systemPickerIdx
      if idx >= 0 and idx < systems.len:
        let target = systems[idx]
        let cmdType = model.ui.fleetDetailModal.systemPickerCommandType
        # Validate target for starbase/colony-specific commands
        case cmdType
        of FleetCommandType.GuardStarbase:
          var hasStarbase = false
          for row in model.view.planetsRows:
            if row.systemId == target.systemId and row.isOwned and
                row.starbaseCount > 0:
              hasStarbase = true
              break
          if not hasStarbase:
            model.ui.statusMessage =
              "No friendly starbase in that system"
            return
        of FleetCommandType.GuardColony:
          var hasColony = false
          for row in model.view.planetsRows:
            if row.systemId == target.systemId and row.isOwned:
              hasColony = true
              break
          if not hasColony:
            model.ui.statusMessage =
              "No friendly colony in that system"
            return
        of FleetCommandType.HackStarbase:
          var hasKnownStarbase = false
          for row in model.view.intelRows:
            if row.systemId == target.systemId and
                row.starbaseCount.isSome and
                row.starbaseCount.get > 0:
              hasKnownStarbase = true
              break
          if not hasKnownStarbase:
            model.ui.statusMessage =
              "No known starbase in that system"
            return
        else:
          discard
        # Stage command for batch or single fleet
        if model.ui.selectedFleetIds.len > 0:
          for fleetId in model.ui.selectedFleetIds:
            let cmd = FleetCommand(
              fleetId: FleetId(fleetId),
              commandType: cmdType,
              targetSystem: some(
                SystemId(target.systemId.uint32)),
              targetFleet: none(FleetId),
              roe: some(int32(
                model.ui.fleetDetailModal.roeValue))
            )
            model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " &
            $model.ui.selectedFleetIds.len & " " &
            $cmdType & " to " & target.coordLabel
        else:
          let cmd = FleetCommand(
            fleetId: FleetId(
              model.ui.fleetDetailModal.fleetId),
            commandType: cmdType,
            targetSystem: some(
              SystemId(target.systemId.uint32)),
            targetFleet: none(FleetId),
            roe: some(int32(
              model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
          model.ui.statusMessage = "Staged " &
            $cmdType & " to " & target.coordLabel
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
  of ActionKind.fleetDetailOpenROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      model.ui.fleetDetailModal.subModal = FleetSubModal.ROEPicker
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailCloseROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      model.ui.fleetDetailModal.subModal = FleetSubModal.None
  of ActionKind.fleetDetailROEUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue < 10:
        model.ui.fleetDetailModal.roeValue += 1
  of ActionKind.fleetDetailROEDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.roeValue > 0:
        model.ui.fleetDetailModal.roeValue -= 1
  of ActionKind.fleetDetailSelectROE:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      model.ui.fleetDetailModal.subModal = FleetSubModal.None
      let newRoe = model.ui.fleetDetailModal.roeValue
      if model.ui.selectedFleetIds.len > 0:
        # Batch: update ROE on each fleet, preserving
        # whatever command is already staged or active.
        for fleetId in model.ui.selectedFleetIds:
          model.updateStagedROE(fleetId, newRoe)
        model.ui.statusMessage = "Staged ROE " &
          $newRoe & " for " &
          $model.ui.selectedFleetIds.len & " fleets"
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
      else:
        # Single fleet: update ROE, preserve command.
        model.updateStagedROE(
          model.ui.fleetDetailModal.fleetId, newRoe)
        model.ui.statusMessage = "Staged ROE " &
          $newRoe
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
  of ActionKind.fleetDetailOpenZTC:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      model.ui.fleetDetailModal.ztcPickerCommands =
        model.buildZtcPickerList()
      if model.ui.fleetDetailModal.ztcPickerCommands.len == 0:
        model.ui.statusMessage = "No applicable zero-turn commands"
        return
      model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
      model.ui.fleetDetailModal.ztcIdx = 0
      model.ui.fleetDetailModal.ztcDigitBuffer = ""
      model.ui.fleetDetailModal.ztcType = none(ZeroTurnCommandType)
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailSelectZTC:
    # Reserved for future use (direct ZTC selection from detail view)
    discard
  of ActionKind.fleetDetailConfirm:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ConfirmPrompt:
      # User confirmed destructive action
      let cmdType = model.ui.fleetDetailModal.pendingCommandType
      
      # Check if the confirmed command also requires a target
      if needsTargetSystem(int(cmdType)):
        # Open SystemPicker sub-modal for target selection
        model.openSystemPickerForCommand(
          cmdType,
          FleetSubModal.CommandPicker
        )
        return
      
      # Command doesn't need target, stage immediately
      if model.ui.selectedFleetIds.len > 0:
        for fleetId in model.ui.selectedFleetIds:
          let cmd = FleetCommand(
            fleetId: FleetId(fleetId),
            commandType: cmdType,
            targetSystem: none(SystemId),
            targetFleet: none(FleetId),
            roe: some(int32(model.ui.fleetDetailModal.roeValue))
          )
          model.stageFleetCommand(cmd)
        model.ui.statusMessage = "Staged " & $model.ui.selectedFleetIds.len &
          " fleet command(s)"
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
        return
      let cmd = FleetCommand(
        fleetId: FleetId(model.ui.fleetDetailModal.fleetId),
        commandType: cmdType,
        targetSystem: none(SystemId),
        targetFleet: none(FleetId),
        roe: some(int32(model.ui.fleetDetailModal.roeValue))
      )
      model.stageFleetCommand(cmd)
      model.ui.statusMessage = "Staged command: " & $cmdType
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.clearFleetSelection()
      model.resetBreadcrumbs(ViewMode.Fleets)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      # C key from main detail view - open command picker
      model.openCommandPicker()
      model.ui.fleetDetailModal.directSubModal = false
  of ActionKind.fleetDetailCancel:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.ConfirmPrompt:
      # Cancel confirmation, go back to main detail view
      resetFleetDetailSubModal(model)
      model.ui.statusMessage = "Action cancelled"
    elif model.ui.fleetDetailModal.subModal ==
        FleetSubModal.NoticePrompt:
      let returnSubModal =
        model.ui.fleetDetailModal.noticeReturnSubModal
      model.ui.fleetDetailModal.noticeMessage = ""
      model.ui.fleetDetailModal.noticeReturnSubModal =
        FleetSubModal.None
      model.ui.fleetDetailModal.subModal = returnSubModal
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via C from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel command picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via R from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel ROE picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      if model.ui.fleetDetailModal.directSubModal:
        # Opened directly via Z from fleet list — close entire modal
        resetFleetDetailSubModal(model)
        model.ui.mode = ViewMode.Fleets
        model.clearFleetSelection()
        model.resetBreadcrumbs(ViewMode.Fleets)
        model.ui.statusMessage = ""
      else:
        # Cancel ZTC picker, go back to main detail view
        model.ui.fleetDetailModal.subModal = FleetSubModal.None
    elif model.ui.fleetDetailModal.subModal in {FleetSubModal.ShipSelector,
        FleetSubModal.CargoParams, FleetSubModal.FighterParams}:
      # Cancel placeholder sub-modal, go back to ZTC picker
      model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      # Cancel system picker, go back to command picker
      model.ui.fleetDetailModal.systemPickerSystems = @[]
      model.ui.fleetDetailModal.systemPickerFilter = ""
      model.ui.fleetDetailModal.subModal = FleetSubModal.CommandPicker
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FleetPicker:
      if model.ui.fleetDetailModal.ztcType.isSome:
        # ZTC flow: back to ZTC picker.
        model.ui.fleetDetailModal.subModal = FleetSubModal.ZTCPicker
      else:
        # Fleet command flow: back to command picker.
        model.ui.fleetDetailModal.subModal = FleetSubModal.CommandPicker
    else:
      # Fallback: treat cancel as close when no sub-modal is active
      # Always navigate back to Fleets view
      resetFleetDetailSubModal(model)
      model.ui.mode = ViewMode.Fleets
      model.clearFleetSelection()
      model.resetBreadcrumbs(ViewMode.Fleets)
      model.ui.statusMessage = ""
  of ActionKind.fleetDetailPageUp:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (pageSize, _) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = max(0,
        scroll.verticalOffset - pageSize)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let pageSize = 20  # Match max visible rows
      model.ui.fleetDetailModal.systemPickerIdx = max(0,
        model.ui.fleetDetailModal.systemPickerIdx - pageSize)
  of ActionKind.fleetDetailPageDown:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.None:
      let (pageSize, maxOffset) = model.updateFleetDetailScroll()
      let scroll = model.ui.fleetDetailModal.shipScroll
      model.ui.fleetDetailModal.shipScroll.verticalOffset = min(maxOffset,
        scroll.verticalOffset + pageSize)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      let pageSize = 20  # Match max visible rows
      let maxIdx = model.ui.fleetDetailModal.systemPickerSystems.len - 1
      model.ui.fleetDetailModal.systemPickerIdx = min(maxIdx,
        model.ui.fleetDetailModal.systemPickerIdx + pageSize)
  of ActionKind.fleetDetailDigitInput:
    if model.ui.fleetDetailModal.subModal == FleetSubModal.CommandPicker:
      # Handle two-digit quick entry for command selection (00-19)
      if proposal.kind == ProposalKind.pkGameAction:
        let digit = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if digit >= '0' and digit <= '9':
          let now = epochTime()
          let buffer = model.ui.fleetDetailModal.commandDigitBuffer
          let lastTime = model.ui.fleetDetailModal.commandDigitTime
          let commands =
            model.ui.fleetDetailModal.commandPickerCommands
          
          if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
            # Second digit - combine with first to get command code
            let cmdNum = parseInt(buffer & $digit)
            let idx = commandIndexForCode(commands, cmdNum)
            if idx >= 0:
              model.ui.fleetDetailModal.commandIdx = idx
            model.ui.fleetDetailModal.commandDigitBuffer = ""
          else:
            # First digit - jump immediately and wait for second
            let cmdNum = parseInt($digit)
            let idx = commandIndexForCode(commands, cmdNum)
            if idx >= 0:
              model.ui.fleetDetailModal.commandIdx = idx
            model.ui.fleetDetailModal.commandDigitBuffer = $digit
            model.ui.fleetDetailModal.commandDigitTime = now
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ROEPicker:
      # Direct digit entry for ROE Picker (0-10) — jump only, Enter to confirm
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0: proposal.gameActionData[0] else: '\0'
        if ch >= '0' and ch <= '9':
          let digit = parseInt($ch)
          let now = epochTime()
          let buffer = model.ui.fleetDetailModal.commandDigitBuffer
          let lastTime = model.ui.fleetDetailModal.commandDigitTime
          
          if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
            # Two digits: form number like "10"
            let roeNum = parseInt(buffer & $ch)
            if roeNum >= 0 and roeNum <= 10:
              model.ui.fleetDetailModal.roeValue = roeNum
            model.ui.fleetDetailModal.commandDigitBuffer = ""
          elif digit == 1:
            # First digit is '1' - jump immediately, wait for second digit for "10"
            model.ui.fleetDetailModal.roeValue = 1
            model.ui.fleetDetailModal.commandDigitBuffer = $ch
            model.ui.fleetDetailModal.commandDigitTime = now
          else:
            # Single digit 0, 2-9: jump to that ROE value
            model.ui.fleetDetailModal.roeValue = digit
            model.ui.fleetDetailModal.commandDigitBuffer = ""
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ZTCPicker:
      # Single-digit quick entry for ZTC (1-9)
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0: proposal.gameActionData[0] else: '\0'
        if ch >= '1' and ch <= '9':
          let ztcNum = parseInt($ch) - 1  # Convert 1-9 to index 0-8
          let ztcCommands = model.ui.fleetDetailModal.ztcPickerCommands
          if ztcNum >= 0 and ztcNum < ztcCommands.len:
            model.ui.fleetDetailModal.ztcIdx = ztcNum
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.SystemPicker:
      # Letter/digit filter for SystemPicker: jump to matching coord
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if ch != '\0':
          let now = epochTime()
          let lastTime =
            model.ui.fleetDetailModal.systemPickerFilterTime
          let oldFilter =
            model.ui.fleetDetailModal.systemPickerFilter
          # Reset filter if timed out
          let filter = if oldFilter.len > 0 and
              (now - lastTime) < DigitBufferTimeout:
            oldFilter & $ch
          else:
            $ch
          model.ui.fleetDetailModal.systemPickerFilter = filter
          model.ui.fleetDetailModal.systemPickerFilterTime = now
          # Jump to first matching system by coordLabel prefix
          let systems =
            model.ui.fleetDetailModal.systemPickerSystems
          let upperFilter = filter.toUpperAscii()
          for i, sys in systems:
            if sys.coordLabel.toUpperAscii().startsWith(
                upperFilter):
              model.ui.fleetDetailModal.systemPickerIdx = i
              break
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.ShipSelector:
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if ch == 'X' or ch == 'x' or ch == ' ':
          let row = model.ui.fleetDetailModal.shipSelectorIdx
          if row >= 0 and
              row < model.ui.fleetDetailModal.shipSelectorShipIds.len:
            let shipId =
              model.ui.fleetDetailModal.shipSelectorShipIds[row]
            if shipId in model.ui.fleetDetailModal.shipSelectorSelected:
              model.ui.fleetDetailModal.shipSelectorSelected.excl(shipId)
            else:
              model.ui.fleetDetailModal.shipSelectorSelected.incl(shipId)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.CargoParams:
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if ch >= '0' and ch <= '9':
          if model.ui.fleetDetailModal.cargoQuantityInput.value() == "0":
            model.ui.fleetDetailModal.cargoQuantityInput.clear()
          discard model.ui.fleetDetailModal.cargoQuantityInput.appendChar(ch)
    elif model.ui.fleetDetailModal.subModal == FleetSubModal.FighterParams:
      if proposal.kind == ProposalKind.pkGameAction:
        let ch = if proposal.gameActionData.len > 0:
          proposal.gameActionData[0] else: '\0'
        if ch >= '0' and ch <= '9':
          if model.ui.fleetDetailModal.fighterQuantityInput.value() == "0":
            model.ui.fleetDetailModal.fighterQuantityInput.clear()
          discard model.ui.fleetDetailModal.fighterQuantityInput.appendChar(ch)
  else:
    discard

proc fleetListInputAcceptor*(model: var TuiModel, proposal: Proposal) =
  ## Handle fleet list sort and jump input
  if proposal.kind != ProposalKind.pkGameAction and
      proposal.kind != ProposalKind.pkNavigation:
    return
  case proposal.actionKind
  of ActionKind.fleetSortToggle:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      toggleSortDirection(
        model.ui.fleetListState.sortState)
  of ActionKind.fleetConsoleNextPane:
    # Right arrow: next sort column in ListView
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      advanceSortColumn(
        model.ui.fleetListState.sortState)
      model.ui.selectedIdx = 0
      model.ui.fleetsScroll.verticalOffset = 0
  of ActionKind.fleetConsolePrevPane:
    # Left arrow: prev sort column in ListView
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView:
      retreatSortColumn(
        model.ui.fleetListState.sortState)
      model.ui.selectedIdx = 0
      model.ui.fleetsScroll.verticalOffset = 0
  of ActionKind.fleetDigitJump:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.ListView and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.fleetListState.jumpBuffer
      let lastTime = model.ui.fleetListState.jumpTime
      # Build 2-char label buffer (e.g. "A" then "1" → "A1")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.fleetListState.jumpBuffer = nextBuffer
      model.ui.fleetListState.jumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let fleets = model.filteredFleets()
        let target = nextBuffer.toUpperAscii()
        var foundIdx = -1
        for idx, fleet in fleets:
          if fleet.name.toUpperAscii().startsWith(target):
            foundIdx = idx
            break
        if foundIdx >= 0:
          model.ui.selectedIdx = foundIdx
          var localScroll = model.ui.fleetsScroll
          localScroll.contentLength = fleets.len
          let maxVisibleRows = max(1, model.ui.termHeight - 10)
          localScroll.viewportLength = maxVisibleRows
          localScroll.ensureVisible(foundIdx)
          model.ui.fleetsScroll = localScroll
        model.ui.fleetListState.jumpBuffer = ""
  of ActionKind.intelDigitJump:
    if model.ui.mode == ViewMode.IntelDb and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.intelJumpBuffer
      let lastTime = model.ui.intelJumpTime
      # Build 2-char sector label buffer (e.g. "A" then "0" -> "A0")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.intelJumpBuffer = nextBuffer
      model.ui.intelJumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let upperFilter = nextBuffer.toUpperAscii()
        for idx, row in model.view.intelRows:
          if row.sectorLabel.toUpperAscii().startsWith(upperFilter):
            model.ui.selectedIdx = idx
            model.syncIntelListScroll()
            break
        model.ui.intelJumpBuffer = ""
  of ActionKind.colonyDigitJump:
    if model.ui.mode == ViewMode.Planets and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.planetsJumpBuffer
      let lastTime = model.ui.planetsJumpTime
      # Build 2-char sector label buffer (e.g. "A" then "0" -> "A0")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.planetsJumpBuffer = nextBuffer
      model.ui.planetsJumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let upperFilter = nextBuffer.toUpperAscii()
        var foundIdx = -1
        for idx, row in model.view.planetsRows:
          if row.sectorLabel.toUpperAscii().startsWith(upperFilter):
            foundIdx = idx
            break
        if foundIdx >= 0:
          model.ui.selectedIdx = foundIdx
          var localScroll = model.ui.planetsScroll
          localScroll.contentLength = model.view.planetsRows.len
          let maxVisibleRows = max(1, model.ui.termHeight - 10)
          localScroll.viewportLength = maxVisibleRows
          localScroll.ensureVisible(foundIdx)
          model.ui.planetsScroll = localScroll
        model.ui.planetsJumpBuffer = ""
  of ActionKind.fleetConsoleSystemJump:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.fleetConsoleSystemJumpBuffer
      let lastTime = model.ui.fleetConsoleSystemJumpTime
      # Build 2-char coordinate label buffer (e.g. "D" then "1" -> "D1")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.fleetConsoleSystemJumpBuffer = nextBuffer
      model.ui.fleetConsoleSystemJumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let target = nextBuffer.toUpperAscii()
        var foundIdx = -1
        for idx, sys in model.ui.fleetConsoleSystems:
          if sys.sectorLabel.toUpperAscii().startsWith(target):
            foundIdx = idx
            break
        if foundIdx >= 0:
          model.ui.fleetConsoleSystemIdx = foundIdx
          let viewportHeight = model.fleetConsoleViewportRows()
          model.ui.fleetConsoleSystemScroll.contentLength =
            model.ui.fleetConsoleSystems.len
          model.ui.fleetConsoleSystemScroll.viewportLength = viewportHeight
          model.ui.fleetConsoleSystemScroll.ensureVisible(foundIdx)
        model.ui.fleetConsoleSystemJumpBuffer = ""
  of ActionKind.fleetConsoleFleetJump:
    if model.ui.mode == ViewMode.Fleets and
        model.ui.fleetViewMode == FleetViewMode.SystemView and
        proposal.gameActionData.len > 0:
      let ch = proposal.gameActionData[0]
      let now = epochTime()
      let buffer = model.ui.fleetConsoleFleetJumpBuffer
      let lastTime = model.ui.fleetConsoleFleetJumpTime
      # Build 2-char fleet label buffer (e.g. "A" then "1" -> "A1")
      var nextBuffer = ""
      if buffer.len == 1 and (now - lastTime) < DigitBufferTimeout:
        nextBuffer = buffer & $ch
      else:
        nextBuffer = $ch
      model.ui.fleetConsoleFleetJumpBuffer = nextBuffer
      model.ui.fleetConsoleFleetJumpTime = now
      # Only search when we have a full 2-char label
      if nextBuffer.len >= 2:
        let target = nextBuffer.toUpperAscii()
        if model.ui.fleetConsoleSystems.len > 0:
          let sysIdx = clamp(
            model.ui.fleetConsoleSystemIdx,
            0,
            model.ui.fleetConsoleSystems.len - 1
          )
          let systemId = model.ui.fleetConsoleSystems[sysIdx].systemId
          if model.ui.fleetConsoleFleetsBySystem.hasKey(systemId):
            let fleets = model.ui.fleetConsoleFleetsBySystem[systemId]
            var foundIdx = -1
            for idx, fleet in fleets:
              if fleet.name.toUpperAscii().startsWith(target):
                foundIdx = idx
                break
            if foundIdx >= 0:
              model.ui.fleetConsoleFleetIdx = foundIdx
              let viewportHeight = model.fleetConsoleViewportRows()
              model.ui.fleetConsoleFleetScroll.contentLength = fleets.len
              model.ui.fleetConsoleFleetScroll.viewportLength = viewportHeight
              model.ui.fleetConsoleFleetScroll.ensureVisible(foundIdx)
        model.ui.fleetConsoleFleetJumpBuffer = ""
  else:
    discard

# ============================================================================
# Create All Acceptors
# ============================================================================

proc createAcceptors*(): seq[AcceptorProc[TuiModel]] =
  ## Create the standard set of acceptors for the TUI
  @[
    navigationAcceptor, selectionAcceptor, viewportAcceptor, gameActionAcceptor,
    buildModalAcceptor, queueModalAcceptor, fleetDetailModalAcceptor,
    fleetListInputAcceptor, quitAcceptor, errorAcceptor,
  ]
