## Domestikos Fleet Management - ZeroTurnCommand Operations
##
## Strategic fleet reorganization using immediate-execution commands:
## - MergeFleets: Consolidate small fleets into larger combined forces
## - DetachShips: Split fleets for exploration, specialization, or efficiency
## - TransferShips: Optimize fleet compositions by moving ships between fleets
##
## Philosophy:
## - Act 1 (Land Grab): Split fleets to maximize exploration coverage
## - Act 2+ (Combat): Merge fleets to concentrate combat power
## - All Acts: Optimize compositions for specific roles (invasion, defense, raid)
##
## Integration:
## - Called by Domestikos after generating Move orders
## - Returns ZeroTurnCommands for fleets at friendly colonies
## - Executes immediately when fleets are co-located

import std/[tables, options, strformat]
import ../../../common/types/core
import ../../../engine/[gamestate, fog_of_war, fleet, logger]
import ../controller_types
import ../../../engine/commands/zero_turn_commands
import ../../common/types as ai_types
import ../config
import ./fleet_analysis  # For FleetAnalysis type

## =============================================================================
## HELPER FUNCTIONS
## =============================================================================

proc isSystemFriendlyColony*(filtered: FilteredGameState, systemId: SystemId, houseId: HouseId): bool =
  ## Check if a system has a friendly colony
  for colony in filtered.ownColonies:
    if colony.systemId == systemId:
      return true
  return false

## =============================================================================
## FLEET MERGER - Consolidate forces at staging areas
## =============================================================================

type
  MergerGroup* = object
    ## Group of fleets that should be merged together
    targetFleetId*: FleetId      # Primary fleet (largest/strongest)
    sourceFleetIds*: seq[FleetId] # Fleets to merge into target
    location*: SystemId           # Colony where merger happens
    totalShips*: int              # Combined ship count
    reason*: string               # Why these fleets should merge

