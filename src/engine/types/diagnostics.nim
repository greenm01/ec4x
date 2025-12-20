## Transient data collected during turn resolution for a single house.
## This is passed to the diagnostics system to avoid polluting the core House object.

type
  TurnResolutionReport* = object
    # Research
    researchERP*: int32
    researchSRP*: int32
    researchTRP*: int32
    researchBreakthroughs*: int32
    # Maintenance
    maintenanceCostTotal*: int32
    treasuryDeficit*: bool
    maintenanceCostDeficit*: int32
    # Espionage
    espionageAttempts*: int32
    espionageSuccess*: int32
    espionageDetected*: int32
    techThefts*: int32
    sabotage*: int32
    assassinations*: int32
    cyberAttacks*: int32
    ebpSpent*: int32
    cipSpent*: int32
    counterIntelSuccesses*: int32
    # Combat
    spaceCombatWins*: int32
    spaceCombatLosses*: int32
    spaceCombatTotal*: int32
    raiderAmbushSuccess*: int32
    raiderAmbushAttempts*: int32
    orbitalFailures*: int32
    orbitalTotal*: int32
    combatCERAverage*: int32
    bombardmentRounds*: int32
    groundCombatVictories*: int32
    retreatsExecuted*: int32
    criticalHitsDealt*: int32
    criticalHitsReceived*: int32
    cloakedAmbushSuccess*: int32
    shieldsActivated*: int32
    # Detection
    raidersDetected*: int32
    raidersStealthSuccess*: int32
    eliDetectionAttempts*: int32
    eliRollsSum*: int32
    clkRollsSum*: int32
    scoutsDetected*: int32
    scoutsDetectedBy*: int32
    # Fleet Activity
    fleetsMoved*: int32
    fleetsWithOrders*: int32
    stuckFleets*: int32
    # Colonization
    systemsColonized*: int32
    failedColonizations*: int32
    # Diplomacy
    pactFormations*: int32
    pactBreaks*: int32
    hostilityDeclarations*: int32
    warDeclarations*: int32
    # Economy
    infrastructureDamage*: int32
    salvageValueRecovered*: int32
    # Population
    popTransfersCompleted*: int32
    popTransfersLost*: int32
    ptuTransferredTotal*: int32
    # Construction & Commissioning
    shipsCommissioned*: int32
    etacsCommissioned*: int32
    squadronsCommissioned*: int32
    # Logistics
    fightersDisbanded*: int32
    # Invasions
    totalInvasions*: int32
