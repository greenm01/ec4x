## EC4X Planet and Colony Types
## Planet classifications and resource ratings

# =============================================================================
# Planet and Colony Types
# =============================================================================

type
  PlanetClass* {.pure.} = enum
    ## Planet habitability classifications
    ## Determines population and infrastructure limits
    Extreme      # Level I   - 1-20 PU
    Desolate     # Level II  - 21-60 PU
    Hostile      # Level III - 61-180 PU
    Harsh        # Level IV  - 181-500 PU
    Benign       # Level V   - 501-1000 PU
    Lush         # Level VI  - 1k-2k PU
    Eden         # Level VII - 2k+ PU

  ResourceRating* {.pure.} = enum
    ## System resource availability
    VeryPoor
    Poor
    Abundant
    Rich
    VeryRich
