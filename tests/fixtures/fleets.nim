## Test Fleet Fixtures
##
## Pre-built fleets for testing

import ../../src/engine/[ship, fleet, squadron]
import ../../src/common/types/[core, units, combat]

## Basic Fleet Configurations

proc testFleet_SingleScout*(owner: HouseId, location: SystemId): seq[CombatSquadron] =
  ## Single scout squadron
  let scout = newEnhancedShip(ShipClass.Scout, techLevel = 1)
  let squadron = newSquadron(scout, id = "sq-scout-1", owner = owner, location = location)
  result = @[CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Scout,
    targetWeight: 1.0
  )]

proc testFleet_BalancedCapital*(owner: HouseId, location: SystemId, techLevel: int = 1): seq[CombatSquadron] =
  ## Balanced capital fleet: 2 Battleships + 1 Cruiser
  result = @[]
  for i in 1..2:
    let battleship = newEnhancedShip(ShipClass.Battleship, techLevel = techLevel)
    let squadron = newSquadron(battleship, id = $"sq-bs-" & $i, owner = owner, location = location)
    result.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Capital,
      targetWeight: 1.0
    ))

  let cruiser = newEnhancedShip(ShipClass.Cruiser, techLevel = techLevel)
  let squadron = newSquadron(cruiser, id = "sq-ca-1", owner = owner, location = location)
  result.add(CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  ))

proc testFleet_FighterSwarm*(owner: HouseId, location: SystemId): seq[CombatSquadron] =
  ## Fighter swarm: 4 fighter squadrons
  result = @[]
  for i in 1..4:
    let fighter = newEnhancedShip(ShipClass.Fighter, techLevel = 1)
    let squadron = newSquadron(fighter, id = $"sq-ff-" & $i, owner = owner, location = location)
    result.add(CombatSquadron(
      squadron: squadron,
      state: CombatState.Undamaged,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: TargetBucket.Fighter,
      targetWeight: 1.0
    ))

proc testFleet_Dreadnought*(owner: HouseId, location: SystemId, techLevel: int = 3): seq[CombatSquadron] =
  ## Single dreadnought
  let dreadnought = newEnhancedShip(ShipClass.Dreadnought, techLevel = techLevel)
  let squadron = newSquadron(dreadnought, id = "sq-dn-1", owner = owner, location = location)
  result = @[CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  )]

proc testFleet_PlanetBreaker*(owner: HouseId, location: SystemId): seq[CombatSquadron] =
  ## Single planet-breaker for bombardment tests
  let pb = newEnhancedShip(ShipClass.PlanetBreaker, techLevel = 10)
  let squadron = newSquadron(pb, id = "sq-pb-1", owner = owner, location = location)
  result = @[CombatSquadron(
    squadron: squadron,
    state: CombatState.Undamaged,
    damageThisTurn: 0,
    crippleRound: 0,
    bucket: TargetBucket.Capital,
    targetWeight: 1.0
  )]
