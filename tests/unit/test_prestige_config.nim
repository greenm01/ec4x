## Test prestige configuration loading

import std/[unittest]
import ../../src/engine/config/prestige_config

suite "Prestige Configuration":
  test "Config values are reasonable":
    let config = globalPrestigeConfig
    check config.victory.prestige_threshold > 0
    check config.economic.establish_colony > 0
    check config.military.lose_planet < 0
    check config.penalties.maintenance_shortfall_base < 0

  test "Tax bonus tiers":
    let config = globalPrestigeConfig
    check config.tax_incentives.tier_1_max == 10
    check config.tax_incentives.tier_1_bonus == 3
    check config.tax_incentives.tier_2_max == 20
    check config.tax_incentives.tier_2_bonus == 2

  test "Military prestige values":
    let config = globalPrestigeConfig
    check config.military.fleet_victory == 3
    check config.military.force_retreat == 2
    check config.military.invade_planet == 10
    check config.military.destroy_starbase == 5
