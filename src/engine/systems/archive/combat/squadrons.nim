## Helper procs for combat squadrons

proc getCurrentAS*(cs: CombatSquadron): int =
  ## Get current attack strength (reduced if crippled or reserve status)
  ## Per economy.md:3.9 - Reserve fleets have AS reduced by half
  var baseAS: int
  if cs.state == CombatState.Crippled:
    baseAS = cs.squadron.combatStrength() div 2
  elif cs.state == CombatState.Destroyed:
    return 0
  else:
    baseAS = cs.squadron.combatStrength()

  # Apply reserve status penalty (half AS/DS)
  if cs.fleetStatus == FleetStatus.Reserve:
    return baseAS div 2
  else:
    return baseAS

proc getCurrentDS*(cs: CombatSquadron): int =
  ## Get defense strength (doesn't change when crippled, but reduced if reserve)
  ## Per economy.md:3.9 - Reserve fleets have DS reduced by half
  let baseDS = cs.squadron.defenseStrength()

  # Apply reserve status penalty (half AS/DS)
  if cs.fleetStatus == FleetStatus.Reserve:
    return baseDS div 2
  else:
    return baseDS

proc isAlive*(cs: CombatSquadron): bool =
  ## Check if squadron can still fight
  cs.state != CombatState.Destroyed

proc canBeTargeted*(cs: CombatSquadron): bool =
  ## Check if squadron is valid target
  cs.state != CombatState.Destroyed

## CombatFacility helpers

proc getCurrentAS*(cf: CombatFacility): int =
  ## Get current attack strength (reduced if crippled)
  if cf.state == CombatState.Crippled:
    return cf.attackStrength div 2
  elif cf.state == CombatState.Destroyed:
    return 0
  else:
    return cf.attackStrength

proc getCurrentDS*(cf: CombatFacility): int =
  ## Get defense strength (doesn't change when crippled)
  if cf.state == CombatState.Destroyed:
    return 0
  else:
    return cf.defenseStrength

proc isAlive*(cf: CombatFacility): bool =
  ## Check if facility can still fight
  cf.state != CombatState.Destroyed

proc canBeTargeted*(cf: CombatFacility): bool =
  ## Check if facility is valid target
  cf.state != CombatState.Destroyed

## Task Force helpers

proc totalAS*(tf: TaskForce): int =
  ## Calculate total attack strength of Task Force (squadrons + facilities)
  result = 0
  for sq in tf.squadrons:
    result += sq.getCurrentAS()
  for fac in tf.facilities:
    result += fac.getCurrentAS()

proc aliveSquadrons*(tf: TaskForce): seq[CombatSquadron] =
  ## Get all non-destroyed squadrons
  result = @[]
  for sq in tf.squadrons:
    if sq.isAlive():
      result.add(sq)

proc aliveFacilities*(tf: TaskForce): seq[CombatFacility] =
  ## Get all non-destroyed facilities
  result = @[]
  for fac in tf.facilities:
    if fac.isAlive():
      result.add(fac)

proc isEliminated*(tf: TaskForce): bool =
  ## Check if Task Force has no surviving squadrons or facilities
  # Check squadrons
  for sq in tf.squadrons:
    if sq.isAlive():
      return false
  # Check facilities
  for fac in tf.facilities:
    if fac.isAlive():
      return false
  return true

## CER Table lookup (Section 7.3.3)

proc lookupCER*(modifiedRoll: int): float =
  ## Convert modified die roll to effectiveness multiplier
  ## Based on CER Table from Section 7.3.3
  if modifiedRoll <= 2:
    return 0.25
  elif modifiedRoll <= 4:
    return 0.50
  elif modifiedRoll <= 6:
    return 0.75
  else:
    return 1.0

proc isCritical*(naturalRoll: int): bool =
  ## Check if natural roll (before modifiers) is critical hit
  ## Natural 9 = critical hit (Section 7.3.3)
  naturalRoll == 9

## Target bucket classification (Section 7.3.2.2)

proc classifyBucket*(sq: Squadron): TargetBucket =
  ## Determine target priority bucket for squadron
  case sq.flagship.shipClass
  of ShipClass.Raider:
    return TargetBucket.Raider
  of ShipClass.Cruiser, ShipClass.LightCruiser, ShipClass.HeavyCruiser,
     ShipClass.Battlecruiser, ShipClass.Battleship,
     ShipClass.Dreadnought, ShipClass.SuperDreadnought,
     ShipClass.Carrier, ShipClass.SuperCarrier:
    return TargetBucket.Capital
  of ShipClass.Destroyer:
    return TargetBucket.Destroyer
  of ShipClass.Fighter:
    return TargetBucket.Fighter
  else:
    # Default to capital for unknown types
    # Note: Starbases (TargetBucket.Starbase) assigned separately via colony facilities
    return TargetBucket.Capital

proc baseWeight*(bucket: TargetBucket): float =
  ## Get base targeting weight for bucket (Section 7.3.2.2)
  case bucket
  of TargetBucket.Raider: 1.0
  of TargetBucket.Capital: 2.0
  of TargetBucket.Destroyer: 3.0
  of TargetBucket.Fighter: 4.0
  of TargetBucket.Starbase: 5.0

proc calculateTargetWeight*(cs: CombatSquadron): float =
  ## Calculate weighted random selection weight
  ## Crippled units get 2x weight (Section 7.3.2.5)
  let base = cs.bucket.baseWeight()
  if cs.state == CombatState.Crippled:
    return base * 2.0
  else:
    return base
