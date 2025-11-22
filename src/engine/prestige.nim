## Prestige System
##
## Victory point tracking and prestige modifiers per gameplay.md:1.1 and reference.md:9.4
##
## Prestige represents House dominance and is the victory condition
## Victory: First to 5000 prestige OR last house standing
##
## Prestige sources:
## - Military victories (combat, eliminations)
## - Economic prosperity (low taxes, colonies)
## - Technological advancement
## - Diplomatic actions
##
## Prestige penalties:
## - High taxes (rolling average > 50%)
## - Blockaded colonies
## - Maintenance shortfalls
## - Military defeats

import std/tables
import ../common/types/core
import config/prestige_config

export core.HouseId

type
  PrestigeSource* {.pure.} = enum
    ## Sources of prestige gain/loss
    CombatVictory,          # Win space battle
    TaskForceDestroyed,     # Destroy enemy task force
    FleetRetreated,         # Force enemy retreat
    SquadronDestroyed,      # Destroy individual squadron
    ColonySeized,           # Capture colony via invasion
    ColonyEstablished,      # Establish new colony
    TechAdvancement,        # Advance tech level
    LowTaxBonus,            # Low tax rate bonus (per colony)
    HighTaxPenalty,         # High tax average penalty
    BlockadePenalty,        # Colony under blockade
    MaintenanceShortfall,   # Failed to pay maintenance
    PactViolation,          # Violated non-aggression pact
    Eliminated,             # House eliminated from game

  PrestigeEvent* = object
    ## Single prestige gain/loss event
    source*: PrestigeSource
    amount*: int            # Positive = gain, negative = loss
    description*: string    # Event description for reports

  PrestigeReport* = object
    ## Prestige changes for a turn
    houseId*: HouseId
    startingPrestige*: int
    events*: seq[PrestigeEvent]
    endingPrestige*: int

## Prestige Values (reference.md:9.4)

const PRESTIGE_VALUES* = {
  PrestigeSource.CombatVictory: 1,
  PrestigeSource.TaskForceDestroyed: 3,
  PrestigeSource.FleetRetreated: 2,
  PrestigeSource.SquadronDestroyed: 1,
  PrestigeSource.ColonySeized: 10,
  PrestigeSource.ColonyEstablished: 5,
  PrestigeSource.TechAdvancement: 2,
  PrestigeSource.BlockadePenalty: -2,  # Per turn per colony
  PrestigeSource.Eliminated: -50,
}.toTable

## Prestige Calculation

proc createPrestigeEvent*(source: PrestigeSource, amount: int, description: string): PrestigeEvent =
  ## Create prestige event
  result = PrestigeEvent(
    source: source,
    amount: amount,
    description: description
  )

proc calculatePrestigeChange*(events: seq[PrestigeEvent]): int =
  ## Calculate net prestige change from events
  result = 0
  for event in events:
    result += event.amount

proc createPrestigeReport*(houseId: HouseId, startingPrestige: int,
                          events: seq[PrestigeEvent]): PrestigeReport =
  ## Create prestige report for house
  let change = calculatePrestigeChange(events)

  result = PrestigeReport(
    houseId: houseId,
    startingPrestige: startingPrestige,
    events: events,
    endingPrestige: startingPrestige + change
  )

## Prestige from Combat (operations.md:7.3.3)

proc awardCombatPrestige*(victor: HouseId, defeated: HouseId,
                         taskForceDestroyed: bool,
                         squadronsDestroyed: int,
                         forcedRetreat: bool): seq[PrestigeEvent] =
  ## Award prestige for combat outcome
  result = @[]

  # Combat victory
  result.add(createPrestigeEvent(
    PrestigeSource.CombatVictory,
    PRESTIGE_VALUES[PrestigeSource.CombatVictory],
    $victor & " defeated " & $defeated
  ))

  # Task force destroyed
  if taskForceDestroyed:
    result.add(createPrestigeEvent(
      PrestigeSource.TaskForceDestroyed,
      PRESTIGE_VALUES[PrestigeSource.TaskForceDestroyed],
      $victor & " destroyed " & $defeated & " task force"
    ))

  # Squadrons destroyed
  if squadronsDestroyed > 0:
    let prestigeAmount = PRESTIGE_VALUES[PrestigeSource.SquadronDestroyed] * squadronsDestroyed
    result.add(createPrestigeEvent(
      PrestigeSource.SquadronDestroyed,
      prestigeAmount,
      $victor & " destroyed " & $squadronsDestroyed & " squadrons"
    ))

  # Forced retreat
  if forcedRetreat:
    result.add(createPrestigeEvent(
      PrestigeSource.FleetRetreated,
      PRESTIGE_VALUES[PrestigeSource.FleetRetreated],
      $victor & " forced " & $defeated & " to retreat"
    ))

