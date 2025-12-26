type
  ThemeEntry* = object
    name*: string
    description*: string
    legalWarning*: string
    # All 12 houses inline
    house0Name*, house0Color*: string
    house1Name*, house1Color*: string
    house2Name*, house2Color*: string
    house3Name*, house3Color*: string
    house4Name*, house4Color*: string
    house5Name*, house5Color*: string
    house6Name*, house6Color*: string
    house7Name*, house7Color*: string
    house8Name*, house8Color*: string
    house9Name*, house9Color*: string
    house10Name*, house10Color*: string
    house11Name*, house11Color*: string

  HouseTheme* = object
    name*: string
    description*: string
    legalWarning*: string
    houses*: seq[tuple[name: string, color: string]] # Indexed by position 0-11

  ThemeConfig* = object
    themes*: Table[string, HouseTheme]
    activeTheme*: string

