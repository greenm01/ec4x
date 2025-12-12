## Military Event Factory
## Events for combat, invasions, and fleet operations
##
## DRY Principle: Single source of truth for military event creation
## DoD Principle: Data (GameEvent) separated from creation logic

import std/[options, strformat]
import ../../../common/types/core
import ../types as event_types # Standardized alias for GameEvent types

# Export event_types alias for GameEvent types
export event_types

proc colonyEstablished*(
  houseId: HouseId,
  systemId: SystemId,
  prestigeAwarded: int = 0
): event_types.GameEvent =
  ## Create event for successful colonization
  let desc = if prestigeAwarded > 0:
    &"Colony established at system {systemId} (+{prestigeAwarded} prestige)"
  else:
    &"Colony established at system {systemId}"
  event_types.GameEvent(
    eventType: event_types.GameEventType.ColonyEstablished, # Specific eventType
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: desc,
    systemId: some(systemId),
    colonyEventType: some("Established") # Specific detail for case branch (redundant but for clarity)
  )

proc systemCaptured*(
  houseId: HouseId,
  systemId: SystemId,
  previousOwner: HouseId
): event_types.GameEvent =
  ## Create event for system capture via invasion
  event_types.GameEvent(
    eventType: event_types.GameEventType.SystemCaptured, # Specific eventType
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Captured system {systemId} from {previousOwner}",
    systemId: some(systemId),
    newOwner: some(houseId),
    oldOwner: some(previousOwner)
  )

proc battle*(
  houseId: HouseId,
  systemId: SystemId,
  description: string
): event_types.GameEvent =
  ## Create generic battle event (CombatResult will be used for specific outcomes)
  event_types.GameEvent(
    eventType: event_types.GameEventType.General, # Use General for generic message
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: description,
    systemId: some(systemId),
    message: description # Use message field for General kind
  )

proc fleetDestroyed*(
  houseId: HouseId,
  fleetId: FleetId,
  systemId: SystemId,
  destroyedBy: HouseId
): event_types.GameEvent =
  ## Create event for fleet destruction
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetDestroyed, # Specific eventType
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Fleet {fleetId} destroyed by {destroyedBy} at system " &
                  &"{systemId}",
    systemId: some(systemId),
    fleetId: some(fleetId),
    fleetEventType: some("Destroyed") # Specific detail for case branch (redundant but for clarity)
  )

proc invasionRepelled*(
  houseId: HouseId,
  systemId: SystemId,
  attacker: HouseId
): event_types.GameEvent =
  ## Create event for successful invasion defense
  event_types.GameEvent(
    eventType: event_types.GameEventType.InvasionRepelled, # Specific eventType
    turn: 0, # Will be set by event dispatcher
    houseId: some(houseId),
    description: &"Repelled invasion by {attacker} at system {systemId}",
    systemId: some(systemId),
    attackingHouseId: some(attacker),
    defendingHouseId: some(houseId),
    outcome: some("Defeat") # Attacker defeated
  )

proc bombardment*(
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  systemId: SystemId,
  infrastructureDamage: int,
  populationKilled: int,
  facilitiesDestroyed: int
): event_types.GameEvent =
  ## Create event for planetary bombardment
  event_types.GameEvent(
    eventType: event_types.GameEventType.Bombardment,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Bombarded system {systemId} held by {defendingHouse}: " &
                 &"{infrastructureDamage} IU damaged, {populationKilled} PU " &
                 &"killed",
    systemId: some(systemId),
    message: &"Infrastructure: {infrastructureDamage} IU, Population: " &
             &"{populationKilled} PU, Facilities: {facilitiesDestroyed}"
  )

proc colonyCaptured*(
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  systemId: SystemId,
  captureMethod: string  # "Invasion" or "Blitz"
): event_types.GameEvent =
  ## Create event for colony capture via ground assault
  event_types.GameEvent(
    eventType: event_types.GameEventType.ColonyCaptured,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Captured colony at {systemId} from {defendingHouse} " &
                 &"via {captureMethod}",
    systemId: some(systemId),
    attackingHouseId: some(attackingHouse),
    defendingHouseId: some(defendingHouse),
    newOwner: some(attackingHouse),
    outcome: some(captureMethod)
  )

