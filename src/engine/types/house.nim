import std/tables
import ./[core, tech, espionage, income]

type
  House* = object
    id*: HouseId
    name*: string
    prestige*: int32
    treasury*: int32
    techTree*: TechTree
    espionageBudget*: EspionageBudget
    taxPolicy*: TaxPolicy
    isEliminated*: bool
    eliminatedTurn*: int32

  Houses* = object
    data: seq[House]
    index: Table[HouseId, int]
    nextId: uint32
