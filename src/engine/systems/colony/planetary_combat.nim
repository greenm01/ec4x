## Planetary Combat Operations - Theater 3 (Bombardment, Invasion, Blitz)
##
## Per docs/specs/07-combat.md Section 7.1.1:
## "Planetary Combat (Third Theater): Bombard planetary defenses and invade
## the surface after securing orbit."
##
## Requires orbital supremacy from combat/battles.nim before execution.
## Implements three types of planetary assault:
## - Bombardment: Destroy shields, batteries, and infrastructure
## - Invasion: Deploy marines to capture colony
## - Blitz: Fast insertion variant (marines land under fire)

import std/[tables, options, sequtils, hashes, math, random, strformat]
import ../../common/[types/core, types/combat, types/units, logger as common_logger]
import ../../types/[game_state, command, fleet, colony, squadron, ship, house]
import ../../state/[entity_manager, iterators]
import ../index_maintenance
import ../combat/ground  # Combat mechanics (conductBombardment, conductInvasion, conductBlitz)
import ../economy/[types as econ_types, facility_damage]
import ../prestige
import ../../config/[prestige_multiplier, prestige_config, facilities_config]
import ../diplomacy/[types as dip_types, engine as dip_engine]
import ../intelligence/diplomatic_intel
import ../combat/types  # Common resolution types
import ../fleet/orders  # For findClosestOwnedColony, resolveMovementOrder
import ../../event_factory/init as event_factory
import ../intelligence/[types as intel_types, combat_intel]

# ============================================================================
# HELPER FUNCTIONS - Combat Support
# ============================================================================

proc getTargetBucket(shipClass: ShipClass): TargetBucket =
  ## Map ship class to targeting bucket for combat resolution
  case shipClass
  of ShipClass.Fighter, ShipClass.Interceptor: TargetBucket.Fighter
  of ShipClass.Raider: TargetBucket.Raider
  else: TargetBucket.Capital

# ============================================================================
# BOMBARDMENT RESOLUTION
# ============================================================================

