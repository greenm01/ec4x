## Test prestige configuration loading

import std/[unittest]
import ../../src/engine/config/prestige_config

suite "Prestige Configuration":
  test "Default config loads":
    let config = defaultPrestigeConfig()
    check config.prestigeVictoryThreshold == 5000
    check config.establishColony == 5
    check config.techAdvancement == 2
    check config.invadePlanet == 10
    check config.losePlanet == -10

  test "Config values are reasonable":
    let config = globalPrestigeConfig
    check config.prestigeVictoryThreshold > 0
    check config.establishColony > 0
    check config.losePlanet < 0
    check config.maintenanceShortfallBase < 0

  test "Tax bonus tiers":
    let config = globalPrestigeConfig
    check config.taxBonusTier1Max == 10
    check config.taxBonusTier1 == 3
    check config.taxBonusTier2Max == 20
    check config.taxBonusTier2 == 2

  test "Military prestige values":
    let config = globalPrestigeConfig
    check config.destroyTaskForce == 3
    check config.forceRetreat == 2
    check config.invadePlanet == 10
    check config.destroyStarbase == 5
