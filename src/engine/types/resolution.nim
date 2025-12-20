## Common types for resolution modules

import std/[tables, options]
import ./[core, espionage, tech, diplomacy]

type
  # Base event data (common to all events)
  BaseEvent* = object
    turn*: int32
    houseId*: Option[HouseId]
    systemId*: Option[SystemId]
    description*: string

  # Order events
  OrderEventKind* {.pure.} = enum
    Issued, Completed, Rejected, Failed, Aborted, Arrived

  OrderEvent* = object
    base*: BaseEvent
    kind*: OrderEventKind
    fleetId*: Option[FleetId]
    orderType*: string
    reason*: Option[string]

  # Combat events
  CombatOutcome* {.pure.} = enum
    Victory, Defeat, Draw, MutualAnnihilation

  CombatEvent* = object
    base*: BaseEvent
    attacker*: HouseId
    defender*: HouseId
    outcome*: CombatOutcome
    attackStrength*: int32
    defenseStrength*: int32
    attackerLosses*: int32
    defenderLosses*: int32
    systemCaptured*: bool
    colonyCaptured*: bool
    newOwner*: Option[HouseId]

  # Espionage events
  EspionageEvent* = object
    base*: BaseEvent
    attacker*: HouseId
    target*: HouseId
    operation*: EspionageAction
    success*: bool
    detected*: bool
    targetSystem*: Option[SystemId]

  # Research events
  ResearchEvent* = object
    base*: BaseEvent
    techField*: TechField
    oldLevel*: int32
    newLevel*: int32
    breakthrough*: Option[string]

  # Diplomatic events
  DiplomaticEvent* = object
    base*: BaseEvent
    sourceHouse*: HouseId
    targetHouse*: HouseId
    action*: string
    oldState*: Option[DiplomaticState]
    newState*: Option[DiplomaticState]
    reason*: Option[string]

  # Fleet events
  FleetEventKind* {.pure.} = enum
    Created, Destroyed, Disbanded, Retreated, Merged, Detached

  FleetEvent* = object
    base*: BaseEvent
    kind*: FleetEventKind
    fleetId*: FleetId
    shipClass*: Option[ShipClass]
    salvageValue*: int32
    reason*: Option[string]

  # Squadron events
  SquadronEventKind* {.pure.} = enum
    Commissioned, Destroyed, Damaged, Disbanded, Scrapped

  SquadronEvent* = object
    base*: BaseEvent
    kind*: SquadronEventKind
    squadronId*: SquadronId
    fleetId*: Option[FleetId]
    newState*: Option[string]
    killedBy*: Option[HouseId]

  # Colony events
  ColonyEventKind* {.pure.} = enum
    Established, Captured, Bombarded, TerraformComplete

  ColonyEvent* = object
    base*: BaseEvent
    kind*: ColonyEventKind
    colonyId*: ColonyId
    newOwner*: Option[HouseId]
    oldOwner*: Option[HouseId]
    damage*: Option[int32]

  # Construction events
  ConstructionEvent* = object
    base*: BaseEvent
    colonyId*: ColonyId
    projectType*: string
    itemId*: string
    completed*: bool

  # Prestige events
  PrestigeEvent* = object
    base*: BaseEvent
    changeAmount*: int32
    reason*: string

  # Bombardment events
  BombardmentRound* = object
    base*: BaseEvent
    roundNumber*: int32
    fleetId*: FleetId
    batteriesDestroyed*: int32
    batteriesCrippled*: int32
    shieldBlockedHits*: int32
    infrastructureDestroyed*: int32
    populationKilled*: int32
    attackerCasualties*: int32

  # Intelligence events
  IntelligenceEvent* = object
    base*: BaseEvent
    intelType*: string
    targetHouse*: Option[HouseId]
    targetSystem*: Option[SystemId]

  # Event collections
  GameEvents* = object
    orders*: seq[OrderEvent]
    combat*: seq[CombatEvent]
    espionage*: seq[EspionageEvent]
    research*: seq[ResearchEvent]
    diplomacy*: seq[DiplomaticEvent]
    fleets*: seq[FleetEvent]
    squadrons*: seq[SquadronEvent]
    colonies*: seq[ColonyEvent]
    construction*: seq[ConstructionEvent]
    prestige*: seq[PrestigeEvent]
    bombardment*: seq[BombardmentRound]
    intelligence*: seq[IntelligenceEvent]

  # Turn report aggregates events by category
  TurnReport* = object
    turn*: int32
    events*: GameEvents
