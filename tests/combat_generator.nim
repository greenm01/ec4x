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
    attacker*: TaskForce
    defender*: TaskForce
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
    attacker: generateRandomTaskForce(config, "house-alpha", seed),
    defender: generateRandomTaskForce(config, "house-beta", seed + 1),
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
    attacker: generateRandomTaskForce(attackerCfg, "house-alpha", seed),
    defender: generateRandomTaskForce(defenderCfg, "house-beta", seed + 1),
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
    attacker: generateRandomTaskForce(fighterCfg, "house-fighters", seed),
    defender: generateRandomTaskForce(capitalCfg, "house-capitals", seed + 1),
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
    attacker: generateRandomTaskForce(raiderCfg, "house-raiders", seed),
    defender: generateRandomTaskForce(targetCfg, "house-target", seed + 1),
    systemId: systemId,
    seed: seed,
    expectedOutcome: "Ambush advantage test"
  )

## Batch Generation

proc generateTestSuite*(baseSeed: int64, numScenarios: int): seq[BattleScenario] =
  ## Generate suite of diverse test scenarios
  result = @[]

  let scenarioTypes = [
    "balanced",
    "asymmetric",
    "fighter_vs_capital",
    "raider_ambush"
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
      else:
        generateBalancedBattle(name, seed)

    result.add(scenario)

## Helpers

proc `$`*(scenario: BattleScenario): string =
  ## Pretty print scenario
  result = fmt"""
Battle: {scenario.name}
Description: {scenario.description}
Attacker: {scenario.attacker.house} ({scenario.attacker.squadrons.len} squadrons, ROE {scenario.attacker.roe})
Defender: {scenario.defender.house} ({scenario.defender.squadrons.len} squadrons, ROE {scenario.defender.roe})
Expected: {scenario.expectedOutcome}
Seed: {scenario.seed}
"""
