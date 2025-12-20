import military/[fleet]

type
  GameState* = object
      gameId*: int32
      turn*: int
      phase*: GamePhase
      starMap*: StarMap
      houses*: Table[HouseId, House]
      lastTurnReports*: Table[HouseId, TurnResolutionReport] # Transient data for diagnostics
      homeworlds*: Table[HouseId, SystemId]  # Track homeworld system per house
      colonies*: Table[SystemId, Colony]
      fleets*: Table[FleetId, Fleet]
      fleetOrders*: Table[FleetId, FleetOrder]  # Persistent fleet orders (continue until completed)
      activeSpyMissions*: Table[FleetId, ActiveSpyMission]  # Active spy missions (fleet-based system)
      arrivedFleets*: Table[FleetId, SystemId]  # Fleets that arrived at order targets (checked in Conflict/Income phase)
      standingOrders*: Table[FleetId, StandingOrder]  # Standing orders (execute when no explicit order)
      turnDeadline*: int64          # Unix timestamp
      ongoingEffects*: seq[esp_types.OngoingEffect]  # Active espionage effects
      scoutLossEvents*: seq[intel_types.ScoutLossEvent]  # Scout losses for diplomatic processing
      populationInTransit*: seq[pop_types.PopulationInTransit]  # Space Guild population transfers in progress
      pendingProposals*: seq[dip_proposals.PendingProposal]  # Pending diplomatic proposals
      pendingMilitaryCommissions*: seq[econ_types.CompletedProject]  # Military units awaiting commissioning in next Command Phase
      pendingPlanetaryCommissions*: seq[econ_types.CompletedProject]  # Unused - planetary assets commission immediately in Maintenance Phase
      gracePeriodTimers*: Table[HouseId, GracePeriodTracker]  # Grace period tracking for capacity enforcement
      actProgression*: ActProgressionState  # Dynamic game act progression (global, public info)

      # Persistent reverse indices (DoD optimization for O(1) lookups)
      fleetsByLocation*: Table[SystemId, seq[FleetId]]
      fleetsByOwner*: Table[HouseId, seq[FleetId]]
      coloniesByOwner*: Table[HouseId, seq[SystemId]]

      # ID generators
      nextFleetId: int32
      nextSystemId: int32
      nextHouseId: int32
