## Prestige Source Values
##
## Maps prestige sources to configured point values

import ../types/prestige
import ../globals

proc prestigeValue*(source: PrestigeSource): int32 =
  ## Get prestige value from configuration for given source
  ## Maps PrestigeSource enum to config values
  case source
  of PrestigeSource.CombatVictory:
    gameConfig.prestige.military.fleetVictory
  of PrestigeSource.TaskForceDestroyed:
    # Task force destruction uses fleet_victory prestige
    gameConfig.prestige.military.fleetVictory
  of PrestigeSource.FleetRetreated:
    gameConfig.prestige.military.forceRetreat
  of PrestigeSource.SquadronDestroyed:
    gameConfig.prestige.military.destroySquadron
  of PrestigeSource.ColonySeized:
    gameConfig.prestige.military.invadePlanet
  of PrestigeSource.ColonyEstablished:
    gameConfig.prestige.economic.establishColony
  of PrestigeSource.TechAdvancement:
    gameConfig.prestige.economic.techAdvancement
  of PrestigeSource.BlockadePenalty:
    gameConfig.prestige.penalties.blockadePenalty
  of PrestigeSource.Eliminated:
    gameConfig.prestige.military.eliminateHouse
  of PrestigeSource.LowTaxBonus:
    # Low tax bonus calculated dynamically, not from this function
    0
  of PrestigeSource.HighTaxPenalty:
    # High tax penalty calculated dynamically, not from this function
    0
  of PrestigeSource.MaintenanceShortfall:
    # Maintenance shortfall calculated dynamically, not from this function
    0