proc identifyMergerGroups*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  houseId: HouseId
): seq[MergerGroup] =
  ## Identify groups of fleets at the same colony that should merge
  ##
  ## Merge criteria:
  ## - Fleets at same friendly colony
  ## - Same general type (scouts together, combat together)
  ## - Combined fleet size reasonable (< 15 ships for performance)
  ## - At least 2 fleets to merge (obviously)

  result = @[]

  # Group fleets by location
  var fleetsByLocation = initTable[SystemId, seq[FleetAnalysis]]()
  for analysis in analyses:
    if analysis.utilization == FleetUtilization.Idle or
       analysis.utilization == FleetUtilization.UnderUtilized:
      if not fleetsByLocation.hasKey(analysis.location):
        fleetsByLocation[analysis.location] = @[]
      fleetsByLocation[analysis.location].add(analysis)

  # For each location, identify merge candidates
  for systemId, fleetsAtLocation in fleetsByLocation:
    # Need at least 2 fleets to merge
    if fleetsAtLocation.len < 2:
      continue

    # Check if this is a friendly colony
    var isFriendlyColony = false
    for colony in filtered.ownColonies:
      if colony.systemId == systemId:
        isFriendlyColony = true
        break

    if not isFriendlyColony:
      continue

    # Separate into scout fleets and combat fleets
    # CRITICAL: NEVER merge ETAC fleets - they need stable fleet IDs for standing orders
    var scoutFleets: seq[FleetAnalysis] = @[]
    var combatFleets: seq[FleetAnalysis] = @[]

    for fleetAnalysis in fleetsAtLocation:
      # Skip ETACs - they're managed by ETAC manager and need stable fleet IDs
      # Check both the analysis flag AND the actual fleet data
      if fleetAnalysis.hasETACs:
        continue

      # Also check the actual fleet to be absolutely sure
      var actualFleet: Fleet
      var foundFleet = false
      for fleet in filtered.ownFleets:
        if fleet.id == fleetAnalysis.fleetId:
          actualFleet = fleet
          foundFleet = true
          break

      if foundFleet:
        # Check if any squadrons are Expansion type (ETACs)
        var hasExpansionSquadrons = false
        for squadron in actualFleet.squadrons:
          if squadron.squadronType == SquadronType.Expansion:
            hasExpansionSquadrons = true
            break
        if hasExpansionSquadrons:
          # Has expansion squadrons - skip to avoid merging ETACs
          continue

      if fleetAnalysis.hasScouts and not fleetAnalysis.hasCombatShips:
        scoutFleets.add(fleetAnalysis)
      elif fleetAnalysis.hasCombatShips:
        combatFleets.add(fleetAnalysis)

    # Create merger groups for scouts (if 2+ scout fleets)
    # Optimal spy mission size: 3-6 scouts for mesh network bonus
    # Mesh network: 2-3 scouts = +1 ELI, 4-5 scouts = +2 ELI, 6+ scouts = +3 ELI (max)
    if scoutFleets.len >= 2:
      # Find largest scout fleet as target
      var target = scoutFleets[0]
      for fleet in scoutFleets:
        if fleet.shipCount > target.shipCount:
          target = fleet

      var sources: seq[FleetId] = @[]
      var totalShips = 0
      for fleet in scoutFleets:
        totalShips += fleet.shipCount
        if fleet.fleetId != target.fleetId:
          sources.add(fleet.fleetId)

      # Cap at 6 scouts for optimal mesh network bonus (+3 ELI maximum)
      # No benefit to having more than 6 scouts on spy missions
      if sources.len > 0 and totalShips <= 6:
        result.add(MergerGroup(
          targetFleetId: target.fleetId,
          sourceFleetIds: sources,
          location: systemId,
          totalShips: totalShips,
          reason: &"Consolidate {scoutFleets.len} scout fleets (mesh network optimal at 3-6)"
        ))

    # Create merger groups for combat fleets (if 3+ small combat fleets)
    if combatFleets.len >= 3:
      # Only merge if they're all small (avoid merging large battle groups)
      var allSmall = true
      for fleet in combatFleets:
        if fleet.shipCount > 4:
          allSmall = false
          break

      if allSmall:
        # Find strongest combat fleet as target
        var target = combatFleets[0]
        for fleet in combatFleets:
          if fleet.shipCount > target.shipCount:
            target = fleet

        var sources: seq[FleetId] = @[]
        var totalShips = 0
        for fleet in combatFleets:
          totalShips += fleet.shipCount
          if fleet.fleetId != target.fleetId:
            sources.add(fleet.fleetId)

        if sources.len >= 2 and totalShips <= 15:
          result.add(MergerGroup(
            targetFleetId: target.fleetId,
            sourceFleetIds: sources,
            location: systemId,
            totalShips: totalShips,
            reason: &"Merge {combatFleets.len} small combat fleets"
          ))

proc generateMergeCommands*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  houseId: HouseId
): seq[ZeroTurnCommand] =
  ## Generate ZeroTurnCommand.MergeFleets for fleet consolidation
  ##
  ## This is the actual implementation that merges fleets into single units
  ## (vs the old implementation that just moved them to same location)

  result = @[]

  let mergerGroups = identifyMergerGroups(filtered, analyses, houseId)

  for group in mergerGroups:
    logInfo(LogCategory.lcAI,
            &"{houseId} Domestikos: {group.reason} at {group.location} " &
            &"({group.totalShips} ships total)")

    # Generate merge command for each source fleet
    for sourceFleetId in group.sourceFleetIds:
      result.add(ZeroTurnCommand(
        houseId: houseId,
        commandType: ZeroTurnCommandType.MergeFleets,
        sourceFleetId: some(sourceFleetId),
        targetFleetId: some(group.targetFleetId),
        colonySystem: some(group.location)
      ))

      logDebug(LogCategory.lcAI,
               &"{houseId} Merging fleet {sourceFleetId} into {group.targetFleetId}")

## =============================================================================
## FLEET SPLITTING - Detach ships for exploration/specialization
## =============================================================================

type
  DetachmentPlan* = object
    ## Plan to detach ships from a fleet to create specialized units
    sourceFleetId*: FleetId
    shipIndices*: seq[int]       # Which ships to detach
    location*: SystemId           # Colony where detachment happens
    newFleetRole*: string         # Purpose of new fleet (e.g., "Scout patrol")
    reason*: string               # Why detaching

