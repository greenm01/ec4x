## Accessors for commonly-used values

proc soulsPerPtu*(): int32 =
  gConfig.economy.ptuDefinition.soulsPerPtu

proc ptuSizeMillions*(): float32 =
  gConfig.economy.ptuDefinition.ptuSizeMillions

proc minViablePopulation*(): int32 =
  gConfig.economy.population.minViablePopulation

