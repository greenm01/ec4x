## GOAP Parameter Definitions
##
## Defines parameter space for GOAP system tuning
## Similar to src/ai/tuning/ but focused on GOAP strategic planning parameters

import std/[tables, sequtils, strformat]
import ../../rba/orders/phase1_5_goap

# =============================================================================
# Parameter Definitions
# =============================================================================

type
  GOAPParamSet* = object
    ## A specific configuration of GOAP parameters for testing
    id*: int                        # Unique ID for this parameter set
    name*: string                   # Descriptive name
    config*: GOAPConfig             # The actual GOAP configuration
    description*: string            # What this tests

  GOAPSweepSpace* = object
    ## Defines the parameter space to sweep
    planningDepths*: seq[int]                # e.g., [3, 5, 7, 10]
    confidenceThresholds*: seq[float]        # e.g., [0.5, 0.6, 0.7, 0.8]
    maxConcurrentPlans*: seq[int]            # e.g., [3, 5, 7, 10]
    defensePriorities*: seq[float]           # e.g., [0.3, 0.5, 0.7, 0.9]
    offensePriorities*: seq[float]           # e.g., [0.3, 0.5, 0.7, 0.9]

# =============================================================================
# Default Sweep Spaces
# =============================================================================

proc defaultSweepSpace*(): GOAPSweepSpace =
  ## Default parameter sweep space
  ##
  ## Conservative range for initial testing

  GOAPSweepSpace(
    planningDepths: @[3, 5, 7],
    confidenceThresholds: @[0.5, 0.6, 0.7],
    maxConcurrentPlans: @[3, 5, 7],
    defensePriorities: @[0.5, 0.7, 0.9],
    offensePriorities: @[0.3, 0.5, 0.7]
  )

proc aggressiveSweepSpace*(): GOAPSweepSpace =
  ## Sweep space biased toward aggressive play

  GOAPSweepSpace(
    planningDepths: @[3, 5],           # Shorter horizon
    confidenceThresholds: @[0.4, 0.5, 0.6],  # Lower threshold
    maxConcurrentPlans: @[5, 7, 10],   # More concurrent plans
    defensePriorities: @[0.3, 0.4, 0.5],     # Low defense
    offensePriorities: @[0.7, 0.8, 0.9]      # High offense
  )

proc defensiveSweepSpace*(): GOAPSweepSpace =
  ## Sweep space biased toward defensive play

  GOAPSweepSpace(
    planningDepths: @[5, 7, 10],       # Longer horizon
    confidenceThresholds: @[0.7, 0.8, 0.9],  # Higher threshold
    maxConcurrentPlans: @[3, 5],       # Fewer concurrent plans
    defensePriorities: @[0.7, 0.8, 0.9],     # High defense
    offensePriorities: @[0.2, 0.3, 0.4]      # Low offense
  )

# =============================================================================
# Parameter Set Generation
# =============================================================================

proc generateParameterSets*(space: GOAPSweepSpace): seq[GOAPParamSet] =
  ## Generate all combinations of parameters in the sweep space
  ##
  ## Returns: All possible parameter combinations

  result = @[]
  var id = 0

  for depth in space.planningDepths:
    for confidence in space.confidenceThresholds:
      for maxPlans in space.maxConcurrentPlans:
        for defense in space.defensePriorities:
          for offense in space.offensePriorities:
            id.inc()

            let config = GOAPConfig(
              enabled: true,
              planningDepth: depth,
              confidenceThreshold: confidence,
              maxConcurrentPlans: maxPlans,
              defensePriority: defense,
              offensePriority: offense,
              logPlans: false
            )

            let name = &"d{depth}_c{int(confidence*100)}_m{maxPlans}_def{int(defense*100)}_off{int(offense*100)}"

            result.add(GOAPParamSet(
              id: id,
              name: name,
              config: config,
              description: &"Depth={depth}, Conf={confidence}, MaxPlans={maxPlans}, " &
                          &"Def={defense}, Off={offense}"
            ))

