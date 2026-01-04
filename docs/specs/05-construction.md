# 5.0 Construction

You accomplish construction and repair of House assets planet-side or in orbit, with restrictions.

## 5.1 Ship Construction

All ship construction completes in one turn regardless of hull class or CST tech level. This reflects the game's time narrative where turns represent variable time periods (1-15 years depending on map size).

**Payment Model:**

- You must pay full PC cost **upfront** from your house treasury when construction begins
- You cannot start construction if your house lacks sufficient PP in treasury
- If you cancel construction, you receive a 50% PC refund to treasury

**Construction Vulnerability:**

Ships under construction in docks can be destroyed during the Conflict Phase if:

- The shipyard/spaceport is destroyed by orbital bombardment
- The facility is crippled by combat damage

Destroyed ships-in-construction provide no salvage value. Your house loses the full PC investment.

**Completion and Commissioning:**

Ship building completes at the start of the Command Phase and are immediately commissioned:

- Ship is created with current house tech levels
- Automatically assigned to existing fleet at facility location (if stationary fleet present)
- Otherwise, new fleet is created with the ship
- Scouts form scout-only fleets
- Fighters remain colony-assigned (not assigned to fleets)

**Construction Locations:**

Ships can be constructed at two facility types with different costs and requirements. See [Sections 5.2-5.5](#52-planet-side-construction) for detailed construction rules by facility type.

## 5.2 Planet-side Construction

Ground units and Fighters are produced via colony industry, distributed across the surface or in underground factories.

**Spaceports:**

Ships (excluding Fighters) constructed planet-side incur a **100% PC increase** due to the added cost of orbital launch, and require a spaceport to commission.

**Example Cost Calculation:**

Base ship cost: 50 PP  
Planet-side construction: 50 PP × 2 = 100 PP total

For spaceport specifications and capacity, see [Section 2.3.2.1](02-assets.md#23221-spaceports).

## 5.3 Planet-side Repair

Ground units and Fighters are repaired and refitted planet-side using colony industrial capacity.

**Spaceports cannot repair ships.** Spaceports are construction facilities only - they launch ships into orbit but cannot repair orbital damage.

## 5.4 Orbital Construction

Shipyard construction of a ship in orbit is the standard method of commissioning a vessel, and incurs no penalty.

**Standard Costs:**

Ships built at shipyards use their base PP cost with no modifiers. This is the economically efficient construction method.

For shipyard specifications and capacity, see [Section 2.3.2.2](02-assets.md#23222-shipyards).

## 5.5 Orbital Repair

**Ship repairs require a Drydock.** Spaceports and Shipyards cannot repair ships - only drydocks have the specialized orbital infrastructure for ship repairs.

**Ship Repairs:**

The number of turns required to repair a crippled ship is one turn. The ship must be located at a colony equipped with a drydock, and the ship remains decommissioned through the repair period.

The cost of repair equals one quarter (25%) of the ship's construction PP. All ship repairs complete in 1 turn regardless of ship class.

Example: You wish to repair a crippled WEP3 Light Cruiser. The cost is:

```
72.6 PP (build cost) * 0.25 = 18.15 PP (repair cost)
```

**Starbase Repairs:**

Starbase repairs require **spaceports** (not drydocks) and cost 25% of the starbase's construction PP (75 PP). Repair time is 1 turn.

**Important:** Starbase repairs do NOT consume dock capacity. Spaceports can simultaneously repair starbases while constructing ships, as facilities and ships use separate repair queues.

**Colonies without drydocks cannot repair crippled ships.** Ships must either:

- Transfer to a colony with drydock capacity, or
- Be salvaged for 50% PC recovery