proc battleOccurred*(
  systemId: SystemId,
  attackers: seq[HouseId],
  defenders: seq[HouseId],
  outcome: string  # "Decisive", "Stalemate", etc.
): event_types.GameEvent =
  ## Create event for battle between multiple houses (neutral observer)
  ## Used for intelligence reports when house observes combat but doesn't
  ## participate
  let housesInvolved = attackers & defenders
  event_types.GameEvent(
    eventType: event_types.GameEventType.BattleOccurred,
    turn: 0,
    houseId: if attackers.len > 0: some(attackers[0]) else: none(HouseId),
    description: &"Battle at system {systemId} between " &
                 &"{attackers.len} attacker(s) and {defenders.len} " &
                 &"defender(s)",
    systemId: some(systemId),
    message: &"Outcome: {outcome}, Houses involved: {housesInvolved.len}"
  )

# =============================================================================
# Combat Narrative Events (Phase 7a)
# =============================================================================

# -----------------------------------------------------------------------------
# Theater/Phase Events
# -----------------------------------------------------------------------------

proc combatTheaterBegan*(
  theater: string,  # "SpaceCombat", "OrbitalCombat", "PlanetaryCombat"
  systemId: SystemId,
  attackers: seq[HouseId],
  defenders: seq[HouseId],
  roundNumber: int
): event_types.GameEvent =
  ## Create event for combat theater beginning
  event_types.GameEvent(
    eventType: event_types.GameEventType.CombatTheaterBegan,
    turn: 0,
    houseId: if attackers.len > 0: some(attackers[0]) else: none(HouseId),
    description: &"{theater} began at system {systemId} (round {roundNumber})",
    systemId: some(systemId),
    theater: some(theater),
    attackers: some(attackers),
    defenders: some(defenders),
    roundNumber: some(roundNumber),
    casualties: some(newSeq[HouseId]())  # No casualties yet
  )

proc combatTheaterCompleted*(
  theater: string,
  systemId: SystemId,
  victor: Option[HouseId],
  roundNumber: int,
  casualties: seq[HouseId]
): event_types.GameEvent =
  ## Create event for combat theater completion
  let victorDesc = if victor.isSome():
    &"Victor: {victor.get()}"
  else:
    "No victor (stalemate or mutual annihilation)"

  event_types.GameEvent(
    eventType: event_types.GameEventType.CombatTheaterCompleted,
    turn: 0,
    houseId: victor,
    description: &"{theater} completed at system {systemId}: {victorDesc}",
    systemId: some(systemId),
    theater: some(theater),
    attackers: none(seq[HouseId]),  # Not tracked at completion
    defenders: none(seq[HouseId]),
    roundNumber: some(roundNumber),
    casualties: some(casualties)
  )

proc combatPhaseBegan*(
  phase: string,  # "RaiderAmbush", "FighterIntercept", "CapitalEngagement"
  systemId: SystemId,
  roundNumber: int
): event_types.GameEvent =
  ## Create event for combat sub-phase beginning
  event_types.GameEvent(
    eventType: event_types.GameEventType.CombatPhaseBegan,
    turn: 0,
    houseId: none(HouseId),  # Phase affects all houses
    description: &"{phase} phase began at system {systemId} (round " &
                 &"{roundNumber})",
    systemId: some(systemId),
    phase: some(phase),
    roundNumberPhase: some(roundNumber),
    phaseRounds: none(int),  # Not known yet
    phaseCasualties: some(newSeq[HouseId]())  # No casualties yet
  )

proc combatPhaseCompleted*(
  phase: string,
  systemId: SystemId,
  roundNumber: int,
  phaseRounds: int,
  casualties: seq[HouseId]
): event_types.GameEvent =
  ## Create event for combat sub-phase completion
  event_types.GameEvent(
    eventType: event_types.GameEventType.CombatPhaseCompleted,
    turn: 0,
    houseId: none(HouseId),
    description: &"{phase} phase completed at system {systemId} " &
                 &"({phaseRounds} rounds, {casualties.len} houses with " &
                 &"casualties)",
    systemId: some(systemId),
    phase: some(phase),
    roundNumberPhase: some(roundNumber),
    phaseRounds: some(phaseRounds),
    phaseCasualties: some(casualties)
  )

