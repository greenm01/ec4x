## Diplomacy System Types
##
## Type definitions for diplomatic relations per diplomacy.md:8.1
import std/[tables, options]
import ./[core, prestige]

type
  DiplomaticState* {.pure.} = enum
    Neutral, Hostile, Enemy

  DiplomaticActionType* {.pure.} = enum
    DeclareHostile, DeclareEnemy, SetNeutral

  ProposalType* {.pure.} = enum
    TradeAgreement, MilitaryAlliance, TechnologySharing

  ProposalStatus* {.pure.} = enum
    Pending, Accepted, Rejected, Expired, Withdrawn

  PendingProposal* = object
    id*: string
    proposer*: HouseId
    target*: HouseId
    proposalType*: ProposalType
    submittedTurn*: int32
    status*: ProposalStatus
    expiresOnTurn*: int32

  DiplomaticRelation* = object
    sourceHouse*: HouseId
    targetHouse*: HouseId
    state*: DiplomaticState
    sinceTurn*: int32

  DiplomaticCommand* = object
    houseId*: HouseId
    targetHouse*: HouseId
    actionType*: DiplomaticActionType
    proposalId*: Option[string]
    message*: Option[string]

  ViolationRecord* = object
    violator*: HouseId
    victim*: HouseId
    turn*: int32
    description*: string

  ViolationHistory* = object
    houseId*: HouseId  # House with violations
    violations*: seq[ViolationRecord]

  DiplomaticEvent* = object
    houseId*: HouseId
    otherHouse*: HouseId
    oldState*: DiplomaticState
    newState*: DiplomaticState
    turn*: int32
    reason*: string
    prestigeEvents*: seq[PrestigeEvent]

  DiplomaticReport* = object
    turn*: int32
    events*: seq[DiplomaticEvent]
    violations*: seq[ViolationRecord]
