## Treasurer Module - Budget Allocation Strategy
##
## Public API for the RBA budget allocation system.
##
## Responsibilities:
## - Calculate budget allocation percentages across build objectives
## - Consult with Domestikos requirements for dynamic allocation
## - Maintain strategic balance (minimum reserves for recon/expansion)
##
## This module answers the question: "How much PP should each objective get?"
## (The budget module answers: "What ships should we build with that PP?")
##
## Architecture:
## - treasurer/allocation.nim: Core allocation logic (baseline + personality + normalization)
## - treasurer/consultation.nim: Domestikos consultation logic (requirements-driven adjustment)
##
## Usage:
## ```nim
## import ai/rba/treasurer
##
## let allocation = treasurer.allocateBudget(
##   act = GameAct.Act2_RisingTensions,
##   personality = aiPersonality,
##   isUnderThreat = false,
##   admiralRequirements = some(requirements),
##   availableBudget = 300
## )
## # Returns: Table[BuildObjective, float] where sum(values) == 1.0
## ```

import std/[tables, options]
import ../common/types
import ./treasurer/allocation

# Re-export the main public API
export allocation.allocateBudget

# Re-export BudgetAllocation type (Table[BuildObjective, float])
# This is defined in ../common/types but we export for convenience
