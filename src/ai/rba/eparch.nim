## Eparch Module - Imperial Economic Prefect
##
## Byzantine Eparch (ἔπαρχος) - Prefect controlling markets and infrastructure
##
## Public API for economic development and infrastructure management.
##
## Responsibilities:
## - Terraforming strategy (planetary development)
## - Facility construction (shipyards, spaceports)
## - Economic policy (future: taxation, trade)
##
## Usage:
## ```nim
## import ai/rba/eparch
##
## let terraformOrders = eparch.generateTerraformOrders(
##   controller,
##   filtered,
##   myColonies
## )
## ```

import ../../common/types/[core, planets]
import ../../engine/[gamestate, orders]
import ./eparch/terraforming

# Re-export the main public API
export terraforming.generateTerraformOrders

# Re-export types for convenience
export core.SystemId
export planets.PlanetClass
export orders.TerraformOrder
