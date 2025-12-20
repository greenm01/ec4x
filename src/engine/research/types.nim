## Research-Specific Game State Types for EC4X
##
## This module defines data structures related to research and technology,
## adhering to the Data-Oriented Design (DoD) principle.

import std/[tables]
import ../../common/types/tech

# Re-export core TechField and TechLevel if needed by other modules
export tech.TechField, tech.TechLevel

type
  TechTree* = object
    ## Tracks technology levels for a house across various fields
    ## All fields are indexed by TechField enum
    levels*: Table[TechField, TechLevel]
