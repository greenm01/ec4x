## Help registry for TUI glyphs and abbreviations.
##
## Centralized definitions so help overlays stay DRY.

import std/tables

import ./styles/ec_palette

type
  HelpCode* {.pure.} = enum
    GlyphWarning
    GlyphOk
    FlagSelected
    AbbrevAS
    AbbrevDS
    AbbrevETA
    AbbrevROE
    AbbrevTT
    AbbrevETAC
    AbbrevSTS
    AbbrevCMD
    AbbrevTGT
    AbbrevZTC
    AbbrevFlt
    AbbrevSect
    AbbrevDest

  HelpItem* = object
    label*: string
    desc*: string

  HelpContext* {.pure.} = enum
    Overview
    Planets
    FleetList
    FleetConsole
    FleetDetail
    Research
    Espionage
    Economy
    IntelDb
    Settings
    Messages

const HelpItems* = {
  HelpCode.GlyphWarning: HelpItem(
    label: GlyphWarning,
    desc: "Needs attention (idle/crippled/support-only)"
  ),
  HelpCode.GlyphOk: HelpItem(
    label: GlyphOk,
    desc: "Staged command"
  ),
  HelpCode.FlagSelected: HelpItem(
    label: "X",
    desc: "Selected fleet"
  ),
  HelpCode.AbbrevAS: HelpItem(
    label: "AS",
    desc: "Attack Strength"
  ),
  HelpCode.AbbrevDS: HelpItem(
    label: "DS",
    desc: "Defense Strength"
  ),
  HelpCode.AbbrevETA: HelpItem(
    label: "ETA",
    desc: "Estimated turns to arrival"
  ),
  HelpCode.AbbrevROE: HelpItem(
    label: "ROE",
    desc: "Rules of Engagement"
  ),
  HelpCode.AbbrevTT: HelpItem(
    label: "TT",
    desc: "Troop Transports"
  ),
  HelpCode.AbbrevETAC: HelpItem(
    label: "ETAC",
    desc: "Engineering/Transport Assault Craft"
  ),
  HelpCode.AbbrevSTS: HelpItem(
    label: "STS",
    desc: "Status"
  ),
  HelpCode.AbbrevCMD: HelpItem(
    label: "CMD",
    desc: "Command"
  ),
  HelpCode.AbbrevTGT: HelpItem(
    label: "TGT",
    desc: "Target"
  ),
  HelpCode.AbbrevZTC: HelpItem(
    label: "ZTC",
    desc: "Zero Turn Command"
  ),
  HelpCode.AbbrevFlt: HelpItem(
    label: "Flt",
    desc: "Fleet"
  ),
  HelpCode.AbbrevSect: HelpItem(
    label: "Sect",
    desc: "Sector"
  ),
  HelpCode.AbbrevDest: HelpItem(
    label: "Dest",
    desc: "Destination"
  )
}.toTable

proc helpCodes*(ctx: HelpContext): seq[HelpCode] =
  case ctx
  of HelpContext.FleetList:
    @[
      HelpCode.GlyphWarning,
      HelpCode.GlyphOk,
      HelpCode.FlagSelected,
      HelpCode.AbbrevFlt,
      HelpCode.AbbrevSect,
      HelpCode.AbbrevAS,
      HelpCode.AbbrevDS,
      HelpCode.AbbrevCMD,
      HelpCode.AbbrevDest,
      HelpCode.AbbrevETA,
      HelpCode.AbbrevROE,
      HelpCode.AbbrevSTS
    ]
  of HelpContext.FleetConsole:
    @[
      HelpCode.GlyphWarning,
      HelpCode.GlyphOk,
      HelpCode.FlagSelected,
      HelpCode.AbbrevFlt,
      HelpCode.AbbrevAS,
      HelpCode.AbbrevDS,
      HelpCode.AbbrevTT,
      HelpCode.AbbrevETAC,
      HelpCode.AbbrevCMD,
      HelpCode.AbbrevTGT,
      HelpCode.AbbrevETA,
      HelpCode.AbbrevROE,
      HelpCode.AbbrevSTS
    ]
  else:
    @[]

proc helpLines*(ctx: HelpContext): seq[string] =
  for code in helpCodes(ctx):
    if HelpItems.hasKey(code):
      let item = HelpItems[code]
      result.add(item.label & " = " & item.desc)
  if ctx == HelpContext.Research:
    result.add("Up/Down = navigate")
    result.add("+/- = adjust PP")
    result.add("Shift+/- = fine adjust")
    result.add("0 = clear allocation")
    result.add("0-9 = set PP")
    result.add("Enter = confirm")
  if ctx == HelpContext.Messages:
    result.add("Tab = cycle focus")
    result.add("M = jump to Messages")
    result.add("R = jump to Reports")
    result.add("C = compose message")
    result.add("Enter = select / send")
    result.add("Esc = back / collapse")
    result.add("Up/Down = navigate")
