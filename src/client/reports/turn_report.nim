## Client-side turn report formatter for EC4X
##
## Converts structured TurnResult data into human-readable reports
## from a specific player's perspective.
##
## This is CLIENT-SIDE ONLY to minimize network traffic:
## - Engine sends TurnResult with events/combatReports (structured data)
## - Client receives TurnResult and generates formatted report locally
## - Different clients can format differently (CLI, web, mobile)
## - Players only see what's relevant to them

import std/[tables, strformat, strutils, sequtils, options, algorithm]
import ../../engine/[gamestate, resolve]
import ../../engine/diplomacy/types as dip_types
import ../../common/[hex, system, types/core]

type
  ReportSection* = object
    title*: string
    priority*: ReportPriority
    lines*: seq[string]

  ReportPriority* {.pure.} = enum
    Critical,    # ⚠ Immediate attention needed
    Important,   # ! Notable events
    Info,        # • General information
    Detail       # - Minor details

  TurnReport* = object
    ## Complete turn report for a player
    turn*: int
    houseId*: HouseId
    sections*: seq[ReportSection]

proc prioritySymbol(p: ReportPriority): string =
  ## Get display symbol for priority level
  case p
  of ReportPriority.Critical: "⚠"
  of ReportPriority.Important: "!"
  of ReportPriority.Info: "•"
  of ReportPriority.Detail: "-"

proc formatHexCoord(coords: Hex): string =
  ## Format hex coordinates for display
  ## Example: (q:2, r:-1)
  &"(q:{coords.q}, r:{coords.r})"

proc getSystemName(state: GameState, systemId: SystemId): string =
  ## Get system name with hex coordinates
  ## Example: "System 42 (q:2, r:-1)"
  if state.starMap.systems.hasKey(systemId):
    let sys = state.starMap.systems[systemId]
    &"System {systemId} {formatHexCoord(sys.coords)}"
  else:
    &"System {systemId}"

proc formatCombatReport(state: GameState, report: CombatReport, perspective: HouseId): ReportSection =
  ## Format a combat report with detailed battle summary
  result = ReportSection(
    title: "Battle Report",
    priority: ReportPriority.Critical,
    lines: @[]
  )

  let location = getSystemName(state, report.systemId)
  result.lines.add(&"Location: {location}")

  # Determine if player was involved and on which side
  let playerAttacking = perspective in report.attackers
  let playerDefending = perspective in report.defenders
  let playerInvolved = playerAttacking or playerDefending

  # Format participants
  var attackerNames: seq[string] = @[]
  for attacker in report.attackers:
    if state.houses.hasKey(attacker):
      attackerNames.add(state.houses[attacker].name)
    else:
      attackerNames.add($attacker)

  var defenderNames: seq[string] = @[]
  for defender in report.defenders:
    if state.houses.hasKey(defender):
      defenderNames.add(state.houses[defender].name)
    else:
      defenderNames.add($defender)

  result.lines.add(&"Attackers: {attackerNames.join(\", \")}")
  result.lines.add(&"Defenders: {defenderNames.join(\", \")}")

  # Battle outcome
  if report.victor.isSome:
    let victorId = report.victor.get()
    let victorName = if state.houses.hasKey(victorId): state.houses[victorId].name else: $victorId
    let victorSide = if victorId in report.attackers: "Attackers" else: "Defenders"
    result.lines.add(&"Victor: {victorName} ({victorSide})")

    # Emphasize player victory/defeat
    if playerInvolved:
      if victorId == perspective:
        result.lines.add("★ VICTORY ★")
      else:
        result.lines.add("✗ DEFEAT ✗")
  else:
    result.lines.add("Victor: None (Mutual annihilation)")
    if playerInvolved:
      result.lines.add("✗ Fleet destroyed in mutual annihilation ✗")

  # Casualties
  result.lines.add(&"Attacker losses: {report.attackerLosses} squadrons")
  result.lines.add(&"Defender losses: {report.defenderLosses} squadrons")

  # Total ships involved (rough estimate based on losses)
  let totalCasualties = report.attackerLosses + report.defenderLosses
  if totalCasualties > 0:
    result.lines.add(&"Total squadrons destroyed: {totalCasualties}")

proc generateCombatSection(state: GameState, combatReports: seq[CombatReport], perspective: HouseId): seq[ReportSection] =
  ## Generate all combat-related report sections
  result = @[]

  for report in combatReports:
    # Only show battles player was involved in or knows about
    let playerInvolved = perspective in report.attackers or perspective in report.defenders

    # TODO: Add intelligence detection - player may know about other battles through spy scouts
    if playerInvolved:
      result.add(formatCombatReport(state, report, perspective))

