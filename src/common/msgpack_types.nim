## Shared MessagePack Serialization for Distinct ID Types and Case Objects
##
## This module provides msgpack pack/unpack procs for:
## 1. All distinct ID types used across EC4X
## 2. All case/variant object types (required for correct serialization)
##
## Case objects require explicit pack_type/unpack_type because msgpack4nim's
## default serialization is field-order sensitive and breaks when the
## discriminant is not the first field in memory (Nim >= 1.6 default layout).
##
## Usage:
##   import common/msgpack_types
##   # Now pack/unpack work automatically for HouseId, FleetId, etc.

import std/options
import msgpack4nim
import ../engine/types/core
import ../engine/types/espionage
import ../engine/types/diplomacy
import ../engine/types/ship
import ../engine/types/prestige
import ../engine/types/ground_unit
import ../engine/types/capacity
import ../engine/types/tech
import ../engine/types/event

# =============================================================================
# Custom Serialization for Distinct ID Types
# =============================================================================
#
# msgpack4nim requires explicit pack_type/unpack_type procs for distinct types.
# These procs serialize the underlying uint32 value directly.

proc pack_type*[S](s: S, x: HouseId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var HouseId) =
  var v: uint32
  s.unpack(v)
  x = HouseId(v)

proc pack_type*[S](s: S, x: SystemId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var SystemId) =
  var v: uint32
  s.unpack(v)
  x = SystemId(v)

proc pack_type*[S](s: S, x: ColonyId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ColonyId) =
  var v: uint32
  s.unpack(v)
  x = ColonyId(v)

proc pack_type*[S](s: S, x: NeoriaId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var NeoriaId) =
  var v: uint32
  s.unpack(v)
  x = NeoriaId(v)

proc pack_type*[S](s: S, x: KastraId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var KastraId) =
  var v: uint32
  s.unpack(v)
  x = KastraId(v)

proc pack_type*[S](s: S, x: FleetId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var FleetId) =
  var v: uint32
  s.unpack(v)
  x = FleetId(v)

proc pack_type*[S](s: S, x: ShipId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ShipId) =
  var v: uint32
  s.unpack(v)
  x = ShipId(v)

proc pack_type*[S](s: S, x: GroundUnitId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var GroundUnitId) =
  var v: uint32
  s.unpack(v)
  x = GroundUnitId(v)

proc pack_type*[S](s: S, x: ConstructionProjectId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ConstructionProjectId) =
  var v: uint32
  s.unpack(v)
  x = ConstructionProjectId(v)

proc pack_type*[S](s: S, x: RepairProjectId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var RepairProjectId) =
  var v: uint32
  s.unpack(v)
  x = RepairProjectId(v)

proc pack_type*[S](s: S, x: PopulationTransferId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var PopulationTransferId) =
  var v: uint32
  s.unpack(v)
  x = PopulationTransferId(v)

proc pack_type*[S](s: S, x: ProposalId) = s.pack(x.uint32)
proc unpack_type*[S](s: S, x: var ProposalId) =
  var v: uint32
  s.unpack(v)
  x = ProposalId(v)

# =============================================================================
# Custom Serialization for Case/Variant Object Types
# =============================================================================
#
# These procs ensure deterministic field ordering during serialization.
# Protocol: always pack discriminant first, then branch fields, then any
# common trailing fields. Unpack in the same order.

# -----------------------------------------------------------------------------
# GroundUnitGarrison (src/engine/types/ground_unit.nim)
# Discriminant: locationType: GroundUnitLocation
# Branches: OnColony -> colonyId; OnTransport -> shipId
# -----------------------------------------------------------------------------

proc pack_type*[S](s: S, x: GroundUnitGarrison) =
  s.pack(x.locationType.int)
  case x.locationType
  of GroundUnitLocation.OnColony:
    s.pack(x.colonyId)
  of GroundUnitLocation.OnTransport:
    s.pack(x.shipId)

proc unpack_type*[S](s: S, x: var GroundUnitGarrison) =
  var disc: int
  s.unpack(disc)
  let loc = GroundUnitLocation(disc)
  case loc
  of GroundUnitLocation.OnColony:
    var colonyId: ColonyId
    s.unpack(colonyId)
    x = GroundUnitGarrison(
      locationType: GroundUnitLocation.OnColony,
      colonyId: colonyId
    )
  of GroundUnitLocation.OnTransport:
    var shipId: ShipId
    s.unpack(shipId)
    x = GroundUnitGarrison(
      locationType: GroundUnitLocation.OnTransport,
      shipId: shipId
    )

# -----------------------------------------------------------------------------
# EntityIdUnion (src/engine/types/capacity.nim)
# Discriminant: kind: CapacityType
# Branches:
#   FighterSquadron, ConstructionDock -> colonyId
#   CapitalSquadron, TotalSquadron, PlanetBreaker, FleetCount, C2Pool -> houseId
#   CarrierHangar -> shipId
#   FleetSize -> fleetId
# -----------------------------------------------------------------------------

proc pack_type*[S](s: S, x: EntityIdUnion) =
  s.pack(x.kind.int)
  case x.kind
  of CapacityType.FighterSquadron, CapacityType.ConstructionDock:
    s.pack(x.colonyId)
  of CapacityType.CapitalSquadron, CapacityType.TotalSquadron,
      CapacityType.PlanetBreaker, CapacityType.FleetCount,
      CapacityType.C2Pool:
    s.pack(x.houseId)
  of CapacityType.CarrierHangar:
    s.pack(x.shipId)
  of CapacityType.FleetSize:
    s.pack(x.fleetId)

proc unpack_type*[S](s: S, x: var EntityIdUnion) =
  var disc: int
  s.unpack(disc)
  let kind = CapacityType(disc)
  case kind
  of CapacityType.FighterSquadron, CapacityType.ConstructionDock:
    var colonyId: ColonyId
    s.unpack(colonyId)
    x = EntityIdUnion(kind: kind, colonyId: colonyId)
  of CapacityType.CapitalSquadron, CapacityType.TotalSquadron,
      CapacityType.PlanetBreaker, CapacityType.FleetCount,
      CapacityType.C2Pool:
    var houseId: HouseId
    s.unpack(houseId)
    x = EntityIdUnion(kind: kind, houseId: houseId)
  of CapacityType.CarrierHangar:
    var shipId: ShipId
    s.unpack(shipId)
    x = EntityIdUnion(kind: kind, shipId: shipId)
  of CapacityType.FleetSize:
    var fleetId: FleetId
    s.unpack(fleetId)
    x = EntityIdUnion(kind: kind, fleetId: fleetId)