proc identifyDetachmentOpportunities*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  currentAct: ai_types.GameAct,
  houseId: HouseId
): seq[DetachmentPlan] =
  ## Identify fleets that should be split for better efficiency
  ##
  ## Act 1 strategy: Split large fleets to maximize exploration coverage
  ## Act 2+ strategy: Detach scouts from combat fleets for reconnaissance

  result = @[]

  # Act 1: Aggressive splitting for exploration
  if currentAct == ai_types.GameAct.Act1_LandGrab:
    for analysis in analyses:
      # ETAC FLEETS: Skip entirely - Eparch manages all ETAC operations
      # Domestikos should not modify fleets containing ETACs
      if analysis.hasETACs:
        continue

      # Split fleets with 4+ ships (over-utilized for exploration)
      if analysis.shipCount >= 4 and
         (analysis.utilization == FleetUtilization.Idle or
          analysis.utilization == FleetUtilization.OverUtilized):

        # Check if at friendly colony
        if isSystemFriendlyColony(filtered, analysis.location, houseId):

            # Detach half the ships for secondary exploration
            let detachCount = analysis.shipCount div 2
            if detachCount >= 1:
              var indices: seq[int] = @[]
              for i in 0..<detachCount:
                indices.add(i)

              result.add(DetachmentPlan(
                sourceFleetId: analysis.fleetId,
                shipIndices: indices,
                location: analysis.location,
                newFleetRole: "Exploration patrol",
                reason: &"Split {analysis.shipCount}-ship fleet for Act 1 coverage"
              ))

  # Act 2+: Detach scouts from combat fleets for intel ops
  else:
    for analysis in analyses:
      # ETAC FLEETS: Skip entirely - Eparch manages all ETAC operations
      # Domestikos should not modify fleets containing ETACs
      if analysis.hasETACs:
        continue

      # Combat fleets with scouts should detach them for recon
      if analysis.hasCombatShips and analysis.hasScouts and analysis.shipCount >= 3:
        # Check if at friendly colony
        if isSystemFriendlyColony(filtered, analysis.location, houseId):

            # Note: We'd need to identify which ships are scouts
            # For now, detach first ship if fleet is mixed composition
            # TODO: Add ship-type detection logic

            result.add(DetachmentPlan(
              sourceFleetId: analysis.fleetId,
              shipIndices: @[0],  # Detach first ship (likely scout)
              location: analysis.location,
              newFleetRole: "Scout reconnaissance",
              reason: "Separate scouts from combat fleet for intel ops"
            ))

proc generateDetachCommands*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  currentAct: ai_types.GameAct,
  houseId: HouseId
): seq[ZeroTurnCommand] =
  ## Generate ZeroTurnCommand.DetachShips for fleet splitting
  ##
  ## Creates new specialized fleets from existing over-sized fleets

  result = @[]

  let detachmentPlans = identifyDetachmentOpportunities(
    filtered, analyses, currentAct, houseId
  )

  for plan in detachmentPlans:
    logInfo(LogCategory.lcAI,
            &"{houseId} Domestikos: {plan.reason} at {plan.location}")

    result.add(ZeroTurnCommand(
      houseId: houseId,
      commandType: ZeroTurnCommandType.DetachShips,
      sourceFleetId: some(plan.sourceFleetId),
      colonySystem: some(plan.location),
      shipIndices: plan.shipIndices
      # newFleetId will be auto-generated by engine
    ))

    logDebug(LogCategory.lcAI,
             &"{houseId} Detaching {plan.shipIndices.len} ships from {plan.sourceFleetId} " &
             &"for {plan.newFleetRole}")

## =============================================================================
## SHIP TRANSFERS - Optimize fleet compositions
## =============================================================================

type
  TransferPlan* = object
    ## Plan to transfer ships between fleets for composition optimization
    sourceFleetId*: FleetId
    targetFleetId*: FleetId
    shipIndices*: seq[int]
    location*: SystemId
    reason*: string