proc generateEconomicSection(oldState: GameState, newState: GameState, perspective: HouseId): ReportSection =
  ## Generate economic summary section
  result = ReportSection(
    title: "Economic Report",
    priority: ReportPriority.Info,
    lines: @[]
  )

  if not newState.houses.hasKey(perspective):
    result.lines.add("House data unavailable")
    return

  let oldHouse = if oldState.houses.hasKey(perspective): oldState.houses[perspective] else: newState.houses[perspective]
  let newHouse = newState.houses[perspective]

  # Treasury change
  let oldTreasury = oldHouse.treasury
  let newTreasury = newHouse.treasury
  let treasuryChange = newTreasury - oldTreasury
  let changeSymbol = if treasuryChange >= 0: "+" else: ""
  result.lines.add(&"Treasury: {newTreasury} IU ({changeSymbol}{treasuryChange} IU)")

  # Calculate income from colonies
  var totalProduction = 0
  var colonyCount = 0
  for colony in newState.colonies.values:
    if colony.owner == perspective:
      totalProduction += colony.production
      colonyCount += 1

  if colonyCount > 0:
    result.lines.add(&"Production: {totalProduction} PP from {colonyCount} colonies")

  # Fleet maintenance estimate
  let fleetCount = newState.fleets.values.toSeq.filterIt(it.owner == perspective).len
  if fleetCount > 0:
    let maintenanceCost = fleetCount * 2  # Rough estimate: 2 PP per fleet per turn
    result.lines.add(&"Fleet maintenance: ~{maintenanceCost} PP ({fleetCount} fleets)")

proc generateMilitarySection(oldState: GameState, newState: GameState, perspective: HouseId): ReportSection =
  ## Generate military status section
  result = ReportSection(
    title: "Military Status",
    priority: ReportPriority.Info,
    lines: @[]
  )

  # Fleet count and composition
  let playerFleets = newState.fleets.values.toSeq.filterIt(it.owner == perspective)
  result.lines.add(&"Fleets: {playerFleets.len} active")

  # Count squadrons
  var totalSquadrons = 0
  for fleet in playerFleets:
    for squadron in fleet.squadrons:
      totalSquadrons += 1

  if totalSquadrons > 0:
    result.lines.add(&"Total squadrons: {totalSquadrons}")

  # Check for construction projects
  var shipsUnderConstruction = 0
  for colony in newState.colonies.values:
    if colony.owner == perspective and colony.underConstruction.isSome:
      shipsUnderConstruction += 1

  if shipsUnderConstruction > 0:
    result.lines.add(&"Construction projects: {shipsUnderConstruction}")

proc generateColonySection(oldState: GameState, newState: GameState, perspective: HouseId): ReportSection =
  ## Generate colony status section
  result = ReportSection(
    title: "Colony Status",
    priority: ReportPriority.Info,
    lines: @[]
  )

  let playerColonies = newState.colonies.values.toSeq.filterIt(it.owner == perspective)
  result.lines.add(&"Colonies: {playerColonies.len}")

  # Show summary statistics
  var totalPopulation = 0
  var totalProduction = 0
  for colony in playerColonies:
    totalPopulation += colony.population
    totalProduction += colony.production

  result.lines.add(&"Total population: {totalPopulation}M")
  result.lines.add(&"Total production: {totalProduction} PP")

  # Highlight colonies with issues
  for colony in playerColonies:
    if colony.blockaded:
      let systemName = getSystemName(newState, colony.systemId)
      result.lines.add(&"⚠ {systemName} is BLOCKADED")
      result.priority = ReportPriority.Important

proc generateTechnologySection(oldState: GameState, newState: GameState, perspective: HouseId): ReportSection =
  ## Generate technology progress section
  result = ReportSection(
    title: "Technology",
    priority: ReportPriority.Info,
    lines: @[]
  )

  if not newState.houses.hasKey(perspective):
    result.lines.add("House data unavailable")
    return

  let oldHouse = if oldState.houses.hasKey(perspective): oldState.houses[perspective] else: newState.houses[perspective]
  let newHouse = newState.houses[perspective]

  let oldLevels = oldHouse.techTree.levels
  let newLevels = newHouse.techTree.levels

  # Show current tech levels
  result.lines.add(&"Energy: {newLevels.economicLevel}, Science: {newLevels.scienceLevel}")
  result.lines.add(&"Construction: {newLevels.constructionTech}, Weapons: {newLevels.weaponsTech}")
  result.lines.add(&"Terraforming: {newLevels.terraformingTech}, ELI: {newLevels.electronicIntelligence}, CIC: {newLevels.counterIntelligence}")

  # Highlight tech advances
  if newLevels.economicLevel > oldLevels.economicLevel:
    result.lines.add(&"! Energy advanced to level {newLevels.economicLevel}")
    result.priority = ReportPriority.Important
  if newLevels.scienceLevel > oldLevels.scienceLevel:
    result.lines.add(&"! Science advanced to level {newLevels.scienceLevel}")
    result.priority = ReportPriority.Important
  if newLevels.constructionTech > oldLevels.constructionTech:
    result.lines.add(&"! Construction advanced to level {newLevels.constructionTech}")
    result.priority = ReportPriority.Important
  if newLevels.weaponsTech > oldLevels.weaponsTech:
    result.lines.add(&"! Weapons advanced to level {newLevels.weaponsTech}")
    result.priority = ReportPriority.Important
  if newLevels.terraformingTech > oldLevels.terraformingTech:
    result.lines.add(&"! Terraforming advanced to level {newLevels.terraformingTech}")
    result.priority = ReportPriority.Important
  if newLevels.electronicIntelligence > oldLevels.electronicIntelligence:
    result.lines.add(&"! ELI advanced to level {newLevels.electronicIntelligence}")
    result.priority = ReportPriority.Important
  if newLevels.counterIntelligence > oldLevels.counterIntelligence:
    result.lines.add(&"! CIC advanced to level {newLevels.counterIntelligence}")
    result.priority = ReportPriority.Important

