import std/tables

type
  HouseThemeData* = object
    ## Theme data for a single house
    name*: string
    color*: string

  ThemeEntry* = object
    name*: string
    description*: string
    # Uses Table for numbered houses (0-11)
    ## Per types-guide.md: Use Table[int32, T] for numbered sequences
    houses*: Table[int32, HouseThemeData]

  HouseTheme* = object
    name*: string
    description*: string
    houses*: seq[tuple[name: string, color: string]] # Indexed by position 0-11

  ThemesConfig* = object
    themes*: Table[string, HouseTheme]
    activeTheme*: string

