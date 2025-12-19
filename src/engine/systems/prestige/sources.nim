## Prestige Source Values
##
## Maps prestige sources to configured point values

import ../../types/prestige as types
import ../../config/prestige_config

proc getPrestigeValue*(source: PrestigeSource): int =
  ## Get prestige value from configuration for given source
  ## Maps PrestigeSource enum to config values
  case source
  of PrestigeSource.CombatVictory:
    globalPrestigeConfig.military.fleet_victory
  of PrestigeSource.TaskForceDestroyed:
    # Task force destruction uses fleet_victory prestige
    globalPrestigeConfig.military.fleet_victory
  of PrestigeSource.FleetRetreated:
    globalPrestigeConfig.military.force_retreat
  of PrestigeSource.SquadronDestroyed:
    globalPrestigeConfig.military.destroy_squadron
  of PrestigeSource.ColonySeized:
    globalPrestigeConfig.military.invade_planet
  of PrestigeSource.ColonyEstablished:
    globalPrestigeConfig.economic.establish_colony
  of PrestigeSource.TechAdvancement:
    globalPrestigeConfig.economic.tech_advancement
  of PrestigeSource.BlockadePenalty:
    globalPrestigeConfig.penalties.blockade_penalty
  of PrestigeSource.Eliminated:
    globalPrestigeConfig.military.eliminate_house
  of PrestigeSource.LowTaxBonus:
    # Low tax bonus calculated dynamically, not from this function
    0
  of PrestigeSource.HighTaxPenalty:
    # High tax penalty calculated dynamically, not from this function
    0
  of PrestigeSource.MaintenanceShortfall:
    # Maintenance shortfall calculated dynamically, not from this function
    0
  of PrestigeSource.PactViolation:
    # Pact violation prestige from diplomacy config
    globalPrestigeConfig.diplomacy.pact_violation
