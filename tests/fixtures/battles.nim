## Test Battle Fixtures
##
## Pre-configured battle scenarios for regression testing

import ../../src/engine/combat/types
import ../../src/common/types/[core, diplomacy]
import fleets

## Known Edge Cases

proc battle_TechMismatch*(): BattleContext =
  ## Tech 3 vs Tech 0 - should demonstrate tech advantage
  let location: SystemId = 1

  let attackers = testFleet_Dreadnought("house-alpha", location, techLevel = 3)
  let defenders = testFleet_BalancedCapital("house-beta", location, techLevel = 0)

  let attackerTF = TaskForce(
    houseId: "house-alpha",
    squadrons: attackers,
    prestige: 50,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    houseId: "house-beta",
    squadrons: defenders,
    prestige: 50,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  result = BattleContext(
    systemId: location,
    taskForces: @[attackerTF, defenderTF],
    seed: 12345,
    maxRounds: 20
  )

proc battle_FighterVsCapital*(): BattleContext =
  ## Fighter swarm vs capital ships - tactical matchup
  let location: SystemId = 1

  let attackers = testFleet_FighterSwarm("house-alpha", location)
  let defenders = testFleet_BalancedCapital("house-beta", location)

  let attackerTF = TaskForce(
    houseId: "house-alpha",
    squadrons: attackers,
    prestige: 50,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    houseId: "house-beta",
    squadrons: defenders,
    prestige: 50,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  result = BattleContext(
    systemId: location,
    taskForces: @[attackerTF, defenderTF],
    seed: 54321,
    maxRounds: 20
  )

proc battle_ScoutAmbush*(): BattleContext =
  ## Cloaked scout ambush scenario
  let location: SystemId = 1

  let attackers = testFleet_SingleScout("house-alpha", location)
  let defenders = testFleet_BalancedCapital("house-beta", location)

  let attackerTF = TaskForce(
    houseId: "house-alpha",
    squadrons: attackers,
    prestige: 50,
    isCloaked: true,  # Scout is cloaked
    isDefendingHomeworld: false
  )

  let defenderTF = TaskForce(
    houseId: "house-beta",
    squadrons: defenders,
    prestige: 50,
    isCloaked: false,
    isDefendingHomeworld: false
  )

  result = BattleContext(
    systemId: location,
    taskForces: @[attackerTF, defenderTF],
    seed: 99999,
    maxRounds: 20
  )
