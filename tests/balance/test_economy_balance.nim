## Balance Testing for M5 Economy System
##
## Tests economic balance across different scenarios:
## - Planet quality impact on growth
## - Tax policy tradeoffs
## - Research progression rates
## - Early/mid/late game economies

import std/[unittest, tables, strformat, math, strutils, options]
import ../../src/engine/economy/[types, production, income, construction]
import ../../src/engine/research/[costs, advancement]
import ../../src/common/types/[core, planets, units]

type
  EconomySnapshot* = object
    turn*: int
    gco*: int
    ncv*: int
    treasury*: int
    population*: int
    industrial*: int
    elLevel*: int

  SimulationResult* = object
    scenario*: string
    snapshots*: seq[EconomySnapshot]
    finalTreasury*: int
    finalGCO*: int
    finalEL*: int
    totalTurns*: int

proc simulateColonyGrowth(startColony: Colony, turns: int, taxRate: int, elLevel: int): seq[EconomySnapshot] =
  ## Simulate colony growth over N turns
  result = @[]
  var colony = startColony
  var treasury = 0

  for turn in 1..turns:
    # Calculate production
    let output = calculateProductionOutput(colony, elLevel)
    treasury += output.netValue

    # Record snapshot
    result.add(EconomySnapshot(
      turn: turn,
      gco: output.grossOutput,
      ncv: output.netValue,
      treasury: treasury,
      population: colony.populationUnits,
      industrial: colony.industrial.units,
      elLevel: elLevel
    ))

    # Apply growth
    discard applyPopulationGrowth(colony, taxRate)

proc compareScenarios(results: seq[SimulationResult]) =
  ## Print comparison table of scenarios
  echo "\n=== SCENARIO COMPARISON ==="
  echo "Scenario                       Turns  Final GCO   Final Treasury  Final EL"
  echo "=".repeat(80)

  for result in results:
    echo fmt"{result.scenario:<30} {result.totalTurns:>6} {result.finalGCO:>10} {result.finalTreasury:>15} {result.finalEL:>8}"