# -----------------------------------------------------------------------------
# Detection & Stealth Events
# -----------------------------------------------------------------------------

proc raiderDetected*(
  raiderFleetId: FleetId,
  raiderHouse: HouseId,
  detectorHouse: HouseId,
  detectorType: string,  # "Scout" or "Starbase"
  systemId: SystemId,
  eliRoll: int,
  clkRoll: int,
  meshBonus: int = 0
): event_types.GameEvent =
  ## Create event for raider detection
  event_types.GameEvent(
    eventType: event_types.GameEventType.RaiderDetected,
    turn: 0,
    houseId: some(raiderHouse),
    description: &"Raider fleet {raiderFleetId} detected by {detectorHouse} " &
                 &"{detectorType} at system {systemId} (ELI {eliRoll} vs CLK " &
                 &"{clkRoll})",
    systemId: some(systemId),
    sourceHouseId: some(detectorHouse),
    targetHouseId: some(raiderHouse),
    raiderFleetId: some(raiderFleetId),
    detectorHouse: some(detectorHouse),
    detectorType: some(detectorType),
    eliRoll: some(eliRoll),
    clkRoll: some(clkRoll),
    meshBonus: some(meshBonus)
  )

proc raiderAmbush*(
  raiderFleetId: FleetId,
  raiderHouse: HouseId,
  targetHouse: HouseId,
  systemId: SystemId,
  ambushBonus: int = 4  # +4 CER for ambush
): event_types.GameEvent =
  ## Create event for raider ambush activation
  event_types.GameEvent(
    eventType: event_types.GameEventType.RaiderAmbush,
    turn: 0,
    houseId: some(raiderHouse),
    description: &"Raider fleet {raiderFleetId} ambushed {targetHouse} at " &
                 &"system {systemId} (+{ambushBonus} CER bonus)",
    systemId: some(systemId),
    sourceHouseId: some(raiderHouse),
    targetHouseId: some(targetHouse),
    ambushFleetId: some(raiderFleetId),
    ambushTargetHouse: some(targetHouse),
    ambushBonus: some(ambushBonus)
  )

proc eliMeshNetworkFormed*(
  house: HouseId,
  systemId: SystemId,
  scoutCount: int,
  meshBonus: int  # +1, +2, or +3
): event_types.GameEvent =
  ## Create event for ELI mesh network formation
  event_types.GameEvent(
    eventType: event_types.GameEventType.EliMeshNetworkFormed,
    turn: 0,
    houseId: some(house),
    description: &"ELI mesh network formed at system {systemId} " &
                 &"({scoutCount} scouts, +{meshBonus} ELI bonus)",
    systemId: some(systemId),
    meshHouse: some(house),
    scoutCount: some(scoutCount),
    meshBonusEli: some(meshBonus)
  )

# -----------------------------------------------------------------------------
# Fighter/Carrier Events
# -----------------------------------------------------------------------------