proc generateDiplomaticSection(oldState: GameState, newState: GameState, perspective: HouseId): ReportSection =
  ## Generate diplomatic status section
  result = ReportSection(
    title: "Diplomatic Relations",
    priority: ReportPriority.Info,
    lines: @[]
  )

  if not newState.houses.hasKey(perspective):
    result.lines.add("House data unavailable")
    return

  let house = newState.houses[perspective]

  # Show relations with each house
  for otherId, otherHouse in newState.houses:
    if otherId != perspective and not otherHouse.eliminated:
      let relation = dip_types.getDiplomaticState(house.diplomaticRelations, otherId)
      let statusStr = case relation
        of DiplomaticState.Enemy: "WAR"
        of DiplomaticState.Hostile: "Hostile (Deep Space Combat)"
        of DiplomaticState.Neutral: "Neutral"

      let priorityMark = if relation in {DiplomaticState.Enemy, DiplomaticState.Hostile}: "⚠ " else: ""
      result.lines.add(&"{priorityMark}{otherHouse.name}: {statusStr}")

      if relation in {DiplomaticState.Enemy, DiplomaticState.Hostile}:
        result.priority = ReportPriority.Important

proc generateAlertsSection(events: seq[GameEvent], newState: GameState, perspective: HouseId): ReportSection =
  ## Generate alerts and notifications section
  result = ReportSection(
    title: "Alerts & Notifications",
    priority: ReportPriority.Info,
    lines: @[]
  )

  # Filter events relevant to this player
  let relevantEvents = events.filterIt(it.houseId == perspective)

  if relevantEvents.len == 0:
    result.lines.add("No new alerts")
    return

  for event in relevantEvents:
    let location = if event.systemId.isSome: " at " & getSystemName(newState, event.systemId.get()) else: ""

    case event.eventType
    of GameEventType.ColonyEstablished:
      result.lines.add(&"• Colony established{location}")
    of GameEventType.SystemCaptured:
      result.lines.add(&"! System captured{location}")
      result.priority = ReportPriority.Important
    of GameEventType.TechAdvance:
      result.lines.add(&"! Technology advanced: {event.description}")
      result.priority = ReportPriority.Important
    of GameEventType.FleetDestroyed:
      result.lines.add(&"⚠ Fleet destroyed{location}")
      result.priority = ReportPriority.Critical
    of GameEventType.HouseEliminated:
      result.lines.add(&"! {event.description}")
      result.priority = ReportPriority.Important
    else:
      result.lines.add(&"• {event.description}")

proc generateTurnReport*(oldState: GameState, turnResult: TurnResult, perspective: HouseId): TurnReport =
  ## Generate a complete turn report from a player's perspective
  ##
  ## This is the main entry point for client-side report generation.
  ## Takes the previous game state and the turn result, returns a formatted report.

  let newState = turnResult.newState

  result = TurnReport(
    turn: newState.turn,
    
    
    houseId: perspective,
    sections: @[]
  )

  # Combat reports (highest priority - shown first)
  let combatSections = generateCombatSection(newState, turnResult.combatReports, perspective)
  result.sections.add(combatSections)

  # Alerts and notifications
  result.sections.add(generateAlertsSection(turnResult.events, newState, perspective))

  # Economic summary
  result.sections.add(generateEconomicSection(oldState, newState, perspective))

  # Military status
  result.sections.add(generateMilitarySection(oldState, newState, perspective))

  # Colony status
  result.sections.add(generateColonySection(oldState, newState, perspective))

  # Technology progress
  result.sections.add(generateTechnologySection(oldState, newState, perspective))

  # Diplomatic relations
  result.sections.add(generateDiplomaticSection(oldState, newState, perspective))

  # Sort sections by priority (Critical first, then Important, Info, Detail)
  result.sections.sort(proc(a, b: ReportSection): int =
    cmp(ord(a.priority), ord(b.priority))
  )

proc formatReport*(report: TurnReport): string =
  ## Format a turn report as a string for display
  ## This can be customized per client (CLI, web, mobile)

  result = ""
  result.add(repeat("=", 70) & "\n")
  result.add(&"Turn {report.turn} Report \n")
  result.add(repeat("=", 70) & "\n\n")

  for section in report.sections:
    # Skip sections with no content
    if section.lines.len == 0:
      continue

    # Section header with priority symbol
    let symbol = prioritySymbol(section.priority)
    result.add(&"{symbol} {section.title}\n")
    result.add(repeat("-", 70) & "\n")

    # Section content
    for line in section.lines:
      result.add(&"  {line}\n")

    result.add("\n")

  result.add(repeat("=", 70) & "\n")
