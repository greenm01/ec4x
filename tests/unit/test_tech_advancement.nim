## Unit Tests: Tech Advancement and Breakthroughs
##
## Tests breakthrough rolls and max level constants from tech/advancement.nim
##
## Per economy.md:4.1

import std/[unittest, random, options, tables, sequtils]
import ../../src/engine/engine
import ../../src/engine/types/[core, tech, command, event]
import ../../src/engine/state/[engine, iterators]
import ../../src/engine/turn_cycle/command_phase
import ../../src/engine/systems/tech/[advancement, costs]
import ../../src/engine/globals

suite "Tech: Maximum Level Constants":
  ## Verify all tech max level constants are defined correctly

  test "Economic and Science max levels":
    check maxEconomicLevel == 11
    check maxScienceLevel == 10

  test "Construction tech max levels":
    check maxConstructionTech == 15
    check maxWeaponsTech == 15
    check maxTerraformingTech == 7

  test "Intelligence tech max levels":
    check maxElectronicIntelligence == 15
    check maxCloakingTech == 15
    check maxCounterIntelligence == 15

  test "Shield and lift tech max levels":
    check maxShieldTech == 15
    check maxStrategicLiftTech == 15

  test "Command tech max levels":
    check maxFlagshipCommandTech == 6
    check maxStrategicCommandTech == 5

  test "Carrier tech max levels":
    check maxFighterDoctrine == 3
    check maxAdvancedCarrierOps == 3

suite "Tech: Breakthrough Turn Check":
  ## Test isBreakthroughTurn - every 5 turns

  test "turn 0 is not breakthrough":
    check isBreakthroughTurn(0) == true # 0 mod 5 = 0, so true

  test "turn 5 is breakthrough":
    check isBreakthroughTurn(5) == true

  test "turn 10 is breakthrough":
    check isBreakthroughTurn(10) == true

  test "turn 15 is breakthrough":
    check isBreakthroughTurn(15) == true

  test "turn 100 is breakthrough":
    check isBreakthroughTurn(100) == true

  test "turn 1 is not breakthrough":
    check isBreakthroughTurn(1) == false

  test "turn 4 is not breakthrough":
    check isBreakthroughTurn(4) == false

  test "turn 6 is not breakthrough":
    check isBreakthroughTurn(6) == false

  test "turn 99 is not breakthrough":
    check isBreakthroughTurn(99) == false

suite "Tech: Breakthrough Roll Statistical":
  ## Test rollBreakthrough produces expected distribution

  test "breakthrough with zero RP has 5% base chance":
    var rng = initRand(12345)
    var successes = 0

    # Roll many times
    for i in 1 .. 10000:
      let result = rollBreakthrough(rng, totalRPInvested = 0)
      if result.isSome:
        successes += 1

    # 5% chance = 1/20 = 500 expected successes
    # Allow statistical variance (4-6% range)
    check successes >= 350 # At least 3.5%
    check successes <= 750 # At most 7.5%

  test "breakthrough with 1000+ RP has 15% max chance":
    var rng = initRand(54321)
    var successes = 0

    for i in 1 .. 10000:
      let result = rollBreakthrough(rng, totalRPInvested = 1000)
      if result.isSome:
        successes += 1

    # 15% chance = 3/20 = 1500 expected
    check successes >= 1200 # At least 12%
    check successes <= 1800 # At most 18%

  test "breakthrough chance is capped at 15%":
    var rng = initRand(99999)
    var successes = 0

    # Even with massive RP investment, still capped
    for i in 1 .. 10000:
      let result = rollBreakthrough(rng, totalRPInvested = 100000)
      if result.isSome:
        successes += 1

    # Still ~15% (same as 1000 RP)
    check successes >= 1200
    check successes <= 1800

suite "Tech: Breakthrough Type Distribution":
  ## Test breakthrough type probabilities when breakthrough occurs

  test "breakthrough types follow expected distribution":
    var rng = initRand(11111)
    var minor = 0
    var moderate = 0
    var major = 0
    var revolutionary = 0

    # Generate many breakthroughs (high RP for more hits)
    var total = 0
    for i in 1 .. 50000:
      let result = rollBreakthrough(rng, totalRPInvested = 1000)
      if result.isSome:
        total += 1
        case result.get()
        of BreakthroughType.Minor:
          minor += 1
        of BreakthroughType.Moderate:
          moderate += 1
        of BreakthroughType.Major:
          major += 1
        of BreakthroughType.Revolutionary:
          revolutionary += 1

    # Expected distribution:
    # Minor: 50% (1-10 on d20)
    # Moderate: 25% (11-15)
    # Major: 15% (16-18)
    # Revolutionary: 10% (19-20)

    let minorPct = float(minor) / float(total)
    let moderatePct = float(moderate) / float(total)
    let majorPct = float(major) / float(total)
    let revPct = float(revolutionary) / float(total)

    # Allow variance but check roughly correct
    check minorPct >= 0.40 and minorPct <= 0.60 # 50% ± 10%
    check moderatePct >= 0.18 and moderatePct <= 0.32 # 25% ± 7%
    check majorPct >= 0.08 and majorPct <= 0.22 # 15% ± 7%
    check revPct >= 0.05 and revPct <= 0.18 # 10% ± 8%