# -----------------------------------------------------------------------------
# ResearchAdvancement (src/engine/types/tech.nim)
# Discriminant: advancementType: AdvancementType
# Branches:
#   EconomicLevel -> elFromLevel, elToLevel, elCost
#   ScienceLevel  -> slFromLevel, slToLevel, slCost
#   Technology    -> techField, techFromLevel, techToLevel, techCost
# Common trailing fields: houseId, prestigeEvent
# -----------------------------------------------------------------------------

proc pack_type*[S](s: S, x: ResearchAdvancement) =
  s.pack(x.advancementType.int)
  case x.advancementType
  of AdvancementType.EconomicLevel:
    s.pack(x.elFromLevel)
    s.pack(x.elToLevel)
    s.pack(x.elCost)
  of AdvancementType.ScienceLevel:
    s.pack(x.slFromLevel)
    s.pack(x.slToLevel)
    s.pack(x.slCost)
  of AdvancementType.Technology:
    s.pack(x.techField.int)
    s.pack(x.techFromLevel)
    s.pack(x.techToLevel)
    s.pack(x.techCost)
  # Common trailing fields
  s.pack(x.houseId)
  s.pack(x.prestigeEvent)

proc unpack_type*[S](s: S, x: var ResearchAdvancement) =
  var disc: int
  s.unpack(disc)
  let advType = AdvancementType(disc)
  case advType
  of AdvancementType.EconomicLevel:
    var elFrom, elTo, elCost: int32
    s.unpack(elFrom)
    s.unpack(elTo)
    s.unpack(elCost)
    x = ResearchAdvancement(
      advancementType: AdvancementType.EconomicLevel,
      elFromLevel: elFrom,
      elToLevel: elTo,
      elCost: elCost
    )
  of AdvancementType.ScienceLevel:
    var slFrom, slTo, slCost: int32
    s.unpack(slFrom)
    s.unpack(slTo)
    s.unpack(slCost)
    x = ResearchAdvancement(
      advancementType: AdvancementType.ScienceLevel,
      slFromLevel: slFrom,
      slToLevel: slTo,
      slCost: slCost
    )
  of AdvancementType.Technology:
    var techDisc: int
    s.unpack(techDisc)
    var techFrom, techTo, techCost: int32
    s.unpack(techFrom)
    s.unpack(techTo)
    s.unpack(techCost)
    x = ResearchAdvancement(
      advancementType: AdvancementType.Technology,
      techField: TechField(techDisc),
      techFromLevel: techFrom,
      techToLevel: techTo,
      techCost: techCost
    )
  # Common trailing fields
  var houseId: HouseId
  var prestigeEvent: Option[PrestigeEvent]
  s.unpack(houseId)
  s.unpack(prestigeEvent)
  x.houseId = houseId
  x.prestigeEvent = prestigeEvent

# -----------------------------------------------------------------------------
# GameEvent (src/engine/types/event.nim)
# Discriminant: eventType: GameEventType
# Common leading fields (12): turn, houseId, systemId, description,
#   sourceHouseId, targetHouseId, targetSystemId, success, detected,
#   details, fleetId, newOwner, oldOwner
# Branch groups (14):
#   General/Battle/BattleOccurred/Bombardment/ResourceWarning/
#     ThreatDetected/AutomationCompleted -> message
#   CommandIssued/CommandCompleted/CommandRejected/CommandFailed/
#     CommandAborted/FleetArrived -> orderType, reason
#   CombatResult/SystemCaptured/ColonyCaptured/InvasionRepelled ->
#     attackingHouseId, defendingHouseId, outcome,
#     totalAttackStrength, totalDefenseStrength,
#     attackerLosses, defenderLosses
#   Espionage/SpyMissionSucceeded/SabotageConducted/TechTheftExecuted/
#     AssassinationAttempted/EconomicManipulationExecuted/
#     CyberAttackConducted/PsyopsCampaignLaunched/IntelTheftExecuted/
#     DisinformationPlanted/CounterIntelSweepExecuted/SpyMissionDetected
#     -> operationType
#   Diplomacy/WarDeclared/PeaceSigned/DiplomaticRelationChanged/
#     TreatyProposed/TreatyAccepted/TreatyBroken ->
#     action, proposalType, oldState, newState, changeReason
#   Research/TechAdvance -> techField, oldLevel, newLevel, breakthrough
#   Economy/ConstructionStarted/PopulationTransfer/
#     PopulationTransferCompleted/PopulationTransferLost/
#     InfrastructureDamage/SalvageRecovered -> category, amount
#   Colony/ColonyEstablished/BuildingCompleted/UnitRecruited/
#     UnitDisbanded/TerraformComplete/RepairQueued/RepairCancelled/
#     EntitySalvaged/ConstructionLost ->
#     colonyEventType, salvageValueColony, lostProjectType, lostProjectPP
#   Fleet/FleetDestroyed/ShipCommissioned/ScoutDestroyed/FleetDisbanded/
#     SquadronDisbanded/SquadronScrapped/RepairStalled/RepairCompleted ->
#     fleetEventType, shipClass, salvageValue
#   Intelligence/IntelGathered/ScoutDetected -> intelType
#   Prestige/PrestigeGained/PrestigeLost -> changeAmount
#   HouseEliminated -> eliminatedBy
#   CombatTheaterBegan/CombatTheaterCompleted ->
#     theater, attackers, defenders, roundNumber, casualties
#   CombatPhaseBegan/CombatPhaseCompleted ->
#     phase, roundNumberPhase, phaseRounds, phaseCasualties
#   RaiderDetected ->
#     raiderFleetId, detectorHouse, detectorType, eliRoll, clkRoll
#   RaiderStealthSuccess ->
#     stealthFleetId, attemptedDetectorHouse, attemptedDetectorType,
#     stealthEliRoll, stealthClkRoll
#   StarbaseSurveillanceDetection ->
#     surveillanceStarbaseId, surveillanceOwner,
#     detectedFleetsCount, undetectedFleetsCount
#   RaiderAmbush ->
#     ambushFleetId, ambushTargetHouse, ambushBonus
#   FighterDeployed ->
#     carrierFleetId, fighterSquadronId, deploymentPhase
#   FighterEngagement ->
#     attackerFighter, targetFighter, fighterDamage, noCerRoll
#   CarrierDestroyed ->
#     destroyedCarrierId, embarkedFightersLost
#   WeaponFired ->
#     attackerSquadronId, weaponType, targetSquadronId,
#     cerRollValue, cerModifier, damageDealt
#   ShipDamaged ->
#     damagedSquadronId, damageAmount, shipNewState, remainingDs
#   ShipDestroyed ->
#     destroyedSquadronId, killedBy, criticalHit, overkillDamage
#   FleetRetreat ->
#     retreatingFleetId, retreatReason, retreatThreshold, retreatCasualties
#   BombardmentRoundBegan ->
#     bombRound, bombardFleetId, bombardPlanet
#   BombardmentRoundCompleted ->
#     completedRound, batteriesDestroyed, batteriesCrippled,
#     shieldBlockedHits, groundForcesDamaged, infrastructureDestroyed,
#     populationKilled, facilitiesDestroyed, attackerCasualties
#   ShieldActivated ->
#     shieldLevel, shieldRoll, shieldThreshold, percentBlocked
#   GroundBatteryFired ->
#     batteryId, batteryTargetSquadron, batteryDamage
#   InvasionBegan ->
#     invasionFleetId, marinesLanding, invasionTargetColony
#   BlitzBegan ->
#     blitzFleetId, blitzMarinesLanding, transportsVulnerable,
#     marineAsPenalty
#   GroundCombatRound ->
#     attackersGround, defendersGround, attackerRoll, defenderRoll,
#     groundCasualties
#   StarbaseCombat ->
#     starbaseSystemId, starbaseTargetId, starbaseAs, starbaseDs,
#     starbaseEliBonus
#   BlockadeSuccessful ->
#     blockadeTurns, totalBlockaders
#   ColonyProjectsLost -> (no branch fields, uses common systemId)
#   FleetEncounter ->
#     encounteringFleetId, encounteredFleetIds, encounterLocation,
#     diplomaticStatus
#   FleetMerged ->
#     sourceFleetId, targetFleetIdMerge, squadronsMerged, mergeLocation
#   FleetDetachment ->
#     parentFleetId, newFleetId, squadronsDetached, detachmentLocation
#   FleetTransfer ->
#     transferSourceFleetId, transferTargetFleetId, squadronsTransferred,
#     transferLocation
#   CargoLoaded ->
#     loadingFleetId, cargoType, cargoQuantity, loadLocation
#   CargoUnloaded ->
#     unloadingFleetId, unloadCargoType, unloadCargoQuantity,
#     unloadLocation
# -----------------------------------------------------------------------------

