## Random Combat Scenario Generator
##
## Generates random fleets and battles for combat testing
## Uses deterministic PRNG for reproducible tests

import std/[random, sequtils, strformat]
import ../src/engine/[squadron, combat_types, combat_engine]
import ../src/common/types/[core, units]

export TaskForce, Squadron, ShipClass

## Configuration

type
  FleetGenConfig* = object
    ## Configuration for random fleet generation
    minSquadrons*: int
    maxSquadrons*: int
    minShipsPerSquadron*: int
    maxShipsPerSquadron*: int
    allowedShipClasses*: seq[ShipClass]
    techLevel*: int
    roe*: int
    prestige*: int

proc defaultConfig*(): FleetGenConfig =
  ## Default configuration for balanced fleets
  FleetGenConfig(
    minSquadrons: 1,
    maxSquadrons: 5,
    minShipsPerSquadron: 1,
    maxShipsPerSquadron: 4,
    allowedShipClasses: @[
      ShipClass.Fighter,
      ShipClass.Destroyer,
      ShipClass.Cruiser,
      ShipClass.Battleship
    ],
    techLevel: 1,
    roe: 6,  # Engage equal or inferior
    prestige: 50
  )

proc fighterHeavyConfig*(): FleetGenConfig =
  ## Configuration for fighter-heavy fleets
  var cfg = defaultConfig()
  cfg.allowedShipClasses = @[ShipClass.Fighter, ShipClass.Carrier]
  cfg.minSquadrons = 3
  cfg.maxSquadrons = 8
  return cfg

proc capitalShipConfig*(): FleetGenConfig =
  ## Configuration for capital ship fleets
  var cfg = defaultConfig()
  cfg.allowedShipClasses = @[
    ShipClass.Cruiser,
    ShipClass.HeavyCruiser,
    ShipClass.Battleship,
    ShipClass.Dreadnought
  ]
  cfg.minShipsPerSquadron = 2
  cfg.maxShipsPerSquadron = 5
  return cfg

proc raiderConfig*(): FleetGenConfig =
  ## Configuration for raider fleets
  var cfg = defaultConfig()
  cfg.allowedShipClasses = @[ShipClass.Raider, ShipClass.Scout]
  cfg.minSquadrons = 2
  cfg.maxSquadrons = 4
  return cfg

## Random Generation

proc generateRandomSquadron*(
  config: FleetGenConfig,
  houseId: HouseId,
  squadronId: SquadronId,
  rng: var Rand
): Squadron =
  ## Generate random squadron based on config

  # Pick random flagship class
  let flagshipClass = rng.sample(config.allowedShipClasses)
  let flagship = newEnhancedShip(flagshipClass, config.techLevel)

  result = newSquadron(flagship, squadronId, houseId)

  # Add random ships to squadron (respecting CR limit)
  let numShips = rng.rand(config.minShipsPerSquadron .. config.maxShipsPerSquadron)

  for i in 0..<numShips:
    let shipClass = rng.sample(config.allowedShipClasses)
    let ship = newEnhancedShip(shipClass, config.techLevel)

    # Try to add - may fail if CR exceeded
    discard result.addShip(ship)

proc generateRandomFleet*(
  config: FleetGenConfig,
  houseId: HouseId,
  seed: int64
): seq[Squadron] =
  ## Generate random fleet of squadrons
  var rng = initRand(seed)
  result = @[]

  let numSquadrons = rng.rand(config.minSquadrons .. config.maxSquadrons)

  for i in 0..<numSquadrons:
    let squadronId = fmt"{houseId}-sq-{i+1}"
    let squadron = generateRandomSquadron(config, houseId, squadronId, rng)
    result.add(squadron)

proc generateRandomTaskForce*(
  config: FleetGenConfig,
  houseId: HouseId,
  seed: int64,
  isHomeworld: bool = false
): TaskForce =
  ## Generate complete random Task Force
  let squadrons = generateRandomFleet(config, houseId, seed)
  return initializeTaskForce(
    houseId,
    squadrons,
    config.roe,
    config.prestige,
    isHomeworld
  )

## Battle Scenario Generation