proc fighterDeployed*(
  carrierFleetId: FleetId,
  carrierHouse: HouseId,
  fighterSquadronId: string,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for fighter squadron deployment
  event_types.GameEvent(
    eventType: event_types.GameEventType.FighterDeployed,
    turn: 0,
    houseId: some(carrierHouse),
    description: &"Fighter squadron {fighterSquadronId} deployed from " &
                 &"carrier {carrierFleetId} at system {systemId}",
    systemId: some(systemId),
    fleetId: some(carrierFleetId),
    carrierFleetId: some(carrierFleetId),
    fighterSquadronId: some(fighterSquadronId),
    deploymentPhase: some("PhaseTwo")  # Fighters deploy in Phase 2
  )

proc fighterEngagement*(
  attackerFighter: string,
  attackerHouse: HouseId,
  targetSquadron: string,
  targetHouse: HouseId,
  damage: int,  # Full AS, no CER roll
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for fighter engagement (no CER, full AS damage)
  event_types.GameEvent(
    eventType: event_types.GameEventType.FighterEngagement,
    turn: 0,
    houseId: some(attackerHouse),
    description: &"Fighter {attackerFighter} engaged squadron " &
                 &"{targetSquadron} at system {systemId} ({damage} damage, no " &
                 &"CER roll)",
    systemId: some(systemId),
    sourceHouseId: some(attackerHouse),
    targetHouseId: some(targetHouse),
    attackerFighter: some(attackerFighter),
    targetFighter: some(targetSquadron),
    fighterDamage: some(damage),
    noCerRoll: some(true)  # Fighters always deal full AS
  )

proc carrierDestroyed*(
  carrierId: FleetId,
  carrierHouse: HouseId,
  embarkedFighters: int,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for carrier destruction (embarked fighters lost)
  event_types.GameEvent(
    eventType: event_types.GameEventType.CarrierDestroyed,
    turn: 0,
    houseId: some(carrierHouse),
    description: &"Carrier {carrierId} destroyed at system {systemId} " &
                 &"({embarkedFighters} embarked fighters lost)",
    systemId: some(systemId),
    fleetId: some(carrierId),
    destroyedCarrierId: some(carrierId),
    embarkedFightersLost: some(embarkedFighters)
  )

# -----------------------------------------------------------------------------
# Combat Round Events
# -----------------------------------------------------------------------------

proc weaponFired*(
  attackerSquadron: string,
  attackerHouse: HouseId,
  targetSquadron: string,
  targetHouse: HouseId,
  weaponType: string,
  cerRoll: int,
  cerModifier: int,
  damage: int,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for weapon fired at target
  event_types.GameEvent(
    eventType: event_types.GameEventType.WeaponFired,
    turn: 0,
    houseId: some(attackerHouse),
    description: &"Squadron {attackerSquadron} fired {weaponType} at " &
                 &"squadron {targetSquadron} (CER {cerRoll}+{cerModifier}, " &
                 &"{damage} damage)",
    systemId: some(systemId),
    sourceHouseId: some(attackerHouse),
    targetHouseId: some(targetHouse),
    attackerSquadronId: some(attackerSquadron),
    targetSquadronId: some(targetSquadron),
    weaponType: some(weaponType),
    cerRollValue: some(cerRoll),
    cerModifier: some(cerModifier),
    damageDealt: some(damage)
  )

proc shipDamaged*(
  squadronId: string,
  houseId: HouseId,
  damage: int,
  newState: string,  # "Crippled" or "Undamaged"
  remainingDs: int,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for squadron damage and state change
  event_types.GameEvent(
    eventType: event_types.GameEventType.ShipDamaged,
    turn: 0,
    houseId: some(houseId),
    description: &"Squadron {squadronId} damaged ({damage} hits, now " &
                 &"{newState}, {remainingDs} DS remaining)",
    systemId: some(systemId),
    damagedSquadronId: some(squadronId),
    damageAmount: some(damage),
    shipNewState: some(newState),
    remainingDs: some(remainingDs)
  )

proc shipDestroyed*(
  squadronId: string,
  houseId: HouseId,
  killedByHouse: HouseId,
  criticalHit: bool,
  overkillDamage: int,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for squadron destruction
  let critDesc = if criticalHit: " (critical hit)" else: ""
  event_types.GameEvent(
    eventType: event_types.GameEventType.ShipDestroyed,
    turn: 0,
    houseId: some(houseId),
    description: &"Squadron {squadronId} destroyed by {killedByHouse}{critDesc}",
    systemId: some(systemId),
    destroyedSquadronId: some(squadronId),
    killedBy: some(killedByHouse),
    criticalHit: some(criticalHit),
    overkillDamage: some(overkillDamage)
  )

proc fleetRetreat*(
  fleetId: FleetId,
  houseId: HouseId,
  reason: string,  # "ROE", "Morale", "Losses"
  threshold: int,
  casualties: int,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for fleet retreat from combat
  event_types.GameEvent(
    eventType: event_types.GameEventType.FleetRetreat,
    turn: 0,
    houseId: some(houseId),
    description: &"Fleet {fleetId} retreated from system {systemId} " &
                 &"(reason: {reason}, threshold: {threshold}, casualties: " &
                 &"{casualties})",
    systemId: some(systemId),
    fleetId: some(fleetId),
    retreatingFleetId: some(fleetId),
    retreatReason: some(reason),
    retreatThreshold: some(threshold),
    retreatCasualties: some(casualties)
  )

# -----------------------------------------------------------------------------
# Bombardment Events (Complete Tactical Data)
# -----------------------------------------------------------------------------

proc bombardmentRoundBegan*(
  round: int,  # 1, 2, or 3
  fleetId: FleetId,
  attackingHouse: HouseId,
  systemId: SystemId
): event_types.GameEvent =
  ## Create event for bombardment round beginning
  event_types.GameEvent(
    eventType: event_types.GameEventType.BombardmentRoundBegan,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Bombardment round {round} began at system {systemId} " &
                 &"(fleet {fleetId})",
    systemId: some(systemId),
    fleetId: some(fleetId),
    bombRound: some(round),
    bombardFleetId: some(fleetId),
    bombardPlanet: some(systemId)
  )

proc bombardmentRoundCompleted*(
  round: int,
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  systemId: SystemId,
  batteriesDestroyed: int,
  batteriesCrippled: int,
  shieldBlocked: int,
  groundForcesDamaged: int,
  infrastructureDamage: int,
  populationKilled: int,
  facilitiesDestroyed: int,
  attackerCasualties: int
): event_types.GameEvent =
  ## Create event for bombardment round completion with COMPLETE tactical data
  ## Fixes the critical gap where only partial data was included
  event_types.GameEvent(
    eventType: event_types.GameEventType.BombardmentRoundCompleted,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Bombardment round {round} completed at system {systemId}: " &
                 &"{batteriesDestroyed} batteries destroyed, " &
                 &"{infrastructureDamage} IU damaged, " &
                 &"{populationKilled} PU killed",
    systemId: some(systemId),
    sourceHouseId: some(attackingHouse),
    targetHouseId: some(defendingHouse),
    completedRound: some(round),
    batteriesDestroyed: some(batteriesDestroyed),
    batteriesCrippled: some(batteriesCrippled),
    shieldBlockedHits: some(shieldBlocked),
    groundForcesDamaged: some(groundForcesDamaged),
    infrastructureDestroyed: some(infrastructureDamage),
    populationKilled: some(populationKilled),
    facilitiesDestroyed: some(facilitiesDestroyed),
    attackerCasualties: some(attackerCasualties)
  )

proc shieldActivated*(
  systemId: SystemId,
  defendingHouse: HouseId,
  shieldLevel: int,  # 1-6 for SLD1-6
  roll: int,
  threshold: int,
  percentBlocked: int  # 25-50%
): event_types.GameEvent =
  ## Create event for planetary shield activation
  event_types.GameEvent(
    eventType: event_types.GameEventType.ShieldActivated,
    turn: 0,
    houseId: some(defendingHouse),
    description: &"Planetary shield SLD{shieldLevel} activated at system " &
                 &"{systemId} (roll {roll} vs {threshold}, blocked " &
                 &"{percentBlocked}% of hits)",
    systemId: some(systemId),
    shieldLevel: some(shieldLevel),
    shieldRoll: some(roll),
    shieldThreshold: some(threshold),
    percentBlocked: some(percentBlocked)
  )

proc groundBatteryFired*(
  systemId: SystemId,
  defendingHouse: HouseId,
  batteryId: int,
  targetSquadron: string,
  damage: int
): event_types.GameEvent =
  ## Create event for ground battery firing at bombarding squadron
  event_types.GameEvent(
    eventType: event_types.GameEventType.GroundBatteryFired,
    turn: 0,
    houseId: some(defendingHouse),
    description: &"Ground battery {batteryId} fired at squadron " &
                 &"{targetSquadron} at system {systemId} ({damage} damage)",
    systemId: some(systemId),
    batteryId: some(batteryId),
    batteryTargetSquadron: some(targetSquadron),
    batteryDamage: some(damage)
  )

# -----------------------------------------------------------------------------
# Invasion/Blitz Events
# -----------------------------------------------------------------------------

proc invasionBegan*(
  fleetId: FleetId,
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  systemId: SystemId,
  marinesLanding: int
): event_types.GameEvent =
  ## Create event for planetary invasion beginning
  event_types.GameEvent(
    eventType: event_types.GameEventType.InvasionBegan,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Invasion began at system {systemId}: {marinesLanding} " &
                 &"marines landing (fleet {fleetId})",
    systemId: some(systemId),
    fleetId: some(fleetId),
    sourceHouseId: some(attackingHouse),
    targetHouseId: some(defendingHouse),
    invasionFleetId: some(fleetId),
    marinesLanding: some(marinesLanding),
    invasionTargetColony: some(systemId)
  )

proc blitzBegan*(
  fleetId: FleetId,
  attackingHouse: HouseId,
  defendingHouse: HouseId,
  systemId: SystemId,
  marinesLanding: int,
  transportsVulnerable: bool = true,
  marineAsPenalty: float = 0.5  # Marines at 0.5x AS during blitz
): event_types.GameEvent =
  ## Create event for blitz operation beginning
  event_types.GameEvent(
    eventType: event_types.GameEventType.BlitzBegan,
    turn: 0,
    houseId: some(attackingHouse),
    description: &"Blitz operation began at system {systemId}: " &
                 &"{marinesLanding} marines landing (fleet {fleetId}, " &
                 &"transports vulnerable, marines at {marineAsPenalty}x AS)",
    systemId: some(systemId),
    fleetId: some(fleetId),
    sourceHouseId: some(attackingHouse),
    targetHouseId: some(defendingHouse),
    blitzFleetId: some(fleetId),
    blitzMarinesLanding: some(marinesLanding),
    transportsVulnerable: some(transportsVulnerable),
    marineAsPenalty: some(marineAsPenalty)
  )

proc groundCombatRound*(
  systemId: SystemId,
  attackers: seq[HouseId],
  defenders: seq[HouseId],
  attackerRoll: int,
  defenderRoll: int,
  casualties: seq[HouseId]
): event_types.GameEvent =
  ## Create event for ground combat round (marines vs ground forces)
  event_types.GameEvent(
    eventType: event_types.GameEventType.GroundCombatRound,
    turn: 0,
    houseId: if attackers.len > 0: some(attackers[0]) else: none(HouseId),
    description: &"Ground combat at system {systemId}: attackers rolled " &
                 &"{attackerRoll}, defenders rolled {defenderRoll}",
    systemId: some(systemId),
    attackersGround: some(attackers),
    defendersGround: some(defenders),
    attackerRoll: some(attackerRoll),
    defenderRoll: some(defenderRoll),
    groundCasualties: some(casualties)
  )

# -----------------------------------------------------------------------------
# Starbase Events
# -----------------------------------------------------------------------------

proc starbaseCombat*(
  systemId: SystemId,
  defendingHouse: HouseId,
  targetSquadron: string,
  targetHouse: HouseId,
  starbaseAs: int,
  starbaseDs: int,
  eliBonus: int = 2  # Starbases have +2 ELI detection bonus
): event_types.GameEvent =
  ## Create event for starbase participating in orbital combat
  event_types.GameEvent(
    eventType: event_types.GameEventType.StarbaseCombat,
    turn: 0,
    houseId: some(defendingHouse),
    description: &"Starbase at system {systemId} engaged squadron " &
                 &"{targetSquadron} (AS {starbaseAs}, DS {starbaseDs}, " &
                 &"+{eliBonus} ELI)",
    systemId: some(systemId),
    sourceHouseId: some(defendingHouse),
    targetHouseId: some(targetHouse),
    starbaseSystemId: some(systemId),
    starbaseTargetId: some(targetSquadron),
    starbaseAs: some(starbaseAs),
    starbaseDs: some(starbaseDs),
    starbaseEliBonus: some(eliBonus)
  )