proc pack_type*[S](s: S, x: GameEvent) =
  # Common leading fields
  s.pack(x.turn)
  s.pack(x.houseId)
  s.pack(x.systemId)
  s.pack(x.description)
  s.pack(x.sourceHouseId)
  s.pack(x.targetHouseId)
  s.pack(x.targetSystemId)
  s.pack(x.success)
  s.pack(x.detected)
  s.pack(x.details)
  s.pack(x.fleetId)
  s.pack(x.newOwner)
  s.pack(x.oldOwner)
  # Discriminant
  s.pack(x.eventType.int)
  # Branch fields
  case x.eventType
  of GameEventType.General, GameEventType.Battle,
      GameEventType.BattleOccurred, GameEventType.Bombardment,
      GameEventType.ResourceWarning, GameEventType.ThreatDetected,
      GameEventType.AutomationCompleted:
    s.pack(x.message)
  of GameEventType.CommandIssued, GameEventType.CommandCompleted,
      GameEventType.CommandRejected, GameEventType.CommandFailed,
      GameEventType.CommandAborted, GameEventType.FleetArrived:
    s.pack(x.orderType)
    s.pack(x.reason)
  of GameEventType.CombatResult, GameEventType.SystemCaptured,
      GameEventType.ColonyCaptured, GameEventType.InvasionRepelled:
    s.pack(x.attackingHouseId)
    s.pack(x.defendingHouseId)
    s.pack(x.outcome)
    s.pack(x.totalAttackStrength)
    s.pack(x.totalDefenseStrength)
    s.pack(x.attackerLosses)
    s.pack(x.defenderLosses)
  of GameEventType.Espionage, GameEventType.SpyMissionSucceeded,
      GameEventType.SabotageConducted,
      GameEventType.TechTheftExecuted,
      GameEventType.AssassinationAttempted,
      GameEventType.EconomicManipulationExecuted,
      GameEventType.CyberAttackConducted,
      GameEventType.PsyopsCampaignLaunched,
      GameEventType.IntelTheftExecuted,
      GameEventType.DisinformationPlanted,
      GameEventType.CounterIntelSweepExecuted,
      GameEventType.SpyMissionDetected:
    s.pack(x.operationType)
  of GameEventType.Diplomacy, GameEventType.WarDeclared,
      GameEventType.PeaceSigned,
      GameEventType.DiplomaticRelationChanged,
      GameEventType.TreatyProposed, GameEventType.TreatyAccepted,
      GameEventType.TreatyBroken:
    s.pack(x.action)
    s.pack(x.proposalType)
    s.pack(x.oldState)
    s.pack(x.newState)
    s.pack(x.changeReason)
  of GameEventType.Research, GameEventType.TechAdvance:
    s.pack(x.techField.int)
    s.pack(x.oldLevel)
    s.pack(x.newLevel)
    s.pack(x.breakthrough)
  of GameEventType.Economy, GameEventType.ConstructionStarted,
      GameEventType.PopulationTransfer,
      GameEventType.PopulationTransferCompleted,
      GameEventType.PopulationTransferLost,
      GameEventType.InfrastructureDamage,
      GameEventType.SalvageRecovered:
    s.pack(x.category)
    s.pack(x.amount)
  of GameEventType.Colony, GameEventType.ColonyEstablished,
      GameEventType.BuildingCompleted, GameEventType.UnitRecruited,
      GameEventType.UnitDisbanded, GameEventType.TerraformComplete,
      GameEventType.RepairQueued, GameEventType.RepairCancelled,
      GameEventType.EntitySalvaged, GameEventType.ConstructionLost:
    s.pack(x.colonyEventType)
    s.pack(x.salvageValueColony)
    s.pack(x.lostProjectType)
    s.pack(x.lostProjectPP)
  of GameEventType.Fleet, GameEventType.FleetDestroyed,
      GameEventType.ShipCommissioned, GameEventType.ScoutDestroyed,
      GameEventType.FleetDisbanded, GameEventType.SquadronDisbanded,
      GameEventType.SquadronScrapped, GameEventType.RepairStalled,
      GameEventType.RepairCompleted:
    s.pack(x.fleetEventType)
    s.pack(x.shipClass)
    s.pack(x.salvageValue)
  of GameEventType.Intelligence, GameEventType.IntelGathered,
      GameEventType.ScoutDetected:
    s.pack(x.intelType)
  of GameEventType.Prestige, GameEventType.PrestigeGained,
      GameEventType.PrestigeLost:
    s.pack(x.changeAmount)
  of GameEventType.HouseEliminated:
    s.pack(x.eliminatedBy)
  of GameEventType.CombatTheaterBegan,
      GameEventType.CombatTheaterCompleted:
    s.pack(x.theater)
    s.pack(x.attackers)
    s.pack(x.defenders)
    s.pack(x.roundNumber)
    s.pack(x.casualties)
  of GameEventType.CombatPhaseBegan,
      GameEventType.CombatPhaseCompleted:
    s.pack(x.phase)
    s.pack(x.roundNumberPhase)
    s.pack(x.phaseRounds)
    s.pack(x.phaseCasualties)
  of GameEventType.RaiderDetected:
    s.pack(x.raiderFleetId)
    s.pack(x.detectorHouse)
    s.pack(x.detectorType)
    s.pack(x.eliRoll)
    s.pack(x.clkRoll)
  of GameEventType.RaiderStealthSuccess:
    s.pack(x.stealthFleetId)
    s.pack(x.attemptedDetectorHouse)
    s.pack(x.attemptedDetectorType)
    s.pack(x.stealthEliRoll)
    s.pack(x.stealthClkRoll)
  of GameEventType.StarbaseSurveillanceDetection:
    s.pack(x.surveillanceStarbaseId)
    s.pack(x.surveillanceOwner)
    s.pack(x.detectedFleetsCount)
    s.pack(x.undetectedFleetsCount)
  of GameEventType.RaiderAmbush:
    s.pack(x.ambushFleetId)
    s.pack(x.ambushTargetHouse)
    s.pack(x.ambushBonus)
  of GameEventType.FighterDeployed:
    s.pack(x.carrierFleetId)
    s.pack(x.fighterSquadronId)
    s.pack(x.deploymentPhase)
  of GameEventType.FighterEngagement:
    s.pack(x.attackerFighter)
    s.pack(x.targetFighter)
    s.pack(x.fighterDamage)
    s.pack(x.noCerRoll)
  of GameEventType.CarrierDestroyed:
    s.pack(x.destroyedCarrierId)
    s.pack(x.embarkedFightersLost)
  of GameEventType.WeaponFired:
    s.pack(x.attackerSquadronId)
    s.pack(x.weaponType)
    s.pack(x.targetSquadronId)
    s.pack(x.cerRollValue)
    s.pack(x.cerModifier)
    s.pack(x.damageDealt)
  of GameEventType.ShipDamaged:
    s.pack(x.damagedSquadronId)
    s.pack(x.damageAmount)
    s.pack(x.shipNewState)
    s.pack(x.remainingDs)
  of GameEventType.ShipDestroyed:
    s.pack(x.destroyedSquadronId)
    s.pack(x.killedBy)
    s.pack(x.criticalHit)
    s.pack(x.overkillDamage)
  of GameEventType.FleetRetreat:
    s.pack(x.retreatingFleetId)
    s.pack(x.retreatReason)
    s.pack(x.retreatThreshold)
    s.pack(x.retreatCasualties)
  of GameEventType.BombardmentRoundBegan:
    s.pack(x.bombRound)
    s.pack(x.bombardFleetId)
    s.pack(x.bombardPlanet)
  of GameEventType.BombardmentRoundCompleted:
    s.pack(x.completedRound)
    s.pack(x.batteriesDestroyed)
    s.pack(x.batteriesCrippled)
    s.pack(x.shieldBlockedHits)
    s.pack(x.groundForcesDamaged)
    s.pack(x.infrastructureDestroyed)
    s.pack(x.populationKilled)
    s.pack(x.facilitiesDestroyed)
    s.pack(x.attackerCasualties)
  of GameEventType.ShieldActivated:
    s.pack(x.shieldLevel)
    s.pack(x.shieldRoll)
    s.pack(x.shieldThreshold)
    s.pack(x.percentBlocked)
  of GameEventType.GroundBatteryFired:
    s.pack(x.batteryId)
    s.pack(x.batteryTargetSquadron)
    s.pack(x.batteryDamage)
  of GameEventType.InvasionBegan:
    s.pack(x.invasionFleetId)
    s.pack(x.marinesLanding)
    s.pack(x.invasionTargetColony)
  of GameEventType.BlitzBegan:
    s.pack(x.blitzFleetId)
    s.pack(x.blitzMarinesLanding)
    s.pack(x.transportsVulnerable)
    s.pack(x.marineAsPenalty)
  of GameEventType.GroundCombatRound:
    s.pack(x.attackersGround)
    s.pack(x.defendersGround)
    s.pack(x.attackerRoll)
    s.pack(x.defenderRoll)
    s.pack(x.groundCasualties)
  of GameEventType.StarbaseCombat:
    s.pack(x.starbaseSystemId)
    s.pack(x.starbaseTargetId)
    s.pack(x.starbaseAs)
    s.pack(x.starbaseDs)
    s.pack(x.starbaseEliBonus)
  of GameEventType.BlockadeSuccessful:
    s.pack(x.blockadeTurns)
    s.pack(x.totalBlockaders)
  of GameEventType.ColonyProjectsLost:
    discard # No branch fields; uses common systemId + description
  of GameEventType.FleetEncounter:
    s.pack(x.encounteringFleetId)
    s.pack(x.encounteredFleetIds)
    s.pack(x.encounterLocation)
    s.pack(x.diplomaticStatus)
  of GameEventType.FleetMerged:
    s.pack(x.sourceFleetId)
    s.pack(x.targetFleetIdMerge)
    s.pack(x.squadronsMerged)
    s.pack(x.mergeLocation)
  of GameEventType.FleetDetachment:
    s.pack(x.parentFleetId)
    s.pack(x.newFleetId)
    s.pack(x.squadronsDetached)
    s.pack(x.detachmentLocation)
  of GameEventType.FleetTransfer:
    s.pack(x.transferSourceFleetId)
    s.pack(x.transferTargetFleetId)
    s.pack(x.squadronsTransferred)
    s.pack(x.transferLocation)
  of GameEventType.CargoLoaded:
    s.pack(x.loadingFleetId)
    s.pack(x.cargoType)
    s.pack(x.cargoQuantity)
    s.pack(x.loadLocation)
  of GameEventType.CargoUnloaded:
    s.pack(x.unloadingFleetId)
    s.pack(x.unloadCargoType)
    s.pack(x.unloadCargoQuantity)
    s.pack(x.unloadLocation)