proc resolveBombardment*(state: var GameState, houseId: HouseId, order: FleetOrder,
                       events: var seq[GameEvent]) =
  ## Process planetary bombardment order (operations.md:7.5)
  ## Phase 2 of planetary combat - requires orbital supremacy
  ## Attacks planetary shields, ground batteries, and infrastructure

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Bombardment failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Bombardment failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Bombardment failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Bombard",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  # Fleet now uses Squadrons - convert to CombatSquadrons
  var combatSquadrons: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,  # Pass fleet status for reserve AS/DS penalty
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    combatSquadrons.add(combatSq)

  # Get colony's planetary defense
  let colonyOpt = state.colonies.entities.getEntity(targetId)
  if colonyOpt.isNone:
    logWarn("Combat", "Bombardment failed - colony disappeared during validation",
            "systemId=", $targetId)
    return
  let colony = colonyOpt.get()

  # Build full PlanetaryDefense from colony data
  var defense = PlanetaryDefense()

  # Shields: Convert colony shield level to ShieldLevel object
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,  # Convert d20 roll to probability
      blockPercentage: blockPct
    ))
  else:
    defense.shields = none(ShieldLevel)

  # Ground Batteries: Create GroundUnit objects from colony count
  defense.groundBatteries = @[]
  let houseOpt = state.houses.entities.getEntity(colony.owner)
  if houseOpt.isNone:
    logWarn("Combat", "Bombardment failed - house not found", "houseId=", $colony.owner)
    return
  let ownerCSTLevel = houseOpt.get().techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel  # Use colony owner's actual CST level
    )
    defense.groundBatteries.add(battery)

  # Ground Forces: Create GroundUnit objects from armies and marines
  defense.groundForces = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD" & $i,
      owner = colony.owner
    )
    defense.groundForces.add(marine)

  # Spaceports: Check if colony has any operational spaceports
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed for bombardment (turn + target system)
  let bombardmentSeed = hash((state.turn, targetId)).int64

  # Conduct bombardment
  let result = conductBombardment(combatSquadrons, defense, seed = bombardmentSeed, maxRounds = 3)

  # Apply damage to colony
  var updatedColony = colony

  # Infrastructure damage from bombardment result
  let infrastructureLoss = result.infrastructureDamage div 10  # Convert IU damage to infrastructure levels
  updatedColony.infrastructure -= infrastructureLoss
  if updatedColony.infrastructure < 0:
    updatedColony.infrastructure = 0

  # Industrial capacity damage (IU)
  updatedColony.industrial.units -= result.infrastructureDamage
  if updatedColony.industrial.units < 0:
    updatedColony.industrial.units = 0

  # Population casualties (PU)
  # result.populationDamage is in PU, convert to souls (1 PU = 1M souls)
  let soulsCasualties = result.populationDamage * 1_000_000
  updatedColony.souls -= soulsCasualties
  if updatedColony.souls < 0:
    updatedColony.souls = 0
  # Update display fields
  updatedColony.population = updatedColony.souls div 1_000_000
  updatedColony.populationUnits = updatedColony.population

  # Apply battery destruction from bombardment
  updatedColony.groundBatteries -= result.batteriesDestroyed
  if updatedColony.groundBatteries < 0:
    updatedColony.groundBatteries = 0

  # Ships-in-dock destruction (economy.md:5.0)
  # Bombardment only affects SPACEPORT docks, not shipyard docks
  var shipsDestroyedInDock = false
  if infrastructureLoss > 0 and updatedColony.underConstruction.isSome:
    let project = updatedColony.underConstruction.get()
    if project.projectType == econ_types.ConstructionType.Ship:
      # Only destroy if in spaceport dock (bombardment doesn't affect shipyard docks)
      if project.facilityType.isSome and project.facilityType.get() == econ_types.FacilityType.Spaceport:
        updatedColony.underConstruction = none(econ_types.ConstructionProject)
        shipsDestroyedInDock = true
        logCombat("Ship under construction destroyed in bombardment (spaceport dock)",
                  "systemId=", $targetId)

  state.colonies.entities.updateEntity(targetId, updatedColony)

  logCombat("Bombardment complete",
            "systemId=", $targetId,
            " infrastructure=", $infrastructureLoss,
            " IU=", $result.infrastructureDamage,
            " casualties=", $result.populationDamage, " PU")

  # Generate intelligence reports for both attacker and defender
  let groundForcesKilled = result.populationDamage  # Population damage represents casualties
  combat_intel.generateBombardmentIntelligence(
    state,
    targetId,
    houseId,  # Attacking house
    order.fleetId,
    colony.owner,  # Defending house
    infrastructureLoss,
    result.infrastructureDamage,  # IU damage
    defense.shields.isSome,  # Were shields active?
    result.batteriesDestroyed,
    groundForcesKilled,
    fleet.squadrons.countIt(it.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary})  # Invasion threat assessment (count spacelift squadrons)
  )

  # Generate bombardment event with COMPLETE tactical data (Phase 7a fix)
  # Attacker casualties: squadronsDestroyed + squadronsCrippled from result
  let attackerCasualties = result.squadronsDestroyed + result.squadronsCrippled
  let facilitiesDestroyed = if shipsDestroyedInDock: 1 else: 0

  events.add(event_factory.bombardmentRoundCompleted(
    round = result.roundsCompleted,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    batteriesDestroyed = result.batteriesDestroyed,
    batteriesCrippled = result.batteriesCrippled,
    shieldBlocked = result.shieldBlocked,
    groundForcesDamaged = 0,  # Not tracked separately, part of populationDamage
    infrastructureDamage = result.infrastructureDamage,
    populationKilled = result.populationDamage,
    facilitiesDestroyed = facilitiesDestroyed,
    attackerCasualties = attackerCasualties
  ))

  # Generate OrderCompleted event
  events.add(event_factory.orderCompleted(
    houseId,
    order.fleetId,
    "Bombard",
    details = &"destroyed {infrastructureLoss} infrastructure at {targetId}",
    systemId = some(targetId)
  ))