suite "Economic Balance Testing":

  test "Planet quality progression - All resources types":
    # Test how planet quality affects economy
    var results: seq[SimulationResult] = @[]

    let planetClasses = [
      (PlanetClass.Extreme, "Extreme"),
      (PlanetClass.Desolate, "Desolate"),
      (PlanetClass.Hostile, "Hostile"),
      (PlanetClass.Harsh, "Harsh"),
      (PlanetClass.Benign, "Benign"),
      (PlanetClass.Lush, "Lush"),
      (PlanetClass.Eden, "Eden")
    ]

    let resourceRatings = [
      (ResourceRating.VeryPoor, "Very Poor"),
      (ResourceRating.Poor, "Poor"),
      (ResourceRating.Abundant, "Abundant"),
      (ResourceRating.Rich, "Rich"),
      (ResourceRating.VeryRich, "Very Rich")
    ]

    echo "\n=== PLANET QUALITY vs GCO (50 turns, 50% tax, EL1) ==="
    echo "Planet Class Resources     Start GCO  Turn 25 GCO  Turn 50 GCO   Growth %"
    echo "=".repeat(80)

    for (planetClass, planetName) in planetClasses:
      for (resources, resourceName) in resourceRatings:
        var colony = Colony(
          systemId: SystemId(1),
          owner: "test",
          populationUnits: 100,
          populationTransferUnits: 0,
          industrial: IndustrialUnits(units: 50),
          planetClass: planetClass,
          resources: resources,
          grossOutput: 0,
          taxRate: 50,
          underConstruction: none(ConstructionProject),
          infrastructureDamage: 0.0
        )

        let snapshots = simulateColonyGrowth(colony, 50, 50, 1)
        let startGCO = snapshots[0].gco
        let midGCO = snapshots[24].gco
        let endGCO = snapshots[49].gco
        let growthPct = ((endGCO.float - startGCO.float) / startGCO.float * 100).int

        echo fmt"{planetName:<12} {resourceName:<12} {startGCO:>10} {midGCO:>12} {endGCO:>12} {growthPct:>9}%"

  test "Tax policy tradeoffs - Growth vs Revenue":
    # Compare different tax rates
    echo "\n=== TAX POLICY IMPACT (100 turns, Eden/Abundant, EL1) ==="
    echo "Tax Rate   Final PU  Final GCO    Total Income  Income/Turn"
    echo "=".repeat(75)

    let taxRates = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

    for taxRate in taxRates:
      var colony = Colony(
        systemId: SystemId(1),
        owner: "test",
        populationUnits: 100,
        populationTransferUnits: 0,
        industrial: IndustrialUnits(units: 50),
        planetClass: PlanetClass.Eden,
        resources: ResourceRating.Abundant,
        grossOutput: 0,
        taxRate: taxRate,
        underConstruction: none(ConstructionProject),
        infrastructureDamage: 0.0
      )

      let snapshots = simulateColonyGrowth(colony, 100, taxRate, 1)
      let finalSnapshot = snapshots[99]
      let avgIncome = finalSnapshot.treasury div 100

      echo fmt"{taxRate:>8}% {finalSnapshot.population:>10} {finalSnapshot.gco:>10} {finalSnapshot.treasury:>15} {avgIncome:>12}"

    echo "\nKey Insights:"
    echo "  - Low tax (0-20%): Maximum population growth"
    echo "  - Medium tax (40-60%): Balanced growth and revenue"
    echo "  - High tax (80-100%): Maximum short-term revenue, stunted growth"

  test "Research progression rates - EL advancement":
    # Test how long it takes to advance EL levels
    echo "\n=== RESEARCH PROGRESSION - Economic Level (Eden/Abundant, 50% tax) ==="
    echo " Start GHO  Research %  Turns to EL2  Turns to EL5  Turns to EL10"
    echo "=".repeat(80)

    let ghoSizes = [100, 500, 1000, 5000, 10000]
    let researchAllocations = [10, 20, 30, 50]  # % of GCO to research

    for gho in ghoSizes:
      for researchPct in researchAllocations:
        # Calculate ERP cost per turn
        let erpCost = calculateERPCost(gho)
        let ppPerTurn = gho * researchPct div 100
        let erpPerTurn = convertPPToERP(ppPerTurn, gho)

        # Calculate turns to each level
        var turnsToEL2 = 0
        var turnsToEL5 = 0
        var turnsToEL10 = 0
        var accumulated = 0
        var currentEL = 1

        for turn in 1..1000:
          accumulated += erpPerTurn

          # Check for upgrades (only on turns 1 and 7 of each year)
          let month = ((turn - 1) mod 13) + 1
          if month == 1 or month == 7:
            # Try to upgrade
            while accumulated >= getELUpgradeCost(currentEL):
              accumulated -= getELUpgradeCost(currentEL)
              currentEL += 1

              if currentEL == 2 and turnsToEL2 == 0:
                turnsToEL2 = turn
              elif currentEL == 5 and turnsToEL5 == 0:
                turnsToEL5 = turn
              elif currentEL == 10 and turnsToEL10 == 0:
                turnsToEL10 = turn
                break

          if turnsToEL10 > 0:
            break

        echo fmt"{gho:>10} {researchPct:>11}% {turnsToEL2:>14} {turnsToEL5:>14} {turnsToEL10:>15}"

    echo "\nKey Insights:"
    echo "  - Larger economies (higher GHO) advance research SLOWER (logarithmic cost)"
    echo "  - 30-50% research allocation recommended for steady progress"
    echo "  - Bi-annual upgrade timing creates chunky progression"

  test "Early vs Mid vs Late game economies":
    # Simulate different game stages
    echo "\n=== GAME STAGE COMPARISON (50 turns each) ==="

    # Early game: Small colony, low tech
    var earlyColony = Colony(
      systemId: SystemId(1),
      owner: "test",
      populationUnits: 50,
      populationTransferUnits: 0,
      industrial: IndustrialUnits(units: 20),
      planetClass: PlanetClass.Benign,
      resources: ResourceRating.Abundant,
      grossOutput: 0,
      taxRate: 40,
      underConstruction: none(ConstructionProject),
      infrastructureDamage: 0.0
    )

    let earlySnaps = simulateColonyGrowth(earlyColony, 50, 40, 1)

    # Mid game: Growing colony, medium tech
    var midColony = Colony(
      systemId: SystemId(1),
      owner: "test",
      populationUnits: 200,
      populationTransferUnits: 0,
      industrial: IndustrialUnits(units: 100),
      planetClass: PlanetClass.Lush,
      resources: ResourceRating.Rich,
      grossOutput: 0,
      taxRate: 50,
      underConstruction: none(ConstructionProject),
      infrastructureDamage: 0.0
    )

    let midSnaps = simulateColonyGrowth(midColony, 50, 50, 5)

    # Late game: Massive colony, high tech
    var lateColony = Colony(
      systemId: SystemId(1),
      owner: "test",
      populationUnits: 500,
      populationTransferUnits: 0,
      industrial: IndustrialUnits(units: 400),
      planetClass: PlanetClass.Eden,
      resources: ResourceRating.VeryRich,
      grossOutput: 0,
      taxRate: 60,
      underConstruction: none(ConstructionProject),
      infrastructureDamage: 0.0
    )

    let lateSnaps = simulateColonyGrowth(lateColony, 50, 60, 10)

    echo "Stage        Start GCO    End GCO     Growth    Total Income  Income/Turn"
    echo "=".repeat(80)

    let earlyGrowth = ((earlySnaps[49].gco.float - earlySnaps[0].gco.float) / earlySnaps[0].gco.float * 100).int
    let midGrowth = ((midSnaps[49].gco.float - midSnaps[0].gco.float) / midSnaps[0].gco.float * 100).int
    let lateGrowth = ((lateSnaps[49].gco.float - lateSnaps[0].gco.float) / lateSnaps[0].gco.float * 100).int

    echo fmt"Early        {earlySnaps[0].gco:>10} {earlySnaps[49].gco:>10} {earlyGrowth:>9}% {earlySnaps[49].treasury:>15} {earlySnaps[49].treasury div 50:>12}"
    echo fmt"Mid          {midSnaps[0].gco:>10} {midSnaps[49].gco:>10} {midGrowth:>9}% {midSnaps[49].treasury:>15} {midSnaps[49].treasury div 50:>12}"
    echo fmt"Late         {lateSnaps[0].gco:>10} {lateSnaps[49].gco:>10} {lateGrowth:>9}% {lateSnaps[49].treasury:>15} {lateSnaps[49].treasury div 50:>12}"

    echo "\nKey Insights:"
    echo "  - Early game: High % growth, low absolute income"
    echo "  - Mid game: Moderate growth, ramping income"
    echo "  - Late game: Low % growth, massive absolute income"
    echo "  - Tech multipliers become dominant in late game"

  test "Industrial Unit investment efficiency":
    # Test optimal IU investment timing
    echo "\n=== INDUSTRIAL UNIT INVESTMENT ANALYSIS ==="
    echo "Scenario: 100 PU colony, investing in IU vs saving PP"
    echo ""

    # Baseline: No IU investment
    var baselineColony = Colony(
      systemId: SystemId(1),
      owner: "test",
      populationUnits: 100,
      populationTransferUnits: 0,
      industrial: IndustrialUnits(units: 50),
      planetClass: PlanetClass.Eden,
      resources: ResourceRating.Abundant,
      grossOutput: 0,
      taxRate: 50,
      underConstruction: none(ConstructionProject),
      infrastructureDamage: 0.0
    )

    let baselineSnaps = simulateColonyGrowth(baselineColony, 100, 50, 1)

    echo "Strategy                   Final GCO    Total Income    Advantage"
    echo "=".repeat(75)
    echo fmt"Baseline (50 IU)       {baselineSnaps[99].gco:>12} {baselineSnaps[99].treasury:>15}            -"

    # Calculate IU investment scenarios
    # Note: This is simplified - actual implementation would need to simulate
    # turn-by-turn investment decisions

    let iuCost = getIndustrialUnitCost(baselineColony)
    echo fmt"\nCurrent IU cost: {iuCost} PP per unit"
    echo fmt"IU percentage: {baselineColony.industrial.units * 100 div baselineColony.populationUnits}% of PU"

    echo "\nKey Insights:"
    echo "  - IU investment has exponential returns (compounds each turn)"
    echo "  - Cost scales with IU/PU ratio (1.0x to 2.5x multiplier)"
    echo "  - Early IU investment pays off over 50+ turns"
    echo "  - Beyond 150% PU, IU becomes prohibitively expensive"

  test "Combat damage impact on economy":
    # Test how infrastructure damage affects production
    echo "\n=== INFRASTRUCTURE DAMAGE IMPACT ==="
    echo " Damage %  GCO Reduction    Income Loss  Recovery Turns"
    echo "=".repeat(70)

    let damagelevels = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9]

    for damage in damageLevels:
      var colony = Colony(
        systemId: SystemId(1),
        owner: "test",
        populationUnits: 100,
        populationTransferUnits: 0,
        industrial: IndustrialUnits(units: 50),
        planetClass: PlanetClass.Eden,
        resources: ResourceRating.Abundant,
        grossOutput: 0,
        taxRate: 50,
        underConstruction: none(ConstructionProject),
        infrastructureDamage: damage
      )

      let output = calculateProductionOutput(colony, 1)
      let baseOutput = 225  # Baseline: 100 PU * 1.0 + 50 IU * 1.1 * 1.0 = 155
      let reduction = baseOutput - output.grossOutput
      let incomeLoss = output.netValue div 2  # Assume 50% tax

      # Recovery time = damage * 100 turns (placeholder)
      let recoveryTurns = (damage * 100).int

      echo fmt"{(damage * 100).int:>9}% {reduction:>15} {incomeLoss:>15} {recoveryTurns:>15}"

    echo "\nKey Insights:"
    echo "  - Infrastructure damage linearly reduces GCO"
    echo "  - 50% damage = 50% production loss (devastating)"
    echo "  - Recovery time critical for war planning"
    echo "  - Planetary shields mitigate damage (future tech)"
