# EC4X API Documentation

Complete API reference documentation generated from source code using Nim's nimdoc tool.

## Structure

```
docs/api/
├── engine/           # Engine module documentation
│   ├── index.html   # Main navigation page
│   ├── core.html    # Core types (HouseId, SystemId, etc.)
│   ├── units.html   # Ship classes and weapon systems
│   ├── planets.html # Planet classification and resources
│   ├── combat.html  # Combat mechanics and TaskForce
│   ├── ship.html    # Individual ship representation
│   ├── squadron.html # Combat squadrons with CR/CC
│   ├── spacelift.html # Spacelift ships (ETAC, TroopTransport)
│   ├── fleet.html   # Fleet management
│   ├── gamestate.html # Game state and colonies
│   ├── starmap.html # Star systems and jump lanes
│   └── theindex.html # Full symbol index
└── generate_docs.sh # Documentation generation script
```

## Viewing Documentation

Open `docs/api/engine/index.html` in your web browser:

```bash
firefox docs/api/engine/index.html
# or
xdg-open docs/api/engine/index.html
```

## Regenerating Documentation

To regenerate all documentation:

```bash
cd docs/api
./generate_docs.sh
```

To regenerate a specific module:

```bash
./generate_docs.sh /path/to/module.nim
```

## Key Architecture Concepts

### Spacelift Command Ships

**CRITICAL:** Spacelift ships (ETAC, TroopTransport) are **individual units** NOT squadrons.

- Per operations.md:1036, spacelift ships are "individual units within the fleet"
- They travel with fleets but are separate from combat squadrons
- Screened during space combat (phase 1) and starbase assault (phase 2)
- Participate in ground combat (phase 3) where they can be destroyed

**Architecture:**
```
Fleet → Squadrons (combat) + SpaceLiftShips (transport/colonization)
```

See `spacelift.html` for complete API reference.

### Combat Squadrons

Tactical units with Command Rating (CR) and Command Cost (CC):

- Squadron = Flagship + Escorts (0-11 ships)
- CR determines tactical effectiveness
- Squadrons fight as cohesive units during combat

See `squadron.html` for complete API reference.

### Task Forces

Temporary combat formations created when fleets converge:

- All house fleets in a system disband into squadrons
- Squadrons fight individually (not as fleets)
- Spacelift ships are screened behind the task force
- Per operations.md:281-288

See `combat.html` for TaskForce API reference.

## Documentation Quality

All documentation is generated directly from source code comments using:

```nim
## Module-level documentation (double ##)
## Explains purpose and architecture

proc functionName*(...): ReturnType =
  ## Function documentation
  ## Explains parameters and return values
```

The documentation reflects the actual implementation and is automatically kept in sync with code changes.

## Adding Documentation for New Modules

1. Ensure module has proper doc comments (`##` for exports)
2. Add module to `generate_docs.sh` in appropriate section
3. Update `engine/index.html` with new module card
4. Regenerate documentation

## Benefits for Development

1. **Reduced Context Switching**: API reference available without reading source
2. **Type Discovery**: Find correct enum values (PlanetClass, ResourceRating, etc.)
3. **Architecture Clarity**: Understand module relationships and data flow
4. **Compilation Error Prevention**: Verify types before writing code
5. **Onboarding**: New developers can quickly understand the codebase

## Related Documentation

- `/docs/specs/` - Game specification and rules
- `/docs/design/` - Design documents and architecture
- `/balance_results/` - AI testing results and gap analysis