# ============================================================================
# HELPER FUNCTIONS - Ground Defense Detection
# ============================================================================

proc isColonyUndefended(colony: Colony): bool =
  ## Check if colony lacks any ground defense
  ## Returns true if colony has NO armies, marines, or ground batteries
  ##
  ## NOTE: Planetary shields alone don't count as "defended"
  ## Shields slow invasions but don't stop them - troops are required
  result = colony.armies == 0 and
           colony.marines == 0 and
           colony.groundBatteries == 0

# ============================================================================
# INVASION RESOLUTION
# ============================================================================

proc resolveInvasion*(state: var GameState, houseId: HouseId, order: FleetOrder,
                    events: var seq[GameEvent]) =
  ## Process planetary invasion order (operations.md:7.6)
  ## Phase 3 of planetary combat - requires all ground batteries destroyed
  ## Marines attack ground forces to capture colony

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Invasion failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Invasion failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Invasion failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  let colonyOpt = state.colonies.entities.getEntity(targetId)
  if colonyOpt.isNone:
    logWarn("Combat", "Invasion failed - colony disappeared",
            "systemId=", $targetId)
    return
  let colony = colonyOpt.get()

  # Check if colony belongs to attacker (can't invade your own colony)
  if colony.owner == houseId:
    logWarn("Combat", "Invasion failed - cannot invade your own colony",
            "houseId=", $houseId, " systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "target is now friendly (cannot invade own colony)",
      systemId = some(targetId)
    ))
    return

  # Build attacking ground forces from spacelift squadrons (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for squadron in fleet.squadrons:
    if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
          for i in 0 ..< cargo.quantity:
            let marine = createMarine(
              id = $houseId & "_MD_" & $targetId & "_" & $i,
              owner = houseId
            )
            attackingForces.add(marine)

  if attackingForces.len == 0:
    logWarn("Combat", "Invasion failed - no marines in fleet",
            "fleetId=", $order.fleetId)
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (must be destroyed for invasion to proceed)
  let houseOpt = state.houses.entities.getEntity(colony.owner)
  if houseOpt.isNone:
    logWarn("Combat", "Invasion failed - house not found", "houseId=", $colony.owner)
    return
  let ownerCSTLevel = houseOpt.get().techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Check prerequisite: all ground batteries must be destroyed
  # Per operations.md:7.6, invasion requires bombardment to destroy ground batteries first
  if defense.groundBatteries.len > 0:
    logWarn("Combat", "Invasion failed - ground batteries still operational (bombardment required first)",
            "systemId=", $targetId, " batteries=", $defense.groundBatteries.len)
    return

  # Ground forces already added above
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let invasionSeed = hash((state.turn, targetId, houseId)).int64

  # Generate InvasionBegan event (Phase 7a)
  events.add(event_factory.invasionBegan(
    fleetId = order.fleetId,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    marinesLanding = attackingForces.len
  ))

  # Conduct invasion
  let result = conductInvasion(attackingForces, defendingForces, defense, invasionSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Invasion succeeded - colony captured
    logCombat("Invasion SUCCESS - colony captured",
              "attacker=", $houseId, " defender=", $colony.owner,
              " systemId=", $targetId)

    # Transfer ownership
    updatedColony.owner = houseId

    # Apply infrastructure damage (50% destroyed per operations.md:7.6.2)
    updatedColony.infrastructure = updatedColony.infrastructure div 2

    # Apply industrial capacity damage (IU lost from invasion)
    updatedColony.industrial.units -= result.infrastructureDestroyed
    if updatedColony.industrial.units < 0:
      updatedColony.industrial.units = 0

    # Shields and spaceports destroyed on landing (per spec)
    updatedColony.planetaryShieldLevel = 0
    updatedColony.spaceports = @[]

    # Destroy ships under construction/repair in spaceport docks (per economy.md:5.0)
    handleFacilityDestruction(updatedColony, econ_types.FacilityType.Spaceport)

    # Update ground forces
    # Attacker marines that survived become garrison
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0  # Defender armies all destroyed/disbanded

    # Unload marines from spacelift squadrons (they've landed)
    let fleetOpt = state.fleets.entities.getEntity(order.fleetId)
    if fleetOpt.isSome:
      var updatedFleet = fleetOpt.get()
      for squadron in updatedFleet.squadrons.mitems:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Marines:
              # Clear the cargo
              squadron.flagship.cargo = some(ShipCargo(
                cargoType: CargoType.None,
                quantity: 0,
                capacity: cargo.capacity
              ))
      state.fleets.entities.updateEntity(order.fleetId, updatedFleet)

    # Check if colony was undefended (BEFORE taking ownership)
    let wasUndefended = isColonyUndefended(colony)

    # Prestige changes
    let attackerPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.ColonySeized))
    let invasionEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      attackerPrestige,
      "Captured colony at " & $targetId & " via invasion"
    )
    applyPrestigeEvent(state, houseId, invasionEvent)
    logCombat("Invasion prestige awarded",
              "house=", $houseId, " prestige=", $attackerPrestige)

    # Defender loses prestige for colony loss (with undefended penalty if applicable)
    var defenderPenalty = -attackerPrestige  # Base: equal but opposite

    # Apply +50% penalty for losing undefended colony
    if wasUndefended:
      let undefendedMultiplier = globalPrestigeConfig.military.undefended_colony_penalty_multiplier
      defenderPenalty = int(float(defenderPenalty) * undefendedMultiplier)
      logCombat("Undefended colony penalty applied",
                "house=", $colony.owner, " multiplier=", $undefendedMultiplier,
                " total_penalty=", $defenderPenalty,
                " additional_penalty=", $int(abs(defenderPenalty) - abs(-attackerPrestige)))

    let colonyLossEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      defenderPenalty,
      "Lost colony at " & $targetId & " to invasion" & (if wasUndefended: " (undefended)" else: "")
    )
    applyPrestigeEvent(state, colony.owner, colonyLossEvent)
    logCombat("Colony loss prestige penalty",
              "house=", $colony.owner, " prestige=", $defenderPenalty)

    # Generate event
    events.add(event_factory.colonyCaptured(
      houseId,
      colony.owner,
      targetId,
      "Invasion"
    ))

    # Generate OrderCompleted event for successful invasion
    events.add(event_factory.orderCompleted(
      houseId,
      order.fleetId,
      "Invade",
      details = &"captured system {targetId}",
      systemId = some(targetId)
    ))
  else:
    # Invasion failed - ALL attacking marines destroyed (no retreat from ground combat)
    logCombat("Invasion FAILED - attacker repelled",
              "defender=", $colony.owner, " attacker=", $houseId,
              " systemId=", $targetId)
    logCombat("All attacking marines destroyed",
              "marines=", $attackingForces.len)

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    # Simplified: assume casualties distributed evenly between armies and marines
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # All attacker marines destroyed - unload ALL marines from spacelift squadrons
    # Marines cannot retreat once they've landed on the planet
    let fleetOpt = state.fleets.entities.getEntity(order.fleetId)
    if fleetOpt.isSome:
      var updatedFleet = fleetOpt.get()
      for squadron in updatedFleet.squadrons.mitems:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Marines:
              # Clear the cargo (marines destroyed)
              squadron.flagship.cargo = some(ShipCargo(
                cargoType: CargoType.None,
                quantity: 0,
                capacity: cargo.capacity
              ))
      state.fleets.entities.updateEntity(order.fleetId, updatedFleet)

    # Generate event
    events.add(event_factory.invasionRepelled(
      colony.owner,
      targetId,
      houseId
    ))

    # Generate OrderFailed event for failed invasion
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Invade",
      reason = "invasion repelled - all marines destroyed",
      systemId = some(targetId)
    ))

  state.colonies.entities.updateEntity(targetId, updatedColony)

  # INTELLIGENCE: Generate invasion reports for both houses (after state updates)
  combat_intel.generateInvasionIntelligence(
    state, targetId, houseId, colony.owner,
    attackingForces.len,
    colony.armies,
    colony.marines,
    result.success,
    result.attackerCasualties.len,
    result.defenderCasualties.len,
    result.infrastructureDestroyed
  )