proc generateStratifiedSample*(space: GOAPSweepSpace, samplesPerDim: int = 3): seq[GOAPParamSet] =
  ## Generate a stratified sample of parameter space
  ##
  ## Instead of full combinatorial explosion, samples uniformly across each dimension
  ## Much faster for initial exploration

  result = @[]
  var id = 0

  # Sample uniformly from each dimension
  let depths = space.planningDepths[0 ..< min(samplesPerDim, space.planningDepths.len)]
  let confidences = space.confidenceThresholds[0 ..< min(samplesPerDim, space.confidenceThresholds.len)]
  let maxPlans = space.maxConcurrentPlans[0 ..< min(samplesPerDim, space.maxConcurrentPlans.len)]
  let defenses = space.defensePriorities[0 ..< min(samplesPerDim, space.defensePriorities.len)]
  let offenses = space.offensePriorities[0 ..< min(samplesPerDim, space.offensePriorities.len)]

  # Generate combinations
  for depth in depths:
    for confidence in confidences:
      for plans in maxPlans:
        for defense in defenses:
          for offense in offenses:
            id.inc()

            let config = GOAPConfig(
              enabled: true,
              planningDepth: depth,
              confidenceThreshold: confidence,
              maxConcurrentPlans: plans,
              defensePriority: defense,
              offensePriority: offense,
              logPlans: false
            )

            result.add(GOAPParamSet(
              id: id,
              name: &"strat_{id}",
              config: config,
              description: &"Stratified sample #{id}"
            ))

# =============================================================================
# Preset Parameter Sets
# =============================================================================

proc getPresetParameterSets*(): seq[GOAPParamSet] =
  ## Get hand-crafted preset parameter sets for common strategies
  ##
  ## Useful for baseline comparisons

  result = @[]

  # Baseline: Default GOAP config
  result.add(GOAPParamSet(
    id: 1,
    name: "baseline",
    config: defaultGOAPConfig(),
    description: "Default GOAP configuration (balanced)"
  ))

  # Aggressive preset
  result.add(GOAPParamSet(
    id: 2,
    name: "aggressive",
    config: GOAPConfig(
      enabled: true,
      planningDepth: 3,
      confidenceThreshold: 0.5,
      maxConcurrentPlans: 7,
      defensePriority: 0.4,
      offensePriority: 0.9,
      logPlans: false
    ),
    description: "Aggressive strategy (high offense, short planning)"
  ))

  # Turtle preset
  result.add(GOAPParamSet(
    id: 3,
    name: "turtle",
    config: GOAPConfig(
      enabled: true,
      planningDepth: 7,
      confidenceThreshold: 0.8,
      maxConcurrentPlans: 3,
      defensePriority: 0.9,
      offensePriority: 0.3,
      logPlans: false
    ),
    description: "Turtle strategy (high defense, long planning)"
  ))

  # Opportunistic preset
  result.add(GOAPParamSet(
    id: 4,
    name: "opportunistic",
    config: GOAPConfig(
      enabled: true,
      planningDepth: 5,
      confidenceThreshold: 0.6,
      maxConcurrentPlans: 5,
      defensePriority: 0.6,
      offensePriority: 0.6,
      logPlans: false
    ),
    description: "Opportunistic strategy (balanced, flexible)"
  ))

  # No GOAP (control)
  result.add(GOAPParamSet(
    id: 5,
    name: "no_goap",
    config: GOAPConfig(
      enabled: false,
      planningDepth: 0,
      confidenceThreshold: 0.0,
      maxConcurrentPlans: 0,
      defensePriority: 0.0,
      offensePriority: 0.0,
      logPlans: false
    ),
    description: "Pure RBA (no GOAP) - control baseline"
  ))

# =============================================================================
# Parameter Space Statistics
# =============================================================================

proc countParameterSets*(space: GOAPSweepSpace): int =
  ## Count total number of parameter combinations

  space.planningDepths.len *
  space.confidenceThresholds.len *
  space.maxConcurrentPlans.len *
  space.defensePriorities.len *
  space.offensePriorities.len

proc estimatedSweepTime*(space: GOAPSweepSpace, gamesPerSet: int, minutesPerGame: float): float =
  ## Estimate total time for parameter sweep in hours

  let totalSets = countParameterSets(space)
  let totalGames = totalSets * gamesPerSet
  let totalMinutes = totalGames.float * minutesPerGame

  totalMinutes / 60.0  # Convert to hours