proc unpack_type*[S](s: S, x: var GameEvent) =
  # Common leading fields
  var turn: int
  var houseId: Option[HouseId]
  var systemId: Option[SystemId]
  var description: string
  var sourceHouseId: Option[HouseId]
  var targetHouseId: Option[HouseId]
  var targetSystemId: Option[SystemId]
  var success: Option[bool]
  var detected: Option[bool]
  var details: Option[string]
  var fleetId: Option[FleetId]
  var newOwner: Option[HouseId]
  var oldOwner: Option[HouseId]
  s.unpack(turn)
  s.unpack(houseId)
  s.unpack(systemId)
  s.unpack(description)
  s.unpack(sourceHouseId)
  s.unpack(targetHouseId)
  s.unpack(targetSystemId)
  s.unpack(success)
  s.unpack(detected)
  s.unpack(details)
  s.unpack(fleetId)
  s.unpack(newOwner)
  s.unpack(oldOwner)
  # Discriminant
  var disc: int
  s.unpack(disc)
  let evType = GameEventType(disc)
  # Construct with discriminant and branch fields
  case evType
  of GameEventType.General, GameEventType.Battle,
      GameEventType.BattleOccurred, GameEventType.Bombardment,
      GameEventType.ResourceWarning, GameEventType.ThreatDetected,
      GameEventType.AutomationCompleted:
    var message: string
    s.unpack(message)
    x = GameEvent(eventType: evType, message: message)
  of GameEventType.CommandIssued, GameEventType.CommandCompleted,
      GameEventType.CommandRejected, GameEventType.CommandFailed,
      GameEventType.CommandAborted, GameEventType.FleetArrived:
    var orderType: Option[string]
    var reason: Option[string]
    s.unpack(orderType)
    s.unpack(reason)
    x = GameEvent(
      eventType: evType, orderType: orderType, reason: reason)
  of GameEventType.CombatResult, GameEventType.SystemCaptured,
      GameEventType.ColonyCaptured, GameEventType.InvasionRepelled:
    var attackingHouseId: Option[HouseId]
    var defendingHouseId: Option[HouseId]
    var outcome: Option[string]
    var totalAttackStrength: Option[int]
    var totalDefenseStrength: Option[int]
    var attackerLosses: Option[int]
    var defenderLosses: Option[int]
    s.unpack(attackingHouseId)
    s.unpack(defendingHouseId)
    s.unpack(outcome)
    s.unpack(totalAttackStrength)
    s.unpack(totalDefenseStrength)
    s.unpack(attackerLosses)
    s.unpack(defenderLosses)
    x = GameEvent(
      eventType: evType,
      attackingHouseId: attackingHouseId,
      defendingHouseId: defendingHouseId,
      outcome: outcome,
      totalAttackStrength: totalAttackStrength,
      totalDefenseStrength: totalDefenseStrength,
      attackerLosses: attackerLosses,
      defenderLosses: defenderLosses
    )
  of GameEventType.Espionage, GameEventType.SpyMissionSucceeded,
      GameEventType.SabotageConducted,
      GameEventType.TechTheftExecuted,
      GameEventType.AssassinationAttempted,
      GameEventType.EconomicManipulationExecuted,
      GameEventType.CyberAttackConducted,
      GameEventType.PsyopsCampaignLaunched,
      GameEventType.IntelTheftExecuted,
      GameEventType.DisinformationPlanted,
      GameEventType.CounterIntelSweepExecuted,
      GameEventType.SpyMissionDetected:
    var operationType: Option[EspionageAction]
    s.unpack(operationType)
    x = GameEvent(eventType: evType, operationType: operationType)
  of GameEventType.Diplomacy, GameEventType.WarDeclared,
      GameEventType.PeaceSigned,
      GameEventType.DiplomaticRelationChanged,
      GameEventType.TreatyProposed, GameEventType.TreatyAccepted,
      GameEventType.TreatyBroken:
    var action: Option[string]
    var proposalType: Option[string]
    var oldState: Option[DiplomaticState]
    var newState: Option[DiplomaticState]
    var changeReason: Option[string]
    s.unpack(action)
    s.unpack(proposalType)
    s.unpack(oldState)
    s.unpack(newState)
    s.unpack(changeReason)
    x = GameEvent(
      eventType: evType,
      action: action,
      proposalType: proposalType,
      oldState: oldState,
      newState: newState,
      changeReason: changeReason
    )
  of GameEventType.Research, GameEventType.TechAdvance:
    var techDisc: int
    s.unpack(techDisc)
    var oldLevel: Option[int]
    var newLevel: Option[int]
    var breakthrough: Option[string]
    s.unpack(oldLevel)
    s.unpack(newLevel)
    s.unpack(breakthrough)
    x = GameEvent(
      eventType: evType,
      techField: TechField(techDisc),
      oldLevel: oldLevel,
      newLevel: newLevel,
      breakthrough: breakthrough
    )
  of GameEventType.Economy, GameEventType.ConstructionStarted,
      GameEventType.PopulationTransfer,
      GameEventType.PopulationTransferCompleted,
      GameEventType.PopulationTransferLost,
      GameEventType.InfrastructureDamage,
      GameEventType.SalvageRecovered:
    var category: Option[string]
    var amount: Option[int]
    s.unpack(category)
    s.unpack(amount)
    x = GameEvent(
      eventType: evType, category: category, amount: amount)
  of GameEventType.Colony, GameEventType.ColonyEstablished,
      GameEventType.BuildingCompleted, GameEventType.UnitRecruited,
      GameEventType.UnitDisbanded, GameEventType.TerraformComplete,
      GameEventType.RepairQueued, GameEventType.RepairCancelled,
      GameEventType.EntitySalvaged, GameEventType.ConstructionLost:
    var colonyEventType: Option[string]
    var salvageValueColony: Option[int]
    var lostProjectType: Option[string]
    var lostProjectPP: Option[int]
    s.unpack(colonyEventType)
    s.unpack(salvageValueColony)
    s.unpack(lostProjectType)
    s.unpack(lostProjectPP)
    x = GameEvent(
      eventType: evType,
      colonyEventType: colonyEventType,
      salvageValueColony: salvageValueColony,
      lostProjectType: lostProjectType,
      lostProjectPP: lostProjectPP
    )
  of GameEventType.Fleet, GameEventType.FleetDestroyed,
      GameEventType.ShipCommissioned, GameEventType.ScoutDestroyed,
      GameEventType.FleetDisbanded, GameEventType.SquadronDisbanded,
      GameEventType.SquadronScrapped, GameEventType.RepairStalled,
      GameEventType.RepairCompleted:
    var fleetEventType: Option[string]
    var shipClass: Option[ShipClass]
    var salvageValue: Option[int]
    s.unpack(fleetEventType)
    s.unpack(shipClass)
    s.unpack(salvageValue)
    x = GameEvent(
      eventType: evType,
      fleetEventType: fleetEventType,
      shipClass: shipClass,
      salvageValue: salvageValue
    )
  of GameEventType.Intelligence, GameEventType.IntelGathered,
      GameEventType.ScoutDetected:
    var intelType: Option[string]
    s.unpack(intelType)
    x = GameEvent(eventType: evType, intelType: intelType)
  of GameEventType.Prestige, GameEventType.PrestigeGained,
      GameEventType.PrestigeLost:
    var changeAmount: Option[int]
    s.unpack(changeAmount)
    x = GameEvent(eventType: evType, changeAmount: changeAmount)
  of GameEventType.HouseEliminated:
    var eliminatedBy: Option[HouseId]
    s.unpack(eliminatedBy)
    x = GameEvent(eventType: evType, eliminatedBy: eliminatedBy)
  of GameEventType.CombatTheaterBegan,
      GameEventType.CombatTheaterCompleted:
    var theater: Option[string]
    var attackers: Option[seq[HouseId]]
    var defenders: Option[seq[HouseId]]
    var roundNumber: Option[int]
    var casualties: Option[seq[HouseId]]
    s.unpack(theater)
    s.unpack(attackers)
    s.unpack(defenders)
    s.unpack(roundNumber)
    s.unpack(casualties)
    x = GameEvent(
      eventType: evType,
      theater: theater,
      attackers: attackers,
      defenders: defenders,
      roundNumber: roundNumber,
      casualties: casualties
    )
  of GameEventType.CombatPhaseBegan,
      GameEventType.CombatPhaseCompleted:
    var phase: Option[string]
    var roundNumberPhase: Option[int]
    var phaseRounds: Option[int]
    var phaseCasualties: Option[seq[HouseId]]
    s.unpack(phase)
    s.unpack(roundNumberPhase)
    s.unpack(phaseRounds)
    s.unpack(phaseCasualties)
    x = GameEvent(
      eventType: evType,
      phase: phase,
      roundNumberPhase: roundNumberPhase,
      phaseRounds: phaseRounds,
      phaseCasualties: phaseCasualties
    )
  of GameEventType.RaiderDetected:
    var raiderFleetId: Option[FleetId]
    var detectorHouse: Option[HouseId]
    var detectorType: Option[string]
    var eliRoll: Option[int]
    var clkRoll: Option[int]
    s.unpack(raiderFleetId)
    s.unpack(detectorHouse)
    s.unpack(detectorType)
    s.unpack(eliRoll)
    s.unpack(clkRoll)
    x = GameEvent(
      eventType: evType,
      raiderFleetId: raiderFleetId,
      detectorHouse: detectorHouse,
      detectorType: detectorType,
      eliRoll: eliRoll,
      clkRoll: clkRoll
    )
  of GameEventType.RaiderStealthSuccess:
    var stealthFleetId: Option[FleetId]
    var attemptedDetectorHouse: Option[HouseId]
    var attemptedDetectorType: Option[string]
    var stealthEliRoll: Option[int]
    var stealthClkRoll: Option[int]
    s.unpack(stealthFleetId)
    s.unpack(attemptedDetectorHouse)
    s.unpack(attemptedDetectorType)
    s.unpack(stealthEliRoll)
    s.unpack(stealthClkRoll)
    x = GameEvent(
      eventType: evType,
      stealthFleetId: stealthFleetId,
      attemptedDetectorHouse: attemptedDetectorHouse,
      attemptedDetectorType: attemptedDetectorType,
      stealthEliRoll: stealthEliRoll,
      stealthClkRoll: stealthClkRoll
    )
  of GameEventType.StarbaseSurveillanceDetection:
    var surveillanceStarbaseId: Option[string]
    var surveillanceOwner: Option[HouseId]
    var detectedFleetsCount: Option[int]
    var undetectedFleetsCount: Option[int]
    s.unpack(surveillanceStarbaseId)
    s.unpack(surveillanceOwner)
    s.unpack(detectedFleetsCount)
    s.unpack(undetectedFleetsCount)
    x = GameEvent(
      eventType: evType,
      surveillanceStarbaseId: surveillanceStarbaseId,
      surveillanceOwner: surveillanceOwner,
      detectedFleetsCount: detectedFleetsCount,
      undetectedFleetsCount: undetectedFleetsCount
    )
  of GameEventType.RaiderAmbush:
    var ambushFleetId: Option[FleetId]
    var ambushTargetHouse: Option[HouseId]
    var ambushBonus: Option[int]
    s.unpack(ambushFleetId)
    s.unpack(ambushTargetHouse)
    s.unpack(ambushBonus)
    x = GameEvent(
      eventType: evType,
      ambushFleetId: ambushFleetId,
      ambushTargetHouse: ambushTargetHouse,
      ambushBonus: ambushBonus
    )
  of GameEventType.FighterDeployed:
    var carrierFleetId: Option[FleetId]
    var fighterSquadronId: Option[string]
    var deploymentPhase: Option[string]
    s.unpack(carrierFleetId)
    s.unpack(fighterSquadronId)
    s.unpack(deploymentPhase)
    x = GameEvent(
      eventType: evType,
      carrierFleetId: carrierFleetId,
      fighterSquadronId: fighterSquadronId,
      deploymentPhase: deploymentPhase
    )
  of GameEventType.FighterEngagement:
    var attackerFighter: Option[string]
    var targetFighter: Option[string]
    var fighterDamage: Option[int]
    var noCerRoll: Option[bool]
    s.unpack(attackerFighter)
    s.unpack(targetFighter)
    s.unpack(fighterDamage)
    s.unpack(noCerRoll)
    x = GameEvent(
      eventType: evType,
      attackerFighter: attackerFighter,
      targetFighter: targetFighter,
      fighterDamage: fighterDamage,
      noCerRoll: noCerRoll
    )
  of GameEventType.CarrierDestroyed:
    var destroyedCarrierId: Option[FleetId]
    var embarkedFightersLost: Option[int]
    s.unpack(destroyedCarrierId)
    s.unpack(embarkedFightersLost)
    x = GameEvent(
      eventType: evType,
      destroyedCarrierId: destroyedCarrierId,
      embarkedFightersLost: embarkedFightersLost
    )
  of GameEventType.WeaponFired:
    var attackerSquadronId: Option[string]
    var weaponType: Option[string]
    var targetSquadronId: Option[string]
    var cerRollValue: Option[int]
    var cerModifier: Option[int]
    var damageDealt: Option[int]
    s.unpack(attackerSquadronId)
    s.unpack(weaponType)
    s.unpack(targetSquadronId)
    s.unpack(cerRollValue)
    s.unpack(cerModifier)
    s.unpack(damageDealt)
    x = GameEvent(
      eventType: evType,
      attackerSquadronId: attackerSquadronId,
      weaponType: weaponType,
      targetSquadronId: targetSquadronId,
      cerRollValue: cerRollValue,
      cerModifier: cerModifier,
      damageDealt: damageDealt
    )
  of GameEventType.ShipDamaged:
    var damagedSquadronId: Option[string]
    var damageAmount: Option[int]
    var shipNewState: Option[string]
    var remainingDs: Option[int]
    s.unpack(damagedSquadronId)
    s.unpack(damageAmount)
    s.unpack(shipNewState)
    s.unpack(remainingDs)
    x = GameEvent(
      eventType: evType,
      damagedSquadronId: damagedSquadronId,
      damageAmount: damageAmount,
      shipNewState: shipNewState,
      remainingDs: remainingDs
    )
  of GameEventType.ShipDestroyed:
    var destroyedSquadronId: Option[string]
    var killedBy: Option[HouseId]
    var criticalHit: Option[bool]
    var overkillDamage: Option[int]
    s.unpack(destroyedSquadronId)
    s.unpack(killedBy)
    s.unpack(criticalHit)
    s.unpack(overkillDamage)
    x = GameEvent(
      eventType: evType,
      destroyedSquadronId: destroyedSquadronId,
      killedBy: killedBy,
      criticalHit: criticalHit,
      overkillDamage: overkillDamage
    )
  of GameEventType.FleetRetreat:
    var retreatingFleetId: Option[FleetId]
    var retreatReason: Option[string]
    var retreatThreshold: Option[int]
    var retreatCasualties: Option[int]
    s.unpack(retreatingFleetId)
    s.unpack(retreatReason)
    s.unpack(retreatThreshold)
    s.unpack(retreatCasualties)
    x = GameEvent(
      eventType: evType,
      retreatingFleetId: retreatingFleetId,
      retreatReason: retreatReason,
      retreatThreshold: retreatThreshold,
      retreatCasualties: retreatCasualties
    )
  of GameEventType.BombardmentRoundBegan:
    var bombRound: Option[int]
    var bombardFleetId: Option[FleetId]
    var bombardPlanet: Option[SystemId]
    s.unpack(bombRound)
    s.unpack(bombardFleetId)
    s.unpack(bombardPlanet)
    x = GameEvent(
      eventType: evType,
      bombRound: bombRound,
      bombardFleetId: bombardFleetId,
      bombardPlanet: bombardPlanet
    )
  of GameEventType.BombardmentRoundCompleted:
    var completedRound: Option[int]
    var batteriesDestroyed: Option[int]
    var batteriesCrippled: Option[int]
    var shieldBlockedHits: Option[int]
    var groundForcesDamaged: Option[int]
    var infrastructureDestroyed: Option[int]
    var populationKilled: Option[int]
    var facilitiesDestroyed: Option[int]
    var attackerCasualties: Option[int]
    s.unpack(completedRound)
    s.unpack(batteriesDestroyed)
    s.unpack(batteriesCrippled)
    s.unpack(shieldBlockedHits)
    s.unpack(groundForcesDamaged)
    s.unpack(infrastructureDestroyed)
    s.unpack(populationKilled)
    s.unpack(facilitiesDestroyed)
    s.unpack(attackerCasualties)
    x = GameEvent(
      eventType: evType,
      completedRound: completedRound,
      batteriesDestroyed: batteriesDestroyed,
      batteriesCrippled: batteriesCrippled,
      shieldBlockedHits: shieldBlockedHits,
      groundForcesDamaged: groundForcesDamaged,
      infrastructureDestroyed: infrastructureDestroyed,
      populationKilled: populationKilled,
      facilitiesDestroyed: facilitiesDestroyed,
      attackerCasualties: attackerCasualties
    )
  of GameEventType.ShieldActivated:
    var shieldLevel: Option[int]
    var shieldRoll: Option[int]
    var shieldThreshold: Option[int]
    var percentBlocked: Option[int]
    s.unpack(shieldLevel)
    s.unpack(shieldRoll)
    s.unpack(shieldThreshold)
    s.unpack(percentBlocked)
    x = GameEvent(
      eventType: evType,
      shieldLevel: shieldLevel,
      shieldRoll: shieldRoll,
      shieldThreshold: shieldThreshold,
      percentBlocked: percentBlocked
    )
  of GameEventType.GroundBatteryFired:
    var batteryId: Option[int]
    var batteryTargetSquadron: Option[string]
    var batteryDamage: Option[int]
    s.unpack(batteryId)
    s.unpack(batteryTargetSquadron)
    s.unpack(batteryDamage)
    x = GameEvent(
      eventType: evType,
      batteryId: batteryId,
      batteryTargetSquadron: batteryTargetSquadron,
      batteryDamage: batteryDamage
    )
  of GameEventType.InvasionBegan:
    var invasionFleetId: Option[FleetId]
    var marinesLanding: Option[int]
    var invasionTargetColony: Option[SystemId]
    s.unpack(invasionFleetId)
    s.unpack(marinesLanding)
    s.unpack(invasionTargetColony)
    x = GameEvent(
      eventType: evType,
      invasionFleetId: invasionFleetId,
      marinesLanding: marinesLanding,
      invasionTargetColony: invasionTargetColony
    )
  of GameEventType.BlitzBegan:
    var blitzFleetId: Option[FleetId]
    var blitzMarinesLanding: Option[int]
    var transportsVulnerable: Option[bool]
    var marineAsPenalty: Option[float]
    s.unpack(blitzFleetId)
    s.unpack(blitzMarinesLanding)
    s.unpack(transportsVulnerable)
    s.unpack(marineAsPenalty)
    x = GameEvent(
      eventType: evType,
      blitzFleetId: blitzFleetId,
      blitzMarinesLanding: blitzMarinesLanding,
      transportsVulnerable: transportsVulnerable,
      marineAsPenalty: marineAsPenalty
    )
  of GameEventType.GroundCombatRound:
    var attackersGround: Option[seq[HouseId]]
    var defendersGround: Option[seq[HouseId]]
    var attackerRoll: Option[int]
    var defenderRoll: Option[int]
    var groundCasualties: Option[seq[HouseId]]
    s.unpack(attackersGround)
    s.unpack(defendersGround)
    s.unpack(attackerRoll)
    s.unpack(defenderRoll)
    s.unpack(groundCasualties)
    x = GameEvent(
      eventType: evType,
      attackersGround: attackersGround,
      defendersGround: defendersGround,
      attackerRoll: attackerRoll,
      defenderRoll: defenderRoll,
      groundCasualties: groundCasualties
    )
  of GameEventType.StarbaseCombat:
    var starbaseSystemId: Option[SystemId]
    var starbaseTargetId: Option[string]
    var starbaseAs: Option[int]
    var starbaseDs: Option[int]
    var starbaseEliBonus: Option[int]
    s.unpack(starbaseSystemId)
    s.unpack(starbaseTargetId)
    s.unpack(starbaseAs)
    s.unpack(starbaseDs)
    s.unpack(starbaseEliBonus)
    x = GameEvent(
      eventType: evType,
      starbaseSystemId: starbaseSystemId,
      starbaseTargetId: starbaseTargetId,
      starbaseAs: starbaseAs,
      starbaseDs: starbaseDs,
      starbaseEliBonus: starbaseEliBonus
    )
  of GameEventType.BlockadeSuccessful:
    var blockadeTurns: Option[int32]
    var totalBlockaders: Option[int]
    s.unpack(blockadeTurns)
    s.unpack(totalBlockaders)
    x = GameEvent(
      eventType: evType,
      blockadeTurns: blockadeTurns,
      totalBlockaders: totalBlockaders
    )
  of GameEventType.ColonyProjectsLost:
    x = GameEvent(eventType: evType)
  of GameEventType.FleetEncounter:
    var encounteringFleetId: Option[FleetId]
    var encounteredFleetIds: Option[seq[FleetId]]
    var encounterLocation: Option[SystemId]
    var diplomaticStatus: Option[string]
    s.unpack(encounteringFleetId)
    s.unpack(encounteredFleetIds)
    s.unpack(encounterLocation)
    s.unpack(diplomaticStatus)
    x = GameEvent(
      eventType: evType,
      encounteringFleetId: encounteringFleetId,
      encounteredFleetIds: encounteredFleetIds,
      encounterLocation: encounterLocation,
      diplomaticStatus: diplomaticStatus
    )
  of GameEventType.FleetMerged:
    var sourceFleetId: Option[FleetId]
    var targetFleetIdMerge: Option[FleetId]
    var squadronsMerged: Option[int]
    var mergeLocation: Option[SystemId]
    s.unpack(sourceFleetId)
    s.unpack(targetFleetIdMerge)
    s.unpack(squadronsMerged)
    s.unpack(mergeLocation)
    x = GameEvent(
      eventType: evType,
      sourceFleetId: sourceFleetId,
      targetFleetIdMerge: targetFleetIdMerge,
      squadronsMerged: squadronsMerged,
      mergeLocation: mergeLocation
    )
  of GameEventType.FleetDetachment:
    var parentFleetId: Option[FleetId]
    var newFleetId: Option[FleetId]
    var squadronsDetached: Option[int]
    var detachmentLocation: Option[SystemId]
    s.unpack(parentFleetId)
    s.unpack(newFleetId)
    s.unpack(squadronsDetached)
    s.unpack(detachmentLocation)
    x = GameEvent(
      eventType: evType,
      parentFleetId: parentFleetId,
      newFleetId: newFleetId,
      squadronsDetached: squadronsDetached,
      detachmentLocation: detachmentLocation
    )
  of GameEventType.FleetTransfer:
    var transferSourceFleetId: Option[FleetId]
    var transferTargetFleetId: Option[FleetId]
    var squadronsTransferred: Option[int]
    var transferLocation: Option[SystemId]
    s.unpack(transferSourceFleetId)
    s.unpack(transferTargetFleetId)
    s.unpack(squadronsTransferred)
    s.unpack(transferLocation)
    x = GameEvent(
      eventType: evType,
      transferSourceFleetId: transferSourceFleetId,
      transferTargetFleetId: transferTargetFleetId,
      squadronsTransferred: squadronsTransferred,
      transferLocation: transferLocation
    )
  of GameEventType.CargoLoaded:
    var loadingFleetId: Option[FleetId]
    var cargoType: Option[string]
    var cargoQuantity: Option[int]
    var loadLocation: Option[SystemId]
    s.unpack(loadingFleetId)
    s.unpack(cargoType)
    s.unpack(cargoQuantity)
    s.unpack(loadLocation)
    x = GameEvent(
      eventType: evType,
      loadingFleetId: loadingFleetId,
      cargoType: cargoType,
      cargoQuantity: cargoQuantity,
      loadLocation: loadLocation
    )
  of GameEventType.CargoUnloaded:
    var unloadingFleetId: Option[FleetId]
    var unloadCargoType: Option[string]
    var unloadCargoQuantity: Option[int]
    var unloadLocation: Option[SystemId]
    s.unpack(unloadingFleetId)
    s.unpack(unloadCargoType)
    s.unpack(unloadCargoQuantity)
    s.unpack(unloadLocation)
    x = GameEvent(
      eventType: evType,
      unloadingFleetId: unloadingFleetId,
      unloadCargoType: unloadCargoType,
      unloadCargoQuantity: unloadCargoQuantity,
      unloadLocation: unloadLocation
    )
  # Restore common leading fields
  x.turn = turn
  x.houseId = houseId
  x.systemId = systemId
  x.description = description
  x.sourceHouseId = sourceHouseId
  x.targetHouseId = targetHouseId
  x.targetSystemId = targetSystemId
  x.success = success
  x.detected = detected
  x.details = details
  x.fleetId = fleetId
  x.newOwner = newOwner
  x.oldOwner = oldOwner