proc resolveBlitz*(state: var GameState, houseId: HouseId, order: FleetOrder,
                 events: var seq[GameEvent]) =
  ## Process planetary blitz order (operations.md:7.6.2)
  ## Fast insertion variant - seizes assets intact but marines get 0.5x AS penalty
  ## Transports vulnerable to ground batteries during insertion

  if order.targetSystem.isNone:
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "no target system specified",
      systemId = none(SystemId)
    ))
    return

  let targetId = order.targetSystem.get()

  # Validate fleet exists and is at target
  let fleetOpt = state.getFleet(order.fleetId)
  if fleetOpt.isNone:
    logWarn("Combat", "Blitz failed - fleet not found",
            "fleetId=", $order.fleetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "fleet destroyed",
      systemId = some(targetId)
    ))
    return

  let fleet = fleetOpt.get()
  if fleet.location != targetId:
    logWarn("Combat", "Blitz failed - fleet not at target system",
            "fleetId=", $order.fleetId, " location=", $fleet.location,
            " target=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "fleet not at target system",
      systemId = some(targetId)
    ))
    return

  # Validate target colony exists
  if targetId notin state.colonies:
    logWarn("Combat", "Blitz failed - no colony at target",
            "systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "target colony no longer exists",
      systemId = some(targetId)
    ))
    return

  let colonyOpt = state.colonies.entities.getEntity(targetId)
  if colonyOpt.isNone:
    logWarn("Combat", "Blitz failed - colony disappeared",
            "systemId=", $targetId)
    return
  let colony = colonyOpt.get()

  # Check if colony belongs to attacker
  if colony.owner == houseId:
    logWarn("Combat", "Blitz failed - cannot blitz your own colony",
            "houseId=", $houseId, " systemId=", $targetId)
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "target is now friendly (cannot blitz own colony)",
      systemId = some(targetId)
    ))
    return

  # Build attacking fleet (squadrons needed for blitz vs ground batteries)
  var attackingFleet: seq[CombatSquadron] = @[]
  for squadron in fleet.squadrons:
    let combatSq = CombatSquadron(
      squadron: squadron,
      state: if squadron.flagship.isCrippled: CombatState.Crippled else: CombatState.Undamaged,
      fleetStatus: fleet.status,
      damageThisTurn: 0,
      crippleRound: 0,
      bucket: getTargetBucket(squadron.flagship.shipClass),
      targetWeight: 1.0
    )
    attackingFleet.add(combatSq)

  # Build attacking ground forces from spacelift squadrons (marines only)
  var attackingForces: seq[GroundUnit] = @[]
  for squadron in fleet.squadrons:
    if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
      if squadron.flagship.cargo.isSome:
        let cargo = squadron.flagship.cargo.get()
        if cargo.cargoType == CargoType.Marines and cargo.quantity > 0:
          for i in 0 ..< cargo.quantity:
            let marine = createMarine(
              id = $houseId & "_MD_" & $targetId & "_" & $i,
              owner = houseId
            )
            attackingForces.add(marine)

  if attackingForces.len == 0:
    logWarn("Combat", "Blitz failed - no marines in fleet",
            "fleetId=", $order.fleetId)
    return

  # Build defending ground forces
  var defendingForces: seq[GroundUnit] = @[]
  for i in 0 ..< colony.armies:
    let army = createArmy(
      id = $targetId & "_AA_" & $i,
      owner = colony.owner
    )
    defendingForces.add(army)

  for i in 0 ..< colony.marines:
    let marine = createMarine(
      id = $targetId & "_MD_" & $i,
      owner = colony.owner
    )
    defendingForces.add(marine)

  # Build planetary defense
  var defense = PlanetaryDefense()

  # Shields
  if colony.planetaryShieldLevel > 0:
    let (rollNeeded, blockPct) = getShieldData(colony.planetaryShieldLevel)
    defense.shields = some(ShieldLevel(
      level: colony.planetaryShieldLevel,
      blockChance: float(rollNeeded) / 20.0,
      blockPercentage: blockPct
    ))

  # Ground Batteries (blitz fights through them unlike invasion)
  let houseOpt = state.houses.entities.getEntity(colony.owner)
  if houseOpt.isNone:
    logWarn("Combat", "Blitz failed - house not found", "houseId=", $colony.owner)
    return
  let ownerCSTLevel = houseOpt.get().techTree.levels.constructionTech
  for i in 0 ..< colony.groundBatteries:
    let battery = createGroundBattery(
      id = $targetId & "_GB" & $i,
      owner = colony.owner,
      techLevel = ownerCSTLevel
    )
    defense.groundBatteries.add(battery)

  # Ground forces
  defense.groundForces = defendingForces

  # Spaceport
  defense.spaceport = colony.spaceports.len > 0

  # Generate deterministic seed
  let blitzSeed = hash((state.turn, targetId, houseId, "blitz")).int64

  # Generate BlitzBegan event (Phase 7a)
  # Blitz: marines get 0.5x AS penalty, transports vulnerable during insertion
  events.add(event_factory.blitzBegan(
    fleetId = order.fleetId,
    attackingHouse = houseId,
    defendingHouse = colony.owner,
    systemId = targetId,
    marinesLanding = attackingForces.len,
    transportsVulnerable = true,
    marineAsPenalty = 0.5
  ))

  # Conduct blitz
  let result = conductBlitz(attackingFleet, attackingForces, defense, blitzSeed)

  # Apply results
  var updatedColony = colony

  if result.success:
    # Blitz succeeded - colony captured with assets intact
    logCombat("Blitz SUCCESS - colony captured with assets seized",
              "attacker=", $houseId, " defender=", $colony.owner,
              " systemId=", $targetId)

    # Transfer ownership
    updatedColony.owner = houseId

    # NO infrastructure damage on blitz (assets seized intact per operations.md:7.6.2)
    # Shields, spaceports, ground batteries all seized intact

    # Update ground forces
    let survivingMarines = attackingForces.len - result.attackerCasualties.len
    updatedColony.marines = survivingMarines
    updatedColony.armies = 0

    # Unload marines from auxiliary squadrons
    let fleetOpt = state.fleets.entities.getEntity(order.fleetId)
    if fleetOpt.isSome:
      var updatedFleet = fleetOpt.get()
      for squadron in updatedFleet.squadrons.mitems:
        if squadron.squadronType == SquadronType.Auxiliary:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Marines:
              # Clear marines cargo
              squadron.flagship.cargo = some(ShipCargo(
                cargoType: CargoType.None,
                quantity: 0,
                capacity: cargo.capacity
              ))
      state.fleets.entities.updateEntity(order.fleetId, updatedFleet)

    # Check if colony was undefended (BEFORE taking ownership)
    let wasUndefended = isColonyUndefended(colony)

    # Prestige changes (blitz gets same prestige as invasion)
    let attackerPrestige = applyMultiplier(getPrestigeValue(PrestigeSource.ColonySeized))
    let blitzEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      attackerPrestige,
      "Captured colony at " & $targetId & " via blitz"
    )
    applyPrestigeEvent(state, houseId, blitzEvent)
    logCombat("Blitz prestige awarded",
              "house=", $houseId, " prestige=", $attackerPrestige)

    # Defender loses prestige for colony loss (with undefended penalty if applicable)
    var defenderPenalty = -attackerPrestige  # Base: equal but opposite

    # Apply +50% penalty for losing undefended colony
    if wasUndefended:
      let undefendedMultiplier = globalPrestigeConfig.military.undefended_colony_penalty_multiplier
      defenderPenalty = int(float(defenderPenalty) * undefendedMultiplier)
      logCombat("Undefended colony penalty applied (blitz)",
                "house=", $colony.owner, " multiplier=", $undefendedMultiplier,
                " total_penalty=", $defenderPenalty,
                " additional_penalty=", $int(abs(defenderPenalty) - abs(-attackerPrestige)))

    let colonyLossBlitzEvent = createPrestigeEvent(
      PrestigeSource.ColonySeized,
      defenderPenalty,
      "Lost colony at " & $targetId & " to blitz" & (if wasUndefended: " (undefended)" else: "")
    )
    applyPrestigeEvent(state, colony.owner, colonyLossBlitzEvent)
    logCombat("Colony loss prestige penalty",
              "house=", $colony.owner, " prestige=", $defenderPenalty)

    # Generate event
    events.add(event_factory.colonyCaptured(
      houseId,
      colony.owner,
      targetId,
      "Blitz"
    ))

    # Generate OrderCompleted event for successful blitz
    events.add(event_factory.orderCompleted(
      houseId,
      order.fleetId,
      "Blitz",
      details = &"captured system {targetId} via blitz",
      systemId = some(targetId)
    ))
  else:
    # Blitz failed - ALL attacking marines destroyed (no retreat from ground combat)
    logCombat("Blitz FAILED - attacker repelled",
              "defender=", $colony.owner, " attacker=", $houseId,
              " systemId=", $targetId)
    logCombat("All attacking marines destroyed",
              "marines=", $attackingForces.len)

    # Update defender ground forces
    let survivingDefenders = defendingForces.len - result.defenderCasualties.len
    let totalDefenders = colony.armies + colony.marines
    if totalDefenders > 0:
      let armyFraction = float(colony.armies) / float(totalDefenders)
      updatedColony.armies = int(float(survivingDefenders) * armyFraction)
      updatedColony.marines = survivingDefenders - updatedColony.armies

    # Update ground batteries (destroyed during Phase 1 bombardment)
    updatedColony.groundBatteries -= result.batteriesDestroyed
    if updatedColony.groundBatteries < 0:
      updatedColony.groundBatteries = 0

    # All attacker marines destroyed - unload ALL marines from spacelift squadrons
    # Marines cannot retreat once they've landed on the planet
    let fleetOpt = state.fleets.entities.getEntity(order.fleetId)
    if fleetOpt.isSome:
      var updatedFleet = fleetOpt.get()
      for squadron in updatedFleet.squadrons.mitems:
        if squadron.squadronType in {SquadronType.Expansion, SquadronType.Auxiliary}:
          if squadron.flagship.cargo.isSome:
            let cargo = squadron.flagship.cargo.get()
            if cargo.cargoType == CargoType.Marines:
              # Clear the cargo (marines destroyed)
              squadron.flagship.cargo = some(ShipCargo(
                cargoType: CargoType.None,
                quantity: 0,
                capacity: cargo.capacity
              ))
      state.fleets.entities.updateEntity(order.fleetId, updatedFleet)

    # Generate event
    events.add(event_factory.invasionRepelled(
      colony.owner,
      targetId,
      houseId
    ))

    # Generate OrderFailed event for failed blitz
    events.add(event_factory.orderFailed(
      houseId,
      order.fleetId,
      "Blitz",
      reason = "blitz repelled - all marines destroyed",
      systemId = some(targetId)
    ))

  state.colonies.entities.updateEntity(targetId, updatedColony)

  # INTELLIGENCE: Generate blitz reports for both houses (after state updates)
  combat_intel.generateBlitzIntelligence(
    state, targetId, houseId, colony.owner,
    attackingForces.len,
    colony.armies,
    colony.marines,
    result.success,
    result.attackerCasualties.len,
    result.defenderCasualties.len,
    result.batteriesDestroyed
  )
