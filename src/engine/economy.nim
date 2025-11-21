## Economy and production system
##
## OFFLINE GAMEPLAY SYSTEM - No network dependencies
## Implements resource production, ship construction, research allocation

import std/[tables, options]
import ../common/types/[core, tech]
import gamestate, ship, fleet

type
  ProductionOutput* = object
    credits*: int
    production*: int
    research*: int

  ConstructionResult* {.pure.} = enum
    Started,      # New project started
    InProgress,   # Existing project advanced
    Completed,    # Project finished this turn
    InsufficientFunds,
    InsufficientCapacity,
    InvalidProject

  CompletedProject* = object
    projectType*: BuildingType  # Type of construction completed
    item*: string  # Ship type, building name, etc.

## Production calculation

proc calculateProduction*(colony: Colony, techLevel: int): ProductionOutput =
  ## Calculate colony production for current turn
  ##
  ## TODO M1: Base production from population
  ## TODO M1: Apply infrastructure modifiers
  ## TODO M1: Apply resource quality bonuses
  ## TODO M1: Apply tech level modifiers
  ## TODO M1: Apply building effects
  ## TODO M1: Split between credits/production/research
  ##
  ## STUB: Simple production based on population
  let totalProduction = colony.population div 10  # 1 production per 10 population
  result = ProductionOutput(
    credits: totalProduction div 3,
    production: totalProduction div 3,
    research: totalProduction div 3
  )

proc calculateHouseIncome*(state: GameState, houseId: HouseId): ProductionOutput =
  ## Calculate total income for a house
  ## Sums production from all colonies
  ##
  ## TODO M1: Sum all colony production
  ## TODO M1: Apply house-wide modifiers
  ## TODO M1: Calculate trade income
  ##
  ## STUB: Sum production from all house colonies
  result = ProductionOutput(credits: 0, production: 0, research: 0)

  for colony in state.colonies.values:
    if colony.owner == houseId:
      let colonyProd = calculateProduction(colony, 0)  # TODO: pass actual tech level
      result.credits += colonyProd.credits
      result.production += colonyProd.production
      result.research += colonyProd.research

## Construction

proc startConstruction*(colony: var Colony, project: ConstructionProject,
                       treasury: int): ConstructionResult =
  ## Start new construction project at colony
  ##
  ## TODO M1: Validate colony has capacity (one project at a time initially)
  ## TODO M1: Check sufficient funds for down payment
  ## TODO M1: Validate project type (ship, building, infrastructure)
  ## TODO M1: Set project in colony.underConstruction
  ##
  ## STUB: Simple construction start (no validation)
  if colony.underConstruction.isSome:
    return ConstructionResult.InsufficientCapacity

  colony.underConstruction = some(project)
  return ConstructionResult.Started

proc advanceConstruction*(colony: var Colony): Option[CompletedProject] =
  ## Advance construction one turn
  ## Returns completed project if finished
  ##
  ## TODO M1: Apply colony production to project
  ## TODO M1: Check if project completed
  ## TODO M1: If complete, return project details and clear slot
  ## TODO M1: If not complete, update progress
  ##
  ## STUB: No construction advancement for M1
  return none(CompletedProject)

proc completeShipConstruction*(colony: Colony, shipType: ShipType,
                              state: var GameState): FleetId =
  ## Deploy newly constructed ship
  ## Creates new fleet or adds to existing fleet at colony
  ##
  ## TODO M1: Create new ship
  ## TODO M1: Find or create fleet at colony system
  ## TODO M1: Add ship to fleet
  ## TODO M1: Return fleet ID
  ##
  ## STUB: Skip ship construction for M1
  return FleetId("")  # Return empty fleet ID

## Research

proc applyResearch*(house: var House, field: TechField, points: int): bool =
  ## Apply research points to tech tree
  ## Returns true if tech level advanced
  ##
  ## TODO M1: Add points to tech field accumulator
  ## TODO M1: Check if enough for next level (cost increases per level)
  ## TODO M1: If level up, increment tech level and reset accumulator
  ## TODO M1: Apply any immediate effects of tech advancement
  ##
  ## STUB: No research advancement for M1
  return false

proc getResearchCost*(currentLevel: int): int =
  ## Calculate research points needed for next tech level
  ## Cost increases with each level
  ##
  ## TODO: Implement scaling research cost
  ## Suggested: 1000 * (level + 1)^2
  return 1000 * (currentLevel + 1) * (currentLevel + 1)

## Upkeep and maintenance

proc calculateFleetUpkeep*(fleet: Fleet): int =
  ## Calculate maintenance cost for fleet
  ##
  ## TODO M1: Sum upkeep cost for all ships
  ## TODO M1: Apply modifiers for damaged ships
  ## TODO M1: Check for special cases (mothballed, etc.)
  ##
  ## STUB: Simple upkeep - 1 credit per ship
  return fleet.ships.len

proc calculateHouseUpkeep*(state: GameState, houseId: HouseId): int =
  ## Calculate total upkeep for house
  ##
  ## TODO M1: Sum fleet upkeep
  ## TODO M1: Add building maintenance costs
  ## TODO M1: Add infrastructure maintenance
  ##
  ## STUB: Sum fleet upkeep for all house fleets
  result = 0

  for fleet in state.fleets.values:
    if fleet.owner == houseId:
      result += calculateFleetUpkeep(fleet)