## Prestige from Economy

proc awardColonyPrestige*(houseId: HouseId, colonyType: string): PrestigeEvent =
  ## Award prestige for establishing colony
  let source = if colonyType == "seized":
    PrestigeSource.ColonySeized
  else:
    PrestigeSource.ColonyEstablished

  let amount = PRESTIGE_VALUES[source]

  return createPrestigeEvent(
    source,
    amount,
    $houseId & " " & colonyType & " colony"
  )

proc applyTaxPrestige*(houseId: HouseId, colonyCount: int, taxRate: int): PrestigeEvent =
  ## Apply prestige bonus from low tax rate
  ## Per economy.md:3.2.2
  var bonusPerColony = 0

  if taxRate >= 41:
    bonusPerColony = 0
  elif taxRate >= 31:
    bonusPerColony = 0
  elif taxRate >= 21:
    bonusPerColony = 1
  elif taxRate >= 11:
    bonusPerColony = 2
  else:
    bonusPerColony = 3

  let totalBonus = bonusPerColony * colonyCount

  return createPrestigeEvent(
    PrestigeSource.LowTaxBonus,
    totalBonus,
    $houseId & " low tax bonus (rate: " & $taxRate & "%)"
  )

proc applyHighTaxPenalty*(houseId: HouseId, avgTaxRate: int): PrestigeEvent =
  ## Apply prestige penalty from high rolling average tax
  ## Per economy.md:3.2.1
  var penalty = 0

  if avgTaxRate <= 50:
    penalty = 0
  elif avgTaxRate <= 60:
    penalty = -1
  elif avgTaxRate <= 70:
    penalty = -2
  elif avgTaxRate <= 80:
    penalty = -4
  elif avgTaxRate <= 90:
    penalty = -7
  else:
    penalty = -11

  return createPrestigeEvent(
    PrestigeSource.HighTaxPenalty,
    penalty,
    $houseId & " high tax penalty (avg: " & $avgTaxRate & "%)"
  )

proc applyBlockadePenalty*(houseId: HouseId, blockadedColonies: int): PrestigeEvent =
  ## Apply prestige penalty for blockaded colonies
  ## Per operations.md:6.2.6: -2 prestige per blockaded colony per turn
  let penalty = PRESTIGE_VALUES[PrestigeSource.BlockadePenalty] * blockadedColonies

  return createPrestigeEvent(
    PrestigeSource.BlockadePenalty,
    penalty,
    $houseId & " has " & $blockadedColonies & " blockaded colonies"
  )

## Prestige from Technology

proc awardTechPrestige*(houseId: HouseId, techField: string, level: int): PrestigeEvent =
  ## Award prestige for tech advancement
  let amount = PRESTIGE_VALUES[PrestigeSource.TechAdvancement]

  return createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    amount,
    $houseId & " advanced " & techField & " to level " & $level
  )

## Victory Conditions (gameplay.md:1.1)

const PRESTIGE_VICTORY_THRESHOLD* = 5000

proc checkPrestigeVictory*(prestige: int): bool =
  ## Check if house achieved prestige victory
  return prestige >= PRESTIGE_VICTORY_THRESHOLD

proc checkDefensiveCollapse*(prestige: int, turnsBelow: int): bool =
  ## Check if house enters defensive collapse
  ## Per gameplay.md:1.4.1: Prestige < 0 for 3 consecutive turns
  return prestige < 0 and turnsBelow >= 3

## Morale Effects from Prestige (operations.md:7.1.4)

proc getMoraleROEModifier*(prestige: int): int =
  ## Get morale modifier to ROE from prestige
  ## Per operations.md:7.1.4
  if prestige <= 0:
    return -2  # Crisis
  elif prestige <= 20:
    return -1  # Low
  elif prestige <= 60:
    return 0   # Average/Good
  elif prestige <= 80:
    return +1  # High
  else:
    return +2  # Elite (81+)

proc getMoraleCERModifier*(prestige: int): int =
  ## Get morale modifier to CER from prestige
  ## Per operations.md:7.1.4
  ## Note: Requires turn-based morale check roll (not implemented here)
  return getMoraleROEModifier(prestige)