proc identifyTransferOpportunities*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  houseId: HouseId
): seq[TransferPlan] =
  ## Identify ship transfer opportunities between co-located fleets
  ##
  ## Transfer criteria:
  ## - Balance combat power between defensive fleets
  ## - Consolidate specialized units (all scouts together)
  ##
  ## IMPORTANT: ETACs are NEVER transferred - they are solely for colonization

  result = @[]

  # Group fleets by location
  var fleetsByLocation = initTable[SystemId, seq[FleetAnalysis]]()
  for analysis in analyses:
    if not fleetsByLocation.hasKey(analysis.location):
      fleetsByLocation[analysis.location] = @[]
    fleetsByLocation[analysis.location].add(analysis)

  # For each location with multiple fleets, look for transfer opportunities
  for systemId, fleetsAtLocation in fleetsByLocation:
    if fleetsAtLocation.len < 2:
      continue

    # Check if at friendly colony
    if not isSystemFriendlyColony(filtered, systemId, houseId):
      continue

    # REMOVED: ETAC transfer logic
    # ETACs are ONLY for colonization, never for invasions
    # Invasions use troop transports, not ETACs
    # ETACs should never be transferred out of their colonization fleets
    discard  # Placeholder to keep structure

proc generateTransferCommands*(
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  houseId: HouseId
): seq[ZeroTurnCommand] =
  ## Generate ZeroTurnCommand.TransferShips for fleet optimization
  ##
  ## Moves individual ships between fleets to optimize compositions

  result = @[]

  let transferPlans = identifyTransferOpportunities(filtered, analyses, houseId)

  for plan in transferPlans:
    logInfo(LogCategory.lcAI,
            &"{houseId} Domestikos: {plan.reason} at {plan.location}")

    result.add(ZeroTurnCommand(
      houseId: houseId,
      commandType: ZeroTurnCommandType.TransferShips,
      sourceFleetId: some(plan.sourceFleetId),
      targetFleetId: some(plan.targetFleetId),
      colonySystem: some(plan.location),
      shipIndices: plan.shipIndices
    ))

    logDebug(LogCategory.lcAI,
             &"{houseId} Transferring {plan.shipIndices.len} ships from " &
             &"{plan.sourceFleetId} to {plan.targetFleetId}")

## =============================================================================
## MASTER COORDINATOR - Generate all fleet management commands
## =============================================================================

proc generateFleetManagementCommands*(
  controller: AIController,
  filtered: FilteredGameState,
  analyses: seq[FleetAnalysis],
  currentAct: ai_types.GameAct,
  houseId: HouseId
): seq[ZeroTurnCommand] =
  ## Generate all fleet management zero-turn commands for Domestikos
  ##
  ## Execution order:
  ## 1. Transfers - Optimize compositions first
  ## 2. Merges - Consolidate forces
  ## 3. Detaches - Split for exploration (Act 1 only to avoid undoing merges)

  result = @[]

  # Check if enabled in config
  if not controller.rbaConfig.domestikos.fleet_management_enabled:
    return result

  logDebug(LogCategory.lcAI,
           &"{houseId} Domestikos: Generating fleet management commands for {currentAct}")

  # Phase 1: Ship transfers for composition optimization
  let transferCommands = generateTransferCommands(filtered, analyses, houseId)
  result.add(transferCommands)

  # Phase 2: Fleet mergers for force consolidation
  let mergeCommands = generateMergeCommands(filtered, analyses, houseId)
  result.add(mergeCommands)

  # Phase 3: Fleet detachments (all acts - different strategies per act)
  # Act 1: Split for exploration coverage
  # Act 2+: Detach scouts for reconnaissance, raiders for harassment
  let detachCommands = generateDetachCommands(filtered, analyses, currentAct, houseId)
  result.add(detachCommands)

  if result.len > 0:
    logInfo(LogCategory.lcAI,
            &"{houseId} Domestikos: Generated {result.len} fleet management commands " &
            &"({transferCommands.len} transfers, {mergeCommands.len} merges, " &
            &"{result.len - transferCommands.len - mergeCommands.len} detachments)")
