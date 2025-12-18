## Transient data collected during turn resolution for a single house.
## This is passed to the diagnostics system to avoid polluting the core House object.
import ../common/types/core

type
  TurnResolutionReport* = object
    # Research
    researchERP*: int
    researchSRP*: int
    researchTRP*: int
    researchBreakthroughs*: int
    # Maintenance
    maintenanceCostTotal*: int
    treasuryDeficit*: bool
    maintenanceCostDeficit*: int
    # Espionage
    espionageAttempts*: int
    espionageSuccess*: int
    espionageDetected*: int
    techThefts*: int
    sabotage*: int
    assassinations*: int
    cyberAttacks*: int
    ebpSpent*: int
    cipSpent*: int
    counterIntelSuccesses*: int
    # Combat
    spaceCombatWins*: int
    spaceCombatLosses*: int
    spaceCombatTotal*: int
    raiderAmbushSuccess*: int
    raiderAmbushAttempts*: int
    orbitalFailures*: int
    orbitalTotal*: int
    combatCERAverage*: int
    bombardmentRounds*: int
    groundCombatVictories*: int
    retreatsExecuted*: int
    criticalHitsDealt*: int
    criticalHitsReceived*: int
    cloakedAmbushSuccess*: int
    shieldsActivated*: int
    # Detection
    raidersDetected*: int
    raidersStealthSuccess*: int
    eliDetectionAttempts*: int
    eliRollsSum*: int
    clkRollsSum*: int
    scoutsDetected*: int
    scoutsDetectedBy*: int
    # Fleet Activity
    fleetsMoved*: int
    fleetsWithOrders*: int
    stuckFleets*: int
    # Colonization
    systemsColonized*: int
    failedColonizations*: int
    # Diplomacy
    pactFormations*: int
    pactBreaks*: int
    hostilityDeclarations*: int
    warDeclarations*: int
    # Economy
    infrastructureDamage*: int
    salvageValueRecovered*: int
    # Population
    popTransfersCompleted*: int
    popTransfersLost*: int
    ptuTransferredTotal*: int
    # Construction & Commissioning
    shipsCommissioned*: int
    etacsCommissioned*: int
    squadronsCommissioned*: int
    # Logistics
    fightersDisbanded*: int
    # Invasions
    totalInvasions*: int

proc initTurnResolutionReport*(): TurnResolutionReport =
  ## Initialize an empty report with default zero values.
  result = TurnResolutionReport()
