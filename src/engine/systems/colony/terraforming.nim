## Terraforming Operations - Order Processing and Progress Tracking
##
## Handles terraforming projects for colonies:
## - Order processing: Initiates terraforming projects (validates tech, deducts PP)
## - Progress tracking: Advances active terraforming projects each turn
##
## Per architecture.md: Colony system owns colony operations,
## called from turn_cycle/income_phase.nim

import std/[options, strformat]
import ../../types/[core, game_state, command, event, starmap, colony]
import ../../state/[engine, iterators]
import ../tech/effects
import ../../event_factory/init
import ../../../common/logger

proc resolveTerraformCommands*(
    state: GameState, packet: CommandPacket, events: var seq[GameEvent]
) =
  ## Process terraforming commands - initiate new terraforming projects
  ## Per economy.md Section 4.7
  for command in packet.terraformCommands:
    # Validate colony exists and is owned by house
    let colonyOpt = state.colony(command.colonyId)
    if colonyOpt.isNone:
      logError("Terraforming", "Terraforming failed: System has no colony",
        "System-" & $command.colonyId)
      continue

    var colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      logError("Terraforming", "Terraforming failed: House does not own system",
        $packet.houseId, "System-" & $command.colonyId)
      continue

    # Check if already terraforming
    if colony.activeTerraforming.isSome:
      logError("Terraforming",
        "Terraforming failed: System already has active terraforming project",
        "System-" & $command.colonyId)
      continue

    # Get house tech level
    let houseOpt = state.house(packet.houseId)
    if houseOpt.isNone:
      logError("Terraforming", "Terraforming failed: House not found",
        $packet.houseId)
      continue

    let house = houseOpt.get()
    let terLevel = house.techTree.levels.ter

    # Get system to access planetClass
    let systemOpt = state.system(colony.systemId)
    if systemOpt.isNone:
      logError("Terraforming", "Terraforming failed: System not found for colony",
        $command.colonyId)
      continue
    let system = systemOpt.get()

    # Validate TER level requirement
    let currentClass = ord(system.planetClass) + 1 # Convert enum to class number (1-7)
    if not canTerraform(currentClass, terLevel):
      let targetClass = currentClass + 1
      logError("Terraforming",
        &"Terraforming failed: TER level {terLevel} insufficient for class {currentClass} → {targetClass}",
        &"(requires TER {targetClass})")
      continue

    # Calculate costs and duration
    let targetClass = currentClass + 1
    let ppCost = getTerraformingBaseCost(currentClass)
    let turnsRequired = getTerraformingSpeed(terLevel)

    # Check house treasury has sufficient PP
    if house.treasury < ppCost:
      logError("Terraforming",
        &"Terraforming failed: Insufficient PP (need {ppCost}, have {house.treasury})")
      continue

    # Deduct PP cost from house treasury
    var houseToUpdate = house
    houseToUpdate.treasury -= ppCost.int32
    state.updateHouse(packet.houseId, houseToUpdate)

    # Create terraforming project
    let project = TerraformProject(
      startTurn: state.turn,
      turnsRemaining: turnsRequired.int32,
      targetClass: targetClass.int32,
      ppCost: ppCost.int32,
      ppPaid: ppCost.int32,
    )

    colony.activeTerraforming = some(project)
    state.updateColony(command.colonyId, colony)

    let className =
      case targetClass
      of 1: "Extreme"
      of 2: "Desolate"
      of 3: "Hostile"
      of 4: "Harsh"
      of 5: "Benign"
      of 6: "Lush"
      of 7: "Eden"
      else: "Unknown"

    logInfo("Terraforming",
      &"{house.name} initiated terraforming of system-{command.colonyId} to {className} (class {targetClass})",
      &"Cost: {ppCost} PP", &"Duration: {turnsRequired} turns")

    # Note: This was using TerraformComplete incorrectly for "initiated" - should be constructionStarted
    events.add(
      constructionStarted(
        packet.houseId, &"Terraforming to {className}", colony.systemId, ppCost
      )
    )

proc processTerraformingProjects*(state: GameState, events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  # Iterate over all colonies using iterator (read-only access)
  for (colonyId, colony) in state.allColoniesWithId():
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner

    # Get house
    let houseOpt = state.house(houseId)
    if houseOpt.isNone:
      continue

    let house = houseOpt.get()

    # Get mutable colony copy
    var colonyMut = colony
    var project = colonyMut.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Update System.planetClass (single source of truth)
      let systemOpt = state.system(colony.systemId)
      if systemOpt.isSome:
        var systemMut = systemOpt.get()
        # Convert int class number (1-7) back to PlanetClass enum (0-6)
        systemMut.planetClass = PlanetClass(project.targetClass - 1)
        state.updateSystem(colony.systemId, systemMut)

      colonyMut.activeTerraforming = none(TerraformProject)

      let className =
        case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      logInfo("Terraforming",
        &"{house.name} completed terraforming of {colonyId} to {className} (class {project.targetClass})")

      events.add(terraformComplete(houseId, colony.systemId, className))
    else:
      logDebug("Terraforming",
        &"{house.name} terraforming {colonyId}: {project.turnsRemaining} turn(s) remaining")
      # Update project
      colonyMut.activeTerraforming = some(project)

    # Write back colony changes
    state.updateColony(colonyId, colonyMut)
