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

import std/options
import ../common/types/core
import config/prestige_config
import config/prestige_multiplier

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

## Prestige Values (loaded from config/prestige.toml)

proc getPrestigeValue*(source: PrestigeSource): int =
  ## Get prestige value from configuration for given source
  ## Maps PrestigeSource enum to config values
  case source
  of PrestigeSource.CombatVictory:
    globalPrestigeConfig.military.fleet_victory
  of PrestigeSource.TaskForceDestroyed:
    # Task force destruction uses fleet_victory prestige
    globalPrestigeConfig.military.fleet_victory
  of PrestigeSource.FleetRetreated:
    globalPrestigeConfig.military.force_retreat
  of PrestigeSource.SquadronDestroyed:
    globalPrestigeConfig.military.destroy_squadron
  of PrestigeSource.ColonySeized:
    globalPrestigeConfig.military.invade_planet
  of PrestigeSource.ColonyEstablished:
    globalPrestigeConfig.economic.establish_colony
  of PrestigeSource.TechAdvancement:
    globalPrestigeConfig.economic.tech_advancement
  of PrestigeSource.BlockadePenalty:
    globalPrestigeConfig.penalties.blockade_penalty
  of PrestigeSource.Eliminated:
    globalPrestigeConfig.military.eliminate_house
  of PrestigeSource.LowTaxBonus:
    # Low tax bonus calculated dynamically, not from this function
    0
  of PrestigeSource.HighTaxPenalty:
    # High tax penalty calculated dynamically, not from this function
    0
  of PrestigeSource.MaintenanceShortfall:
    # Maintenance shortfall calculated dynamically, not from this function
    0
  of PrestigeSource.PactViolation:
    # Pact violation prestige from diplomacy config
    globalPrestigeConfig.diplomacy.pact_violation

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
## Zero-Sum System: Combat is competitive - winner gains prestige, loser loses equal amount

type
  CombatPrestigeResult* = object
    ## Result of combat prestige calculation
    victorEvents*: seq[PrestigeEvent]   # Prestige events for victor (positive)
    defeatedEvents*: seq[PrestigeEvent] # Prestige events for defeated (negative)

proc awardCombatPrestige*(victor: HouseId, defeated: HouseId,
                         taskForceDestroyed: bool,
                         squadronsDestroyed: int,
                         forcedRetreat: bool): CombatPrestigeResult =
  ## Award prestige for combat outcome (zero-sum: winner gains, loser loses)
  result.victorEvents = @[]
  result.defeatedEvents = @[]

  # Combat victory (zero-sum)
  let victoryPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.CombatVictory))
  result.victorEvents.add(createPrestigeEvent(
    PrestigeSource.CombatVictory,
    victoryPrestige,
    $victor & " defeated " & $defeated
  ))
  result.defeatedEvents.add(createPrestigeEvent(
    PrestigeSource.CombatVictory,
    -victoryPrestige,
    $defeated & " defeated by " & $victor
  ))

  # Task force destroyed (zero-sum)
  if taskForceDestroyed:
    let tfPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.TaskForceDestroyed))
    result.victorEvents.add(createPrestigeEvent(
      PrestigeSource.TaskForceDestroyed,
      tfPrestige,
      $victor & " destroyed " & $defeated & " task force"
    ))
    result.defeatedEvents.add(createPrestigeEvent(
      PrestigeSource.TaskForceDestroyed,
      -tfPrestige,
      $defeated & " lost task force to " & $victor
    ))

  # Squadrons destroyed (zero-sum)
  if squadronsDestroyed > 0:
    let squadronPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.SquadronDestroyed)) * squadronsDestroyed
    result.victorEvents.add(createPrestigeEvent(
      PrestigeSource.SquadronDestroyed,
      squadronPrestige,
      $victor & " destroyed " & $squadronsDestroyed & " squadrons"
    ))
    result.defeatedEvents.add(createPrestigeEvent(
      PrestigeSource.SquadronDestroyed,
      -squadronPrestige,
      $defeated & " lost " & $squadronsDestroyed & " squadrons"
    ))

  # Forced retreat (zero-sum)
  if forcedRetreat:
    let retreatPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.FleetRetreated))
    result.victorEvents.add(createPrestigeEvent(
      PrestigeSource.FleetRetreated,
      retreatPrestige,
      $victor & " forced " & $defeated & " to retreat"
    ))
    result.defeatedEvents.add(createPrestigeEvent(
      PrestigeSource.FleetRetreated,
      -retreatPrestige,
      $defeated & " forced to retreat by " & $victor
    ))

## Prestige from Economy

type
  ColonyPrestigeResult* = object
    ## Result of colony prestige calculation
    attackerEvent*: PrestigeEvent        # Attacker gains (if seized)
    defenderEvent*: Option[PrestigeEvent] # Defender loses (if seized, zero-sum)

proc awardColonyPrestige*(attackerId: HouseId, colonyType: string, defenderId: Option[HouseId] = none(HouseId)): ColonyPrestigeResult =
  ## Award prestige for colony actions
  ## - "established": New colony (absolute gain, no defender)
  ## - "seized": Invasion/blitz (zero-sum: attacker gains, defender loses)

  let source = if colonyType == "seized":
    PrestigeSource.ColonySeized
  else:
    PrestigeSource.ColonyEstablished

  let amount = applyMultiplier(getPrestigeValue(source))

  result.attackerEvent = createPrestigeEvent(
    source,
    amount,
    $attackerId & " " & colonyType & " colony"
  )

  # Zero-sum for seized colonies
  if colonyType == "seized" and defenderId.isSome:
    result.defenderEvent = some(createPrestigeEvent(
      PrestigeSource.ColonySeized,
      -amount,
      $defenderId.get() & " lost colony to " & $attackerId
    ))
  else:
    result.defenderEvent = none(PrestigeEvent)

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
  let penalty = applyMultiplier(getPrestigeValue(PrestigeSource.BlockadePenalty)) * blockadedColonies

  return createPrestigeEvent(
    PrestigeSource.BlockadePenalty,
    penalty,
    $houseId & " has " & $blockadedColonies & " blockaded colonies"
  )

## Prestige from Technology

proc awardTechPrestige*(houseId: HouseId, techField: string, level: int): PrestigeEvent =
  ## Award prestige for tech advancement
  let amount = applyMultiplier(getPrestigeValue(PrestigeSource.TechAdvancement))

  return createPrestigeEvent(
    PrestigeSource.TechAdvancement,
    amount,
    $houseId & " advanced " & techField & " to level " & $level
  )

## Victory Conditions (gameplay.md:1.1)

const prestigeVictoryThreshold* = 5000

proc checkPrestigeVictory*(prestige: int): bool =
  ## Check if house achieved prestige victory
  return prestige >= prestigeVictoryThreshold

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
