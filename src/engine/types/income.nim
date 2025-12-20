import std/[tables, hashes]
import ./core

type
  TaxPolicy* = object
    currentRate*: int32
    history*: seq[int32]  # Last 6 turns

  TransactionCategory* {.pure.} = enum
    TaxIncome, Construction, Maintenance, Research,
    IndustrialInvestment, Terraforming, Prestige

  TreasuryTransaction* = object
    source*: string
    amount*: int32
    category*: TransactionCategory

  ColonyIncomeReport* = object
    colonyId*: ColonyId
    owner*: HouseId
    populationUnits*: int32
    grossOutput*: int32
    taxRate*: int32
    netValue*: int32
    populationGrowth*: float32
    prestigeBonus*: int32

  HouseIncomeReport* = object
    houseId*: HouseId
    colonies*: seq[ColonyIncomeReport]
    totalGross*: int32
    totalNet*: int32
    taxRate*: int32
    taxAverage6Turn*: int32
    taxPenalty*: int32
    totalPrestigeBonus*: int32
    treasuryBefore*: int32
    treasuryAfter*: int32
    transactions*: seq[TreasuryTransaction]
    prestigeEvents*: seq[PrestigeEvent]  # Assuming defined elsewhere

  IncomePhaseReport* = object
    turn*: int32
    houseReports*: Table[HouseId, HouseIncomeReport]
