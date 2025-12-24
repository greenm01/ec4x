## Population Configuration Loader
##
## Loads population transfer settings from config/population.toml
## Defines PTU (Population Transfer Unit) size and Space Guild transfer rules

import std/[os]
import toml_serialization
import ../../common/logger

type
  PtuDefinitionConfig* = object
    souls_per_ptu*: int
    ptu_size_millions*: float
    min_population_remaining*: int

  TransferCostsConfig* = object
    eden_cost*: int
    lush_cost*: int
    benign_cost*: int
    harsh_cost*: int
    hostile_cost*: int
    desolate_cost*: int
    extreme_cost*: int

  TransferTimeConfig* = object
    turns_per_jump*: int
    minimum_turns*: int

  TransferModifiersConfig* = object
    cost_increase_per_jump*: float

  TransferLimitsConfig* = object
    min_ptu_transfer*: int
    min_source_pu_remaining*: int
    max_concurrent_transfers*: int

  TransferRisksConfig* = object
    source_conquered_behavior*: string
    dest_conquered_behavior*: string
    dest_blockaded_behavior*: string
    dest_collapsed_behavior*: string

  RecruitmentConfig* = object
    min_viable_population*: int

  AiStrategyConfig* = object
    min_treasury_for_transfer*: int
    min_source_population*: int
    max_dest_population*: int
    recent_colony_age_turns*: int
    ptu_per_transfer*: int
    min_economic_focus*: float
    min_expansion_drive*: float

  PopulationConfig* = object ## Complete population configuration loaded from TOML
    ptu_definition*: PtuDefinitionConfig
    transfer_costs*: TransferCostsConfig
    transfer_time*: TransferTimeConfig
    transfer_modifiers*: TransferModifiersConfig
    transfer_limits*: TransferLimitsConfig
    transfer_risks*: TransferRisksConfig
    recruitment*: RecruitmentConfig
    ai_strategy*: AiStrategyConfig

proc loadPopulationConfig*(
    configPath: string = "config/population.toml"
): PopulationConfig =
  ## Load population configuration from TOML file
  ## Uses toml_serialization for type-safe parsing

  if not fileExists(configPath):
    raise newException(IOError, "Population config not found: " & configPath)

  let configContent = readFile(configPath)
  result = Toml.decode(configContent, PopulationConfig)

  logInfo("Config", "Loaded population configuration", "path=", configPath)

## Global configuration instance

var config: PopulationConfig = loadPopulationConfig()

## Accessors for commonly-used values

proc soulsPerPtu*(): int =
  config.ptu_definition.souls_per_ptu

proc ptuSizeMillions*(): float =
  config.ptu_definition.ptu_size_millions

proc minViablePopulation*(): int =
  config.recruitment.min_viable_population

## Helper to reload configuration (for testing)

proc reloadPopulationConfig*() =
  ## Reload configuration from file
  config = loadPopulationConfig()

## Initialize legacy global config (population/types.nim)
## TODO: Refactor to use new config structure throughout codebase

import ../types/population as pop_types

pop_types.globalPopulationConfig = pop_types.PopulationTransferConfig(
  soulsPerPtu: config.ptu_definition.souls_per_ptu.int32,
  ptuSizeMillions: config.ptu_definition.ptu_size_millions.float32,
  edenCost: config.transfer_costs.eden_cost.int32,
  lushCost: config.transfer_costs.lush_cost.int32,
  benignCost: config.transfer_costs.benign_cost.int32,
  harshCost: config.transfer_costs.harsh_cost.int32,
  hostileCost: config.transfer_costs.hostile_cost.int32,
  desolateCost: config.transfer_costs.desolate_cost.int32,
  extremeCost: config.transfer_costs.extreme_cost.int32,
  turnsPerJump: config.transfer_time.turns_per_jump.int32,
  minimumTurns: config.transfer_time.minimum_turns.int32,
  costIncreasePerJump: config.transfer_modifiers.cost_increase_per_jump.float32,
  minPtuTransfer: config.transfer_limits.min_ptu_transfer.int32,
  minSourcePuRemaining: config.transfer_limits.min_source_pu_remaining.int32,
  maxConcurrentTransfers: config.transfer_limits.max_concurrent_transfers.int32,
  sourceConqueredBehavior: config.transfer_risks.source_conquered_behavior,
  destConqueredBehavior: config.transfer_risks.dest_conquered_behavior,
  destBlockadedBehavior: config.transfer_risks.dest_blockaded_behavior,
  minTreasuryForTransfer: config.ai_strategy.min_treasury_for_transfer.int32,
  minSourcePopulation: config.ai_strategy.min_source_population.int32,
  maxDestPopulation: config.ai_strategy.max_dest_population.int32,
  recentColonyAgeTurns: config.ai_strategy.recent_colony_age_turns.int32,
  ptuPerTransfer: config.ai_strategy.ptu_per_transfer.int32,
  minEconomicFocus: config.ai_strategy.min_economic_focus.float32,
  minExpansionDrive: config.ai_strategy.min_expansion_drive.float32,
)
