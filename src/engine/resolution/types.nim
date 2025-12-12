## Common types for resolution modules

import std/[options, tables, strformat] # Added tables, strformat
import ../../common/types/core
import ../../common/types/units # For ShipClass
import ../../common/types/diplomacy # For DiplomaticState, DiplomaticActionType
import ../../common/types/tech # For TechField
import ../../engine/espionage/types as esp_types # For EspionageAction (for operationType field)

type
  GameEventType* {.pure.} = enum
    ## Categories of game events.
    ## This enum now consolidates all specific event kinds.
    General,              # Generic informational event
    OrderIssued,          # An order was successfully issued
    OrderCompleted,       # An order was completed
    OrderRejected,        # An order was rejected due to validation failure
    OrderFailed,          # An order failed during execution
    OrderAborted,         # An order was aborted due to changed conditions
    CombatResult,         # Result of a space combat or planetary assault
    Espionage,            # Outcome of an espionage operation
    Diplomacy,            # Outcome of a diplomatic action
    Research,             # Research advancement or breakthrough
    Economy,              # Economic changes (income, production, shortfall)
    Colony,               # Colony established, lost, or major change
    Fleet,                # Fleet created, destroyed, or major status change
    Intelligence,         # Intel gathered or updated
    Prestige,             # Prestige gained or lost
    # Specific event types
    ColonyEstablished,    # Colony founded
    SystemCaptured,       # System ownership changed via combat
    ColonyCaptured,       # Colony captured via invasion
    TerraformComplete,    # Terraforming project completed
    Battle,               # Generic battle event
    BattleOccurred,       # Battle observed by third party
    Bombardment,          # Planetary bombardment
    FleetDestroyed,       # Fleet eliminated in combat
    InvasionRepelled,     # Successful defense against invasion
    ConstructionStarted,  # Construction project initiated
    ShipCommissioned,     # New ship entered service
    BuildingCompleted,    # Building construction finished
    UnitRecruited,        # Ground unit recruited
    UnitDisbanded,        # Unit disbanded
    TechAdvance,          # Technology level increased
    HouseEliminated,      # House eliminated from game
    PopulationTransfer,   # Population moved between systems
    IntelGathered,        # Intelligence report generated
    PrestigeGained,       # Prestige increased
    PrestigeLost,         # Prestige decreased
    WarDeclared,          # War declaration
    PeaceSigned,          # Peace treaty signed
    DiplomaticRelationChanged, # Diplomatic state change (any transition with reason)
    TreatyProposed,       # Treaty proposal submitted
    TreatyAccepted,       # Treaty proposal accepted
    TreatyBroken,         # Treaty violation/broken
    ResourceWarning,      # Resource shortage warning
    ThreatDetected,       # Threat identified
    AutomationCompleted,  # Automated task completed
    SpyMissionSucceeded,  # Espionage operation succeeded
    SabotageConducted,    # Sabotage operation executed
    TechTheftExecuted,    # Technology stolen
    AssassinationAttempted, # Assassination attempt
    EconomicManipulationExecuted, # Economic warfare executed
    CyberAttackConducted, # Cyber attack executed
    PsyopsCampaignLaunched, # Psychological operations launched
    IntelligenceTheftExecuted, # Intelligence stolen
    DisinformationPlanted, # Disinformation planted
    CounterIntelSweepExecuted, # Counter-intelligence sweep
    SpyMissionDetected,   # Enemy espionage detected
    ScoutDetected,        # Scout detected in system
    ScoutDestroyed,       # Scout eliminated
    # Combat Narrative Events (Phase 7a)
    CombatTheaterBegan,   # Combat theater (Space/Orbital/Planetary) began
    CombatTheaterCompleted, # Combat theater completed
    CombatPhaseBegan,     # Combat sub-phase (Raider/Fighter/Capital) began
    CombatPhaseCompleted, # Combat sub-phase completed
    RaiderDetected,       # Cloaked raider detected by ELI/scouts
    RaiderAmbush,         # Raider ambush executed with +4 CER bonus
    EliMeshNetworkFormed, # Scout mesh network formed for detection
    FighterDeployed,      # Fighter squadron deployed from carrier
    FighterEngagement,    # Fighter engaged target (no CER, full AS damage)
    CarrierDestroyed,     # Carrier destroyed with embarked fighters
    WeaponFired,          # Squadron fired weapons at target
    ShipDamaged,          # Squadron took damage and changed state
    ShipDestroyed,        # Squadron destroyed in combat
    FleetRetreat,         # Fleet retreated from combat
    BombardmentRoundBegan, # Bombardment round began
    BombardmentRoundCompleted, # Bombardment round completed with full tactical data
    ShieldActivated,      # Planetary shield activated and blocked hits
    GroundBatteryFired,   # Ground battery fired at bombarding squadron
    InvasionBegan,        # Planetary invasion began
    BlitzBegan,           # Blitz operation began (bombardment + invasion)
    GroundCombatRound,    # Ground combat round (marines vs ground forces)
    StarbaseCombat,       # Starbase participated in orbital combat
    # Fleet Operations Events (Phase 7b)
    StandingOrderSet,     # Standing order configured on fleet
    StandingOrderActivated, # Standing order triggered and generated fleet order
    StandingOrderSuspended, # Standing order disabled or overridden
    FleetEncounter,       # Fleet encountered enemy fleet before combat
    FleetMerged,          # Squadrons transferred between fleets (merge)
    FleetDetachment,      # Squadrons split off to new fleet
    FleetTransfer,        # Squadrons transferred between existing fleets
    CargoLoaded,          # Marines/colonists loaded onto spacelift ships
    CargoUnloaded,        # Marines/colonists unloaded from spacelift ships
    ScoutMeshNetworkFormed, # Multiple scouts formed detection network
    SpyScoutDeployed,     # Spy scout created for espionage mission
    SpyScoutTravel        # Spy scout moved toward target

  GameEvent* = ref object of RootObj
    ## Base type for all game events.
    ## Uses a 'case' statement on `eventType` to hold specific event data.
    turn*: int # Added turn field
    houseId*: Option[HouseId] # House that triggered or is primarily affected
    systemId*: Option[SystemId] # System primarily affected
    description*: string # Human-readable summary for logs/UI
    # Common optional fields used by multiple event types
    sourceHouseId*: Option[HouseId] # Source house for multi-house events
    targetHouseId*: Option[HouseId] # Target house for multi-house events
    targetSystemId*: Option[SystemId] # Target system for operations
    success*: Option[bool] # Whether operation/action succeeded
    detected*: Option[bool] # Whether operation was detected
    details*: Option[string] # Additional details for various events
    fleetId*: Option[FleetId] # Fleet involved in event
    newOwner*: Option[HouseId] # New owner after ownership change
    oldOwner*: Option[HouseId] # Previous owner before ownership change

    case eventType*: GameEventType
    of General, Battle, BattleOccurred, Bombardment, ResourceWarning,
       ThreatDetected, AutomationCompleted:
      message*: string # Generic message or simple description

    of OrderIssued, OrderCompleted, OrderRejected, OrderFailed, OrderAborted:
      ## Events for fleet and other orders (fleetId/details in common fields)
      orderType*: Option[string] # String representation of the order type (e.g., "MoveFleet", "BuildFleet")
      reason*: Option[string] # Why it failed/rejected/aborted

    of CombatResult, SystemCaptured, ColonyCaptured, InvasionRepelled:
      ## Events for combat outcomes (newOwner/oldOwner in common fields)
      attackingHouseId*: Option[HouseId]
      defendingHouseId*: Option[HouseId]
      outcome*: Option[string] # "Victory", "Defeat", "Draw", "MutualAnnihilation" for CombatResult
      totalAttackStrength*: Option[int]
      totalDefenseStrength*: Option[int]
      attackerLosses*: Option[int]
      defenderLosses*: Option[int]

    of Espionage, SpyMissionSucceeded, SabotageConducted, TechTheftExecuted, AssassinationAttempted,
       EconomicManipulationExecuted, CyberAttackConducted, PsyopsCampaignLaunched,
       IntelligenceTheftExecuted, DisinformationPlanted, CounterIntelSweepExecuted, SpyMissionDetected:
      ## Events for espionage operations (success/detected in common fields)
      operationType*: Option[esp_types.EspionageAction] # e.g., SabotageHigh, TechTheft

    of Diplomacy, WarDeclared, PeaceSigned, DiplomaticRelationChanged,
       TreatyProposed, TreatyAccepted, TreatyBroken:
      ## Events for diplomatic actions (success in common fields)
      action*: Option[string] # e.g., "ProposeAlliance", "DeclareWar"
      proposalType*: Option[string] # e.g., "NonAggressionPact", "Alliance"
      oldState*: Option[DiplomaticState]
      newState*: Option[DiplomaticState]
      changeReason*: Option[string] # Why the relation changed or treaty was broken

    of Research, TechAdvance:
      ## Research events (houseId in common fields)
      techField*: TechField
      oldLevel*: Option[int]
      newLevel*: Option[int]
      breakthrough*: Option[string] # "Minor", "Major", "Revolutionary"

    of Economy, ConstructionStarted, PopulationTransfer:
      ## Economic events (details in common fields)
      category*: Option[string] # "Income", "Maintenance", "Production" for generic Economy
      amount*: Option[int] # PP, IU, etc.

    of Colony, ColonyEstablished, BuildingCompleted, UnitRecruited, UnitDisbanded, TerraformComplete:
      ## Colony events (newOwner/oldOwner/details in common fields)
      colonyEventType*: Option[string] # "Established", "Lost", "Damage", "BuildingCompleted", "UnitRecruited", "UnitDisbanded", "TerraformComplete"

    of Fleet, FleetDestroyed, ShipCommissioned, ScoutDestroyed:
      ## Fleet events (fleetId/details in common fields)
      fleetEventType*: Option[string] # "Created", "Destroyed", "Crippled", "Repaired" for generic Fleet
      shipClass*: Option[ShipClass] # For fleet creation/destruction/crippling/commissioning/scout destruction

    of Intelligence, IntelGathered, ScoutDetected:
      ## Intelligence events (details in common fields)
      intelType*: Option[string] # "ScoutReport", "SpyReport", "CombatIntel" for IntelGathered

    of Prestige, PrestigeGained, PrestigeLost:
      ## Prestige events (details in common fields)
      changeAmount*: Option[int]

    of HouseEliminated:
      eliminatedBy*: Option[HouseId] # House that eliminated them

    # Combat Theater/Phase Events
    of CombatTheaterBegan, CombatTheaterCompleted:
      theater*: Option[string] # "SpaceCombat", "OrbitalCombat", "PlanetaryCombat"
      attackers*: Option[seq[HouseId]] # Houses attacking
      defenders*: Option[seq[HouseId]] # Houses defending
      roundNumber*: Option[int] # Current round number
      casualties*: Option[seq[HouseId]] # Houses with casualties this theater

    of CombatPhaseBegan, CombatPhaseCompleted:
      phase*: Option[string] # "RaiderAmbush", "FighterIntercept", "CapitalEngagement"
      roundNumberPhase*: Option[int] # Round number
      phaseRounds*: Option[int] # Rounds in this phase
      phaseCasualties*: Option[seq[HouseId]] # Houses with casualties this phase

    # Detection & Stealth Events
    of RaiderDetected:
      raiderFleetId*: Option[FleetId] # Fleet that was detected
      detectorHouse*: Option[HouseId] # House that detected
      detectorType*: Option[string] # "Scout", "Starbase"
      eliRoll*: Option[int] # ELI detection roll
      clkRoll*: Option[int] # CLK cloaking roll
      meshBonus*: Option[int] # Mesh network bonus (+1, +2, +3)

    of RaiderAmbush:
      ambushFleetId*: Option[FleetId] # Raider fleet executing ambush
      ambushTargetHouse*: Option[HouseId] # Target of ambush
      ambushBonus*: Option[int] # CER bonus (+4 for ambush)

    of EliMeshNetworkFormed:
      meshHouse*: Option[HouseId] # House with mesh network
      scoutCount*: Option[int] # Number of scouts in mesh
      meshBonusEli*: Option[int] # Mesh network ELI bonus (+1, +2, +3)

    # Fighter/Carrier Events
    of FighterDeployed:
      carrierFleetId*: Option[FleetId] # Carrier deploying fighters
      fighterSquadronId*: Option[string] # Fighter squadron ID
      deploymentPhase*: Option[string] # "PhaseTwo" (Fighter Intercept phase)

    of FighterEngagement:
      attackerFighter*: Option[string] # Attacker fighter squadron ID
      targetFighter*: Option[string] # Target squadron ID
      fighterDamage*: Option[int] # Damage dealt (full AS, no CER)
      noCerRoll*: Option[bool] # Always true for fighters

    of CarrierDestroyed:
      destroyedCarrierId*: Option[FleetId] # Carrier destroyed
      embarkedFightersLost*: Option[int] # Number of embarked fighters destroyed

    # Combat Round Events
    of WeaponFired:
      attackerSquadronId*: Option[string] # Attacker squadron
      weaponType*: Option[string] # Weapon class (e.g., "Beam", "Missile")
      targetSquadronId*: Option[string] # Target squadron
      cerRollValue*: Option[int] # CER roll (1d10)
      cerModifier*: Option[int] # Total CER modifiers (ambush, scouts, morale, etc.)
      damageDealt*: Option[int] # Damage dealt

    of ShipDamaged:
      damagedSquadronId*: Option[string] # Squadron that took damage
      damageAmount*: Option[int] # Damage taken
      shipNewState*: Option[string] # "Crippled" or "Undamaged"
      remainingDs*: Option[int] # Remaining defense strength

    of ShipDestroyed:
      destroyedSquadronId*: Option[string] # Squadron destroyed
      killedBy*: Option[HouseId] # House that destroyed the squadron
      criticalHit*: Option[bool] # Whether it was a critical hit
      overkillDamage*: Option[int] # Damage beyond destruction

    of FleetRetreat:
      retreatingFleetId*: Option[FleetId] # Fleet retreating
      retreatReason*: Option[string] # "ROE", "Morale", "Losses"
      retreatThreshold*: Option[int] # Threshold that triggered retreat
      retreatCasualties*: Option[int] # Casualties at time of retreat

    # Bombardment-Specific Events (Complete Tactical Data)
    of BombardmentRoundBegan:
      bombRound*: Option[int] # Round number (1, 2, or 3)
      bombardFleetId*: Option[FleetId] # Fleet conducting bombardment
      bombardPlanet*: Option[SystemId] # Planet being bombarded

    of BombardmentRoundCompleted:
      completedRound*: Option[int] # Round that completed
      batteriesDestroyed*: Option[int] # Ground batteries destroyed
      batteriesCrippled*: Option[int] # Ground batteries crippled
      shieldBlockedHits*: Option[int] # Hits blocked by planetary shields
      groundForcesDamaged*: Option[int] # Ground force units damaged
      infrastructureDestroyed*: Option[int] # IU destroyed
      populationKilled*: Option[int] # PU killed
      facilitiesDestroyed*: Option[int] # Facilities destroyed
      attackerCasualties*: Option[int] # Bombarding squadrons damaged/destroyed

    of ShieldActivated:
      shieldLevel*: Option[int] # Shield level (1-6 for SLD1-6)
      shieldRoll*: Option[int] # Shield activation roll (1d20)
      shieldThreshold*: Option[int] # Threshold to activate
      percentBlocked*: Option[int] # Percentage of hits blocked (25%-50%)

    of GroundBatteryFired:
      batteryId*: Option[int] # Battery ID
      batteryTargetSquadron*: Option[string] # Squadron targeted
      batteryDamage*: Option[int] # Damage dealt to squadron

    # Invasion/Blitz Events
    of InvasionBegan:
      invasionFleetId*: Option[FleetId] # Fleet conducting invasion
      marinesLanding*: Option[int] # Number of marines landing
      invasionTargetColony*: Option[SystemId] # Colony being invaded

    of BlitzBegan:
      blitzFleetId*: Option[FleetId] # Fleet conducting blitz
      blitzMarinesLanding*: Option[int] # Marines landing
      transportsVulnerable*: Option[bool] # Transports vulnerable during bombardment
      marineAsPenalty*: Option[float] # Marine AS penalty (0.5x for blitz)

    of GroundCombatRound:
      attackersGround*: Option[seq[HouseId]] # Attacking ground forces
      defendersGround*: Option[seq[HouseId]] # Defending ground forces
      attackerRoll*: Option[int] # Attacker ground CER roll
      defenderRoll*: Option[int] # Defender ground CER roll
      groundCasualties*: Option[seq[HouseId]] # Houses with ground casualties

    # Starbase Events
    of StarbaseCombat:
      starbaseSystemId*: Option[SystemId] # System with starbase
      starbaseTargetId*: Option[string] # Target squadron
      starbaseAs*: Option[int] # Starbase attack strength
      starbaseDs*: Option[int] # Starbase defense strength
      starbaseEliBonus*: Option[int] # ELI detection bonus (+2 for starbases)

    # Fleet Operations Events (Phase 7b)
    of StandingOrderSet:
      standingOrderType*: Option[string] # e.g., "AutoColonize", "PatrolRoute"
      standingOrderEnabled*: Option[bool] # Whether enabled
      activationDelay*: Option[int] # Turns until activation

    of StandingOrderActivated:
      activatedOrderType*: Option[string] # Standing order that activated
      generatedFleetOrderType*: Option[string] # Fleet order it generated (e.g., "Move", "Colonize")
      triggerReason*: Option[string] # Why it activated

    of StandingOrderSuspended:
      suspendedOrderType*: Option[string] # Standing order that was suspended
      suspendReason*: Option[string] # "ExplicitOrderIssued", "Disabled", "GlobalToggle"

    of FleetEncounter:
      encounteringFleetId*: Option[FleetId] # Fleet that detected enemy
      encounteredFleetIds*: Option[seq[FleetId]] # Enemy fleets detected
      encounterLocation*: Option[SystemId] # Where encounter occurred
      diplomaticStatus*: Option[string] # "Enemy", "Hostile", "Neutral"

    of FleetMerged:
      sourceFleetId*: Option[FleetId] # Fleet that was merged (dissolved)
      targetFleetIdMerge*: Option[FleetId] # Fleet that absorbed squadrons
      squadronsMerged*: Option[int] # Number of squadrons transferred
      mergeLocation*: Option[SystemId] # Where merge occurred

    of FleetDetachment:
      parentFleetId*: Option[FleetId] # Original fleet
      newFleetId*: Option[FleetId] # Newly created fleet
      squadronsDetached*: Option[int] # Number of squadrons split off
      detachmentLocation*: Option[SystemId] # Where detachment occurred

    of FleetTransfer:
      transferSourceFleetId*: Option[FleetId] # Fleet losing squadrons
      transferTargetFleetId*: Option[FleetId] # Fleet gaining squadrons
      squadronsTransferred*: Option[int] # Number of squadrons transferred
      transferLocation*: Option[SystemId] # Where transfer occurred

    of CargoLoaded:
      loadingFleetId*: Option[FleetId] # Fleet loading cargo
      cargoType*: Option[string] # "Marines" or "Colonists"
      cargoQuantity*: Option[int] # Number of units loaded
      loadLocation*: Option[SystemId] # Colony where loaded

    of CargoUnloaded:
      unloadingFleetId*: Option[FleetId] # Fleet unloading cargo
      unloadCargoType*: Option[string] # "Marines" or "Colonists"
      unloadCargoQuantity*: Option[int] # Number of units unloaded
      unloadLocation*: Option[SystemId] # Where unloaded

    of ScoutMeshNetworkFormed:
      meshFleetIds*: Option[seq[FleetId]] # Fleets forming mesh
      totalScouts*: Option[int] # Total scouts in network
      meshEliBonus*: Option[int] # Detection bonus (+1, +2, +3)
      meshLocation*: Option[SystemId] # Where network formed

    of SpyScoutDeployed:
      spyScoutId*: Option[string] # Spy scout unique ID
      deployingHouseId*: Option[HouseId] # House deploying scout
      spyMissionType*: Option[string] # "SpyPlanet", "SpySystem", "HackStarbase"
      spyTargetSystem*: Option[SystemId] # Target system
      spyTargetHouse*: Option[HouseId] # Target house

    of SpyScoutTravel:
      travelingSpyScoutId*: Option[string] # Spy scout ID
      travelOrigin*: Option[SystemId] # Starting location
      travelDestination*: Option[SystemId] # Destination
      travelProgress*: Option[int] # Jumps completed / total jumps
      detectionRisk*: Option[bool] # Whether passing through hostile systems

  CombatReport* = object
    systemId*: SystemId
    attackers*: seq[HouseId]
    defenders*: seq[HouseId]
    attackerLosses*: int
    defenderLosses*: int
    victor*: Option[HouseId]
