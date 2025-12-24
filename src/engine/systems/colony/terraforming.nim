## Terraforming Operations - Order Processing and Progress Tracking
##
## Handles terraforming projects for colonies:
## - Order processing: Initiates terraforming projects (validates tech, deducts PP)
## - Progress tracking: Advances active terraforming projects each turn
##
## Per architecture.md: Colony system owns colony operations,
## called from turn_cycle/income_phase.nim

import std/[tables, options, logging, strformat]
import ../../types/[game_state, command, event]
import ../../state/entity_manager
import ../tech/[costs as res_costs, effects as res_effects]
import ../../event_factory/init as event_factory

proc resolveTerraformCommands*(state: var GameState, packet: CommandPacket, events: var seq[GameEvent]) =
  ## Process terraforming commands - initiate new terraforming projects
  ## Per economy.md Section 4.7
  for command in packet.terraformCommands:
    # Validate colony exists and is owned by house using entity_manager
    let colonyOpt = state.colonies.entities.getEntity(command.colonyId)
    if colonyOpt.isNone:
      error "Terraforming failed: System-", command.colonyId, " has no colony"
      continue

    var colony = colonyOpt.get()
    if colony.owner != packet.houseId:
      error "Terraforming failed: ", packet.houseId, " does not own system-", command.colonyId
      continue

    # Check if already terraforming
    if colony.activeTerraforming.isSome:
      error "Terraforming failed: System-", command.colonyId, " already has active terraforming project"
      continue

    # Get house tech level using entity_manager
    let houseOpt = state.houses.entities.getEntity(packet.houseId)
    if houseOpt.isNone:
      error "Terraforming failed: House ", packet.houseId, " not found"
      continue

    let house = houseOpt.get()
    let terLevel = house.techTree.levels.terraformingTech

    # Validate TER level requirement
    let currentClass = ord(colony.planetClass) + 1  # Convert enum to class number (1-7)
    if not res_effects.canTerraform(currentClass, terLevel):
      let targetClass = currentClass + 1
      error "Terraforming failed: TER level ", terLevel, " insufficient for class ", currentClass, " → ", targetClass, " (requires TER ", targetClass, ")"
      continue

    # Calculate costs and duration
    let targetClass = currentClass + 1
    let ppCost = res_effects.getTerraformingBaseCost(currentClass)
    let turnsRequired = res_effects.getTerraformingSpeed(terLevel)

    # Check house treasury has sufficient PP
    if house.treasury < ppCost:
      error "Terraforming failed: Insufficient PP (need ", ppCost, ", have ", house.treasury, ")"
      continue

    # Deduct PP cost from house treasury using entity_manager
    var houseToUpdate = house
    houseToUpdate.treasury -= ppCost
    state.houses.entities.updateEntity(packet.houseId, houseToUpdate)

    # Create terraforming project
    let project = TerraformProject(
      startTurn: state.turn,
      turnsRemaining: turnsRequired,
      targetClass: targetClass,
      ppCost: ppCost,
      ppPaid: ppCost
    )

    colony.activeTerraforming = some(project)
    state.colonies.entities.updateEntity(command.colonyId, colony)

    let className = case targetClass
      of 1: "Extreme"
      of 2: "Desolate"
      of 3: "Hostile"
      of 4: "Harsh"
      of 5: "Benign"
      of 6: "Lush"
      of 7: "Eden"
      else: "Unknown"

    info house.name, " initiated terraforming of system-", command.colonyId, " to ", className, " (class ", targetClass, ") - Cost: ", ppCost, " PP, Duration: ", turnsRequired, " turns"

    # Note: This was using TerraformComplete incorrectly for "initiated" - should be constructionStarted
    events.add(event_factory.constructionStarted(
      packet.houseId,
      &"Terraforming to {className}",
      command.colonyId,
      ppCost
    ))

proc processTerraformingProjects*(state: var GameState, events: var seq[GameEvent]) =
  ## Process active terraforming projects for all houses
  ## Per economy.md Section 4.7

  import ../../state/iterators

  # Iterate over all colonies using iterator (read-only access)
  for (colonyId, colony) in state.allColoniesWithId():
    if colony.activeTerraforming.isNone:
      continue

    let houseId = colony.owner

    # Get house using entity_manager
    let houseOpt = state.houses.entities.getEntity(houseId)
    if houseOpt.isNone:
      continue

    let house = houseOpt.get()

    # Get mutable colony copy
    var colonyMut = colony
    var project = colonyMut.activeTerraforming.get()
    project.turnsRemaining -= 1

    if project.turnsRemaining <= 0:
      # Terraforming complete!
      # Convert int class number (1-7) back to PlanetClass enum (0-6)
      colonyMut.planetClass = PlanetClass(project.targetClass - 1)
      colonyMut.activeTerraforming = none(TerraformProject)

      let className = case project.targetClass
        of 1: "Extreme"
        of 2: "Desolate"
        of 3: "Hostile"
        of 4: "Harsh"
        of 5: "Benign"
        of 6: "Lush"
        of 7: "Eden"
        else: "Unknown"

      info house.name, " completed terraforming of ", colonyId, " to ", className, " (class ", project.targetClass, ")"

      events.add(event_factory.terraformComplete(
        houseId,
        colonyId,
        className
      ))
    else:
      debug house.name, " terraforming ", colonyId, ": ", project.turnsRemaining, " turn(s) remaining"
      # Update project
      colonyMut.activeTerraforming = some(project)

    # Write back using entity_manager
    state.colonies.entities.updateEntity(colonyId, colonyMut)
