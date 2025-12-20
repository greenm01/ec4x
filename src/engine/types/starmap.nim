## Map-related type definitions for EC4X
##
## This module contains the type definitions for the hexagonal grid (Hex),
## star systems (System), jump lanes (JumpLane), and other related map types.
import std/[tables, options]
import ./core

type
  Hex* = object
    q*: int32
    r*: int32
  
  System* = object
    id*: SystemId
    coords*: Hex
    ring*: uint32
    player*: Option[PlayerId]
    planetClass*: PlanetClass
    resourceRating*: ResourceRating
  
  Systems* = object
    data: seq[System]
    index: Table[SystemId, int]
    nextId: uint32
  
  JumpLane* = object
    source*: SystemId
    destination*: SystemId
    laneType*: LaneType
  
  JumpLanes* = object
    data: seq[JumpLane]
    # Lookup tables for pathfinding
    adjacency: Table[SystemId, seq[SystemId]]
    laneTypes: Table[(SystemId, SystemId), LaneType]
  
  PathResult* = object
    path*: seq[SystemId]
    totalCost*: uint32
    found*: bool
  
  StarMap* = object
    systems*: Systems
    lanes*: JumpLanes
    distanceMatrix*: Table[(SystemId, SystemId), uint32]
    playerCount*: int32
    numRings*: uint32
    hubId*: SystemId  # Not uint
    playerSystemIds*: seq[SystemId]  # Not uint
    seed*: int64

  PlanetClass* {.pure.} = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    Extreme      # Level I   - 1-20 PU
    Desolate     # Level II  - 21-60 PU
    Hostile      # Level III - 61-180 PU
    Harsh        # Level IV  - 181-500 PU
    Benign       # Level V   - 501-1000 PU
    Lush         # Level VI  - 1k-2k PU
    Eden         # Level VII - 2k+ PU

  ResourceRating* {.pure.} = enum
    ## System resource availability
    VeryPoor
    Poor
    Abundant
    Rich
    VeryRich
