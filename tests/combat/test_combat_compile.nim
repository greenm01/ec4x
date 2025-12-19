## Basic compilation test for combat system
## Just imports and creates basic objects

import ../src/engine/combat/[types, cer, targeting,
                              damage, resolution, retreat,
                              engine]
import ../src/engine/squadron
import ../src/common/types/[core, units, combat, diplomacy]
import combat_generator

echo "Testing imports..."

# Test basic type creation
let flagship = newShip(ShipClass.Battleship, techLevel = 1, name = "Test Ship")
echo "Created ship: ", flagship

let sq = newSquadron(flagship, id = "sq-1", owner = "house-test", location = 0)
echo "Created squadron: ", sq

# Test RNG
var rng = initRNG(12345)
let roll = rng.roll1d10()
echo "Dice roll: ", roll

# Test CER
let cerRoll = rollCER(rng, CombatPhase.MainEngagement, roundNumber = 1,
                       hasScouts = false, moraleModifier = 0)
echo "CER roll: ", cerRoll

echo "All imports successful!"
