## Unit tests for projected research gating helpers.

import std/unittest

import ../../src/engine/globals
import ../../src/engine/config/engine as config_engine
import ../../src/engine/systems/tech/costs
import ../../src/engine/types/tech
import ../../src/player/sam/tui_model
import ../../src/player/tui/data/research_projection
import ../../src/player/tui/data/tech_info

gameConfig = config_engine.loadGameConfig()

proc baseLevels(
    sl: int32 = 1,
    ml: int32 = 1,
    el: int32 = 1,
    wep: int32 = 1,
    ter: int32 = 1
): TechLevel =
  TechLevel(
    el: el,
    sl: sl,
    ml: ml,
    cst: 1,
    wep: wep,
    ter: ter,
    eli: 1,
    clk: 1,
    sld: 1,
    cic: 1,
    stl: 1,
    fc: 1,
    sc: 1,
    fd: 1,
    aco: 1
  )

proc emptyPoints(): ResearchPoints =
  ResearchPoints(erp: 0, srp: 0, mrp: 0)

proc emptyDeposits(): ResearchDeposits =
  ResearchDeposits(erp: 0, srp: 0, mrp: 0)

proc emptyPurchases(): TechPurchaseSet =
  TechPurchaseSet(economic: false, science: false, military: false)

suite "Research Projection: Root Levels":
  test "science purchase projects one SL level when affordable":
    let levels = baseLevels(sl = 1)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    points.srp = slUpgradeCost(1)
    purchases.science = true

    check projectedScienceLevel(
      levels, points, deposits, purchases, 100
    ) == 2

  test "military purchase projects one ML level when affordable":
    let levels = baseLevels(ml = 1)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    points.mrp = mlUpgradeCost(1)
    purchases.military = true

    check projectedMilitaryLevel(
      levels, points, deposits, purchases, 100
    ) == 2

  test "economic level remains ungated":
    let levels = baseLevels(sl = 1, el = 1)
    let points = emptyPoints()
    let deposits = emptyDeposits()
    let purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("EL"))

    check not isBlockedProjected(
      levels, points, deposits, purchases, item, 100
    )

suite "Research Projection: Branch Gating":
  test "science tech stays blocked without projected SL":
    let levels = baseLevels(sl = 1)
    let points = emptyPoints()
    let deposits = emptyDeposits()
    let purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("STL"))

    check isBlockedProjected(
      levels, points, deposits, purchases, item, 100
    )

  test "science tech unlocks when staged SL purchase meets gate":
    let levels = baseLevels(sl = 1)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("STL"))
    points.srp = slUpgradeCost(levels.sl)
    purchases.science = true

    check not isBlockedProjected(
      levels, points, deposits, purchases, item, 100
    )

  test "military tech stays blocked without projected ML":
    let levels = baseLevels(ml = 1, wep = 1)
    let points = emptyPoints()
    let deposits = emptyDeposits()
    let purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("WEP"))

    check isBlockedProjected(
      levels, points, deposits, purchases, item, 100
    )

  test "military tech unlocks when staged ML purchase meets gate":
    let levels = baseLevels(ml = 1, wep = 1)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("WEP"))
    points.mrp = mlUpgradeCost(levels.ml)
    purchases.military = true

    check not isBlockedProjected(
      levels, points, deposits, purchases, item, 100
    )

suite "Research Projection: Tech Purchases":
  test "military tech purchase projects one level when affordable":
    let levels = baseLevels(ml = 2, wep = 1)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("WEP"))
    points.mrp = techProgressCost(item, 1).int32
    purchases.technology.incl item.field

    check projectedTechLevel(
      levels, points, deposits, purchases, item, 100
    ) == 2

suite "Research Projection: Detail Targets":
  test "detail target level points at next ACO tier when current gate is unmet":
    let item = researchItemAt(researchIndexForCode("ACO"))

    check detailTargetLevel(1, progressionMaxLevel(item)) == 2
    check techGateRequiredForLevel(item, detailTargetLevel(
      1, progressionMaxLevel(item)
    )) == 4

  test "detail target level points at next military branch tier":
    let item = researchItemAt(researchIndexForCode("WEP"))

    check detailTargetLevel(1, progressionMaxLevel(item)) == 2
    check techGateRequiredForLevel(item, detailTargetLevel(
      1, progressionMaxLevel(item)
    )) == 2

  test "detail target level clamps to max level":
    let item = researchItemAt(researchIndexForCode("ACO"))

    check detailTargetLevel(3, progressionMaxLevel(item)) == 3

  test "science tech purchase projects one level when affordable":
    let levels = baseLevels(sl = 2)
    var points = emptyPoints()
    let deposits = emptyDeposits()
    var purchases = emptyPurchases()
    let item = researchItemAt(researchIndexForCode("STL"))
    points.srp = techProgressCost(item, 1).int32
    purchases.technology.incl item.field

    check projectedTechLevel(
      levels, points, deposits, purchases, item, 100
    ) == 2
