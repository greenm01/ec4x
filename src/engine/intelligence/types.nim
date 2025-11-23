## Intelligence Report Types
##
## Defines intelligence data structures for spy scout missions
## Per intel.md and operations.md specifications

import std/[tables, options]
import ../../common/types/[core, tech]

type
  IntelQuality* {.pure.} = enum
    ## Quality/source of intelligence
    Visual     # Visual detection from fleet presence
    Scan       # Active sensor scan (future)
    Spy        # Espionage operation
    Perfect    # Owned/current information

  ColonyIntelReport* = object
    ## Intelligence on an enemy colony (SpyOnPlanet mission)
    ## Per intel.md:107-121
    colonyId*: SystemId
    targetOwner*: HouseId        # Owner of the colony
    gatheredTurn*: int           # When intel was gathered
    quality*: IntelQuality

    # Colony stats (what was observed)
    population*: int
    industry*: int               # IU count
    defenses*: int               # Ground unit count
    starbaseLevel*: int          # 0 if no starbase
    constructionQueue*: seq[string]  # Item IDs in construction (if successful spy)

  SystemIntelReport* = object
    ## Intelligence on enemy fleets in a system (SpyOnSystem mission)
    ## Per intel.md:96-105
    systemId*: SystemId
    gatheredTurn*: int
    quality*: IntelQuality

    # Fleet information
    detectedFleets*: seq[FleetIntel]

  FleetIntel* = object
    ## Intel on a specific fleet
    fleetId*: FleetId
    owner*: HouseId
    location*: SystemId
    shipCount*: int
    # Detailed composition (only if quality = Spy or Perfect)
    squadronDetails*: Option[seq[SquadronIntel]]

  SquadronIntel* = object
    ## Detailed squadron information
    squadronId*: string
    shipClass*: string  # Ship class name
    shipCount*: int
    techLevel*: int
    hullIntegrity*: Option[int]  # % if known

  StarbaseIntelReport* = object
    ## Intelligence from hacking a starbase (HackStarbase mission)
    ## Per intel.md and operations.md:6.2.11 - "economic and R&D intelligence"
    systemId*: SystemId
    targetOwner*: HouseId
    gatheredTurn*: int
    quality*: IntelQuality

    # Economic intelligence
    treasuryBalance*: Option[int]       # PP balance
    grossIncome*: Option[int]           # Gross PP/turn
    netIncome*: Option[int]             # Net PP/turn
    taxRate*: Option[float]             # Current tax rate

    # R&D intelligence
    researchAllocations*: Option[tuple[erp: int, srp: int, trp: int]]
    currentResearch*: Option[string]    # Current tech being researched
    techLevels*: Option[TechLevel]      # Current tech levels

  EspionageActivityReport* = object
    ## Record of detected espionage activity against this house
    ## Generated when espionage attempts are detected
    turn*: int
    perpetrator*: HouseId
    action*: string           # Action type description
    targetSystem*: Option[SystemId]  # If targeted specific system
    detected*: bool           # Was the perpetrator identified?
    description*: string

  IntelligenceDatabase* = object
    ## Collection of all intelligence reports for a house
    ## Stored per-house in GameState
    colonyReports*: Table[SystemId, ColonyIntelReport]
    systemReports*: Table[SystemId, SystemIntelReport]
    starbaseReports*: Table[SystemId, StarbaseIntelReport]
    espionageActivity*: seq[EspionageActivityReport]  # Log of espionage against this house

proc newIntelligenceDatabase*(): IntelligenceDatabase =
  ## Create empty intelligence database
  result.colonyReports = initTable[SystemId, ColonyIntelReport]()
  result.systemReports = initTable[SystemId, SystemIntelReport]()
  result.starbaseReports = initTable[SystemId, StarbaseIntelReport]()
  result.espionageActivity = @[]

proc addColonyReport*(db: var IntelligenceDatabase, report: ColonyIntelReport) =
  ## Add or update colony intelligence report
  db.colonyReports[report.colonyId] = report

proc addSystemReport*(db: var IntelligenceDatabase, report: SystemIntelReport) =
  ## Add or update system intelligence report
  db.systemReports[report.systemId] = report

proc addStarbaseReport*(db: var IntelligenceDatabase, report: StarbaseIntelReport) =
  ## Add or update starbase intelligence report
  db.starbaseReports[report.systemId] = report

proc addEspionageActivity*(db: var IntelligenceDatabase, report: EspionageActivityReport) =
  ## Add espionage activity report to log
  db.espionageActivity.add(report)

proc getColonyIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[ColonyIntelReport] =
  ## Retrieve colony intel if available
  if systemId in db.colonyReports:
    return some(db.colonyReports[systemId])
  return none(ColonyIntelReport)

proc getSystemIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[SystemIntelReport] =
  ## Retrieve system intel if available
  if systemId in db.systemReports:
    return some(db.systemReports[systemId])
  return none(SystemIntelReport)

proc getStarbaseIntel*(db: IntelligenceDatabase, systemId: SystemId): Option[StarbaseIntelReport] =
  ## Retrieve starbase intel if available
  if systemId in db.starbaseReports:
    return some(db.starbaseReports[systemId])
  return none(StarbaseIntelReport)

proc getIntelStaleness*(report: ColonyIntelReport | SystemIntelReport | StarbaseIntelReport, currentTurn: int): int =
  ## Calculate how many turns old this intel is
  return currentTurn - report.gatheredTurn