type
  BattleScenario* = object
    ## Complete battle scenario with context
    name*: string
    description*: string
    taskForces*: seq[TaskForce]  # All participating task forces
    systemId*: SystemId
    seed*: int64
    expectedOutcome*: string

proc generateBalancedBattle*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate balanced 1v1 battle
  let config = defaultConfig()

  result = BattleScenario(
    name: name,
    description: "Balanced fleet engagement",
    taskForces: @[
      generateRandomTaskForce(config, "house-alpha", seed),
      generateRandomTaskForce(config, "house-beta", seed + 1)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Either side could win"
  )

proc generateAsymmetricBattle*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate asymmetric battle (attacker stronger)
  var attackerCfg = defaultConfig()
  attackerCfg.maxSquadrons = 5
  attackerCfg.prestige = 70

  var defenderCfg = defaultConfig()
  defenderCfg.maxSquadrons = 2
  defenderCfg.prestige = 30

  result = BattleScenario(
    name: name,
    description: "Asymmetric engagement - attacker stronger",
    taskForces: @[
      generateRandomTaskForce(attackerCfg, "house-alpha", seed),
      generateRandomTaskForce(defenderCfg, "house-beta", seed + 1)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Attacker favored"
  )

proc generateFighterVsCapital*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate fighter swarm vs capital ships
  let fighterCfg = fighterHeavyConfig()
  let capitalCfg = capitalShipConfig()

  result = BattleScenario(
    name: name,
    description: "Fighter swarm vs capital ships",
    taskForces: @[
      generateRandomTaskForce(fighterCfg, "house-fighters", seed),
      generateRandomTaskForce(capitalCfg, "house-capitals", seed + 1)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Tactical matchup test"
  )

proc generateRaiderAmbush*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate raider ambush scenario
  let raiderCfg = raiderConfig()
  let targetCfg = defaultConfig()

  result = BattleScenario(
    name: name,
    description: "Cloaked raider ambush",
    taskForces: @[
      generateRandomTaskForce(raiderCfg, "house-raiders", seed),
      generateRandomTaskForce(targetCfg, "house-target", seed + 1)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Ambush advantage test"
  )

proc generateMultiFactionBattle*(
  name: string,
  seed: int64,
  numFactions: int,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate multi-faction battle (3+ empires converging)
  var rng = initRand(seed)

  # Generate multiple task forces with varying configs
  var taskForces: seq[TaskForce] = @[]

  for i in 0..<numFactions:
    let houseName = fmt"house-{char(ord('A') + i)}"
    let factionSeed = seed + int64(i * 100)

    # Vary tech levels (0-3)
    var config = defaultConfig()
    config.techLevel = rng.rand(0..3)

    # Vary fleet sizes
    config.maxSquadrons = rng.rand(1..4)
    config.prestige = rng.rand(30..70)

    let tf = generateRandomTaskForce(config, houseName, factionSeed)
    taskForces.add(tf)

  result = BattleScenario(
    name: name,
    description: fmt"{numFactions}-way battle with mixed tech levels",
    taskForces: taskForces,
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Multi-faction chaos"
  )

proc generateTechMismatchBattle*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate tech level mismatch (advanced vs primitive)
  var attackerCfg = defaultConfig()
  attackerCfg.techLevel = 3  # Advanced
  attackerCfg.maxSquadrons = 2
  attackerCfg.prestige = 80

  var defenderCfg = defaultConfig()
  defenderCfg.techLevel = 0  # Primitive
  defenderCfg.maxSquadrons = 5
  defenderCfg.prestige = 40

  result = BattleScenario(
    name: name,
    description: "Tech level mismatch - advanced vs primitive",
    taskForces: @[
      generateRandomTaskForce(attackerCfg, "house-advanced", seed),
      generateRandomTaskForce(defenderCfg, "house-primitive", seed + 1)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Quality vs quantity"
  )

proc generateHomeDefenseBattle*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate homeworld defense scenario
  var attackerCfg = defaultConfig()
  attackerCfg.maxSquadrons = 4
  attackerCfg.prestige = 60
  attackerCfg.techLevel = 2

  var defenderCfg = defaultConfig()
  defenderCfg.maxSquadrons = 3
  defenderCfg.prestige = 70
  defenderCfg.techLevel = 1

  result = BattleScenario(
    name: name,
    description: "Homeworld defense - defender never retreats",
    taskForces: @[
      generateRandomTaskForce(attackerCfg, "house-invader", seed),
      generateRandomTaskForce(defenderCfg, "house-defender", seed + 1, isHomeworld = true)
    ],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Fight to the death"
  )

proc generateMergedFleetBattle*(
  name: string,
  seed: int64,
  systemId: SystemId = 0
): BattleScenario =
  ## Generate battle with merged fleets (rendezvous/join orders)
  ## Simulates multiple fleets from same house converging
  var rng = initRand(seed)

  # House Alpha sends 2 fleets that merged via rendezvous
  var alphaConfig1 = defaultConfig()
  alphaConfig1.maxSquadrons = 3
  alphaConfig1.techLevel = rng.rand(1..2)
  let alphaFleet1 = generateRandomFleet(alphaConfig1, "house-alpha", seed)

  var alphaConfig2 = defaultConfig()
  alphaConfig2.maxSquadrons = 2
  alphaConfig2.techLevel = rng.rand(1..2)
  let alphaFleet2 = generateRandomFleet(alphaConfig2, "house-alpha", seed + 100)

  # Merge into single task force
  var alphaMerged = alphaFleet1 & alphaFleet2
  let alphaTF = initializeTaskForce("house-alpha", alphaMerged, 6, 60, false)

  # House Beta sends single fleet
  var betaConfig = defaultConfig()
  betaConfig.maxSquadrons = 4
  betaConfig.techLevel = rng.rand(0..1)
  let betaTF = generateRandomTaskForce(betaConfig, "house-beta", seed + 200)

  result = BattleScenario(
    name: name,
    description: "Merged fleet battle - multiple fleets rendezvoused",
    taskForces: @[alphaTF, betaTF],
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Fleet coordination matters"
  )

## Batch Generation

proc generateTestSuite*(baseSeed: int64, numScenarios: int): seq[BattleScenario] =
  ## Generate suite of diverse test scenarios
  result = @[]

  let scenarioTypes = [
    "balanced",
    "asymmetric",
    "fighter_vs_capital",
    "raider_ambush",
    "multi_faction_3",
    "multi_faction_4",
    "multi_faction_6",
    "multi_faction_12",  # Max player stress test
    "tech_mismatch",
    "home_defense",
    "merged_fleet"       # Rendezvous/join scenarios
  ]

  for i in 0..<numScenarios:
    let scenarioType = scenarioTypes[i mod scenarioTypes.len]
    let seed = baseSeed + int64(i * 1000)
    let name = fmt"{scenarioType}_{i+1}"

    let scenario = case scenarioType
      of "balanced":
        generateBalancedBattle(name, seed)
      of "asymmetric":
        generateAsymmetricBattle(name, seed)
      of "fighter_vs_capital":
        generateFighterVsCapital(name, seed)
      of "raider_ambush":
        generateRaiderAmbush(name, seed)
      of "multi_faction_3":
        generateMultiFactionBattle(name, seed, 3)
      of "multi_faction_4":
        generateMultiFactionBattle(name, seed, 4)
      of "multi_faction_6":
        generateMultiFactionBattle(name, seed, 6)
      of "multi_faction_12":
        generateMultiFactionBattle(name, seed, 12)  # Max players
      of "tech_mismatch":
        generateTechMismatchBattle(name, seed)
      of "home_defense":
        generateHomeDefenseBattle(name, seed)
      of "merged_fleet":
        generateMergedFleetBattle(name, seed)
      else:
        generateBalancedBattle(name, seed)

    result.add(scenario)

## Helpers

proc `$`*(scenario: BattleScenario): string =
  ## Pretty print scenario
  result = fmt"""
Battle: {scenario.name}
Description: {scenario.description}
"""
  for i, tf in scenario.taskForces:
    result.add(fmt"Faction {i+1}: {tf.house} ({tf.squadrons.len} squadrons, ROE {tf.roe})" & "\n")
  result.add(fmt"Expected: {scenario.expectedOutcome}" & "\n")
  result.add(fmt"Seed: {scenario.seed}" & "\n")