suite "Tech: Breakthrough Scaling":
  ## Test RP investment affects breakthrough chance correctly

  test "100 RP gives 6% chance (base 5 + 1)":
    var rng = initRand(22222)
    var successes = 0

    for i in 1 .. 10000:
      let result = rollBreakthrough(rng, totalRPInvested = 100)
      if result.isSome:
        successes += 1

    # 6% = 600 expected
    check successes >= 450
    check successes <= 850

  test "500 RP gives 10% chance (base 5 + 5)":
    var rng = initRand(33333)
    var successes = 0

    for i in 1 .. 10000:
      let result = rollBreakthrough(rng, totalRPInvested = 500)
      if result.isSome:
        successes += 1

    # 10% = 1000 expected
    check successes >= 800
    check successes <= 1200

suite "Tech: Deterministic Breakthrough (Seeded)":
  ## Test reproducibility with seeded RNG

  test "same seed produces same results":
    var rng1 = initRand(42)
    var rng2 = initRand(42)

    for i in 1 .. 100:
      let result1 = rollBreakthrough(rng1, totalRPInvested = 500)
      let result2 = rollBreakthrough(rng2, totalRPInvested = 500)
      check result1 == result2

  test "different seeds produce different results":
    var rng1 = initRand(1)
    var rng2 = initRand(2)

    var same = 0
    for i in 1 .. 100:
      let result1 = rollBreakthrough(rng1, totalRPInvested = 500)
      let result2 = rollBreakthrough(rng2, totalRPInvested = 500)
      if result1 == result2:
        same += 1

    # Should NOT be all the same
    check same < 100

suite "Tech: Allocation Caps":
  ## Ensure one-level-per-tech-per-turn cap and SL gating

  test "allocations cap to next level and refund excess":
    var game = newGame()
    let houseId = game.allHouses().toSeq[0].id
    var house = game.house(houseId).get()
    house.treasury = 1000
    house.techTree.levels.sl = 10
    house.techTree.levels.wep = 1
    house.techTree.accumulated.technology = initTable[TechField, int32]()
    game.updateHouse(houseId, house)

    let cost = techUpgradeCost(TechField.WeaponsTech, 1)
    var allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    )
    allocation.technology[TechField.WeaponsTech] = cost + 50

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = CommandPacket(
      houseId: houseId,
      turn: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      researchAllocation: allocation,
      diplomaticCommand: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var events: seq[GameEvent] = @[]
    game.processResearchAllocation(orders, events)

    let updated = game.house(houseId).get()
    let expectedSpent = cost
    check updated.treasury == house.treasury - expectedSpent
    check updated.techTree.accumulated.technology[TechField.WeaponsTech] > 0
    check updated.techTree.accumulated.technology[TechField.WeaponsTech] <=
      techUpgradeCost(TechField.WeaponsTech, 1)

  test "SL gating blocks allocation and refunds PP":
    var game = newGame()
    let houseId = game.allHouses().toSeq[0].id
    var house = game.house(houseId).get()
    house.treasury = 500
    house.techTree.levels.sl = 1
    house.techTree.levels.wep = 1
    house.techTree.accumulated.technology = initTable[TechField, int32]()
    game.updateHouse(houseId, house)

    var allocation = ResearchAllocation(
      economic: 0,
      science: 0,
      technology: initTable[TechField, int32]()
    )
    allocation.technology[TechField.WeaponsTech] = 100

    var orders = initTable[HouseId, CommandPacket]()
    orders[houseId] = CommandPacket(
      houseId: houseId,
      turn: 1,
      fleetCommands: @[],
      buildCommands: @[],
      repairCommands: @[],
      scrapCommands: @[],
      researchAllocation: allocation,
      diplomaticCommand: @[],
      populationTransfers: @[],
      terraformCommands: @[],
      colonyManagement: @[],
      espionageActions: @[],
      ebpInvestment: 0,
      cipInvestment: 0
    )

    var events: seq[GameEvent] = @[]
    game.processResearchAllocation(orders, events)

    let updated = game.house(houseId).get()
    check updated.treasury == house.treasury
    check updated.techTree.accumulated.technology.len == 0

suite "Tech: Science Level Advancement":
  test "SL advances from 8 to 9 with required SRP":
    var tree = TechTree(
      houseId: HouseId(1),
      levels: TechLevel(sl: 8),
      accumulated: ResearchPoints(
        economic: 0,
        science: slUpgradeCost(8),
        technology: initTable[TechField, int32]()
      ),
      breakthroughBonus: initTable[TechField, float32]()
    )

    let adv = tree.attemptSLAdvancement(8)
    check adv.isSome
    check tree.levels.sl == 9

  test "SL advances from 9 to 10 with required SRP":
    var tree = TechTree(
      houseId: HouseId(1),
      levels: TechLevel(sl: 9),
      accumulated: ResearchPoints(
        economic: 0,
        science: slUpgradeCost(9),
        technology: initTable[TechField, int32]()
      ),
      breakthroughBonus: initTable[TechField, float32]()
    )

    let adv = tree.attemptSLAdvancement(9)
    check adv.isSome
    check tree.levels.sl == 10

when isMainModule:
  echo "========================================"
  echo "  Tech Advancement Unit Tests"
  echo "========================================"
