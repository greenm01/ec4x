## StarMap Type Definition for EC4X
##
## This module defines the main StarMap object, which is the central data structure
## for representing the game world map.

import std/tables
import ./types # Import Hex, System, JumpLane, etc.

type
  StarMap* = object
    systems*: Table[uint, System]
    lanes*: seq[JumpLane]
    laneMap*: Table[(uint, uint), LaneType]  # Bidirectional lane type cache
    distanceMatrix*: Table[(uint, uint), uint32]  # Pre-computed hex distances
    adjacency*: Table[uint, seq[uint]]
    playerCount*: int
    numRings*: uint32
    hubId*: uint
    playerSystemIds*: seq[uint]
    seed*: int64  # Seed for deterministic but varied generation
