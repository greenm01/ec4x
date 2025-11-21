# EC4X Scripts

Utility scripts for project automation and documentation maintenance.

---

## Game Configuration Scripts

### sync_specs.py

**Purpose:** Generate specification tables from TOML configuration files

**Usage:**
```bash
python3 scripts/sync_specs.py
```

**What it does:**
- Reads `config/prestige.toml` and `config/espionage.toml`
- Generates markdown tables with enum names and values
- Updates `docs/specs/reference.md` between HTML comment markers
- Ensures single source of truth for game balance values

**Tables Generated:**
- Prestige sources (18 entries) - ✅ Active
- Penalty mechanics (4 penalty types) - ✅ Active
- Morale levels (7 levels) - ⏳ Pending markers in reference.md
- Espionage actions (7 actions) - ⏳ Pending markers in reference.md

**Example Output:**
```markdown
| Prestige Source | Enum Name | Value |
|-----------------|-----------|-------|
| Tech Advancement | `TechAdvancement` | +2 |
| Colony Establishment | `ColonyEstablishment` | +5 |
```

**Run:** After modifying any TOML config file in `config/`

---

## Development Quality Scripts

### setup_hooks.sh

**Purpose:** Install git pre-commit hooks to enforce code quality

**Usage:**
```bash
bash scripts/setup_hooks.sh
```

**What it does:**
- Installs `.git/hooks/pre-commit` hook
- Automatically runs before each commit
- Prevents non-compliant code from being committed

**Checks Performed:**
1. All enums are `{.pure.}` (NEP-1 requirement)
2. All constants use camelCase (not UPPER_SNAKE_CASE)
3. Project builds successfully (`nimble build`)
4. Critical integration tests pass (3 key tests)

**Bypass:** Use `git commit --no-verify` (not recommended)

**Status:** ✅ Installed and active

---

## Documentation Quality Scripts

### check_formatting.py

**Purpose:** Analyze formatting consistency across specification files

**Usage:**
```bash
python3 scripts/check_formatting.py
```

**What it checks:**
- Heading patterns and levels
- Table formatting consistency
- Code block styles
- List formatting
- Bold/italic patterns
- Spacing consistency

**Use case:** Ensuring all spec files follow consistent markdown formatting

---

### check_links.py

**Purpose:** Validate internal links in markdown documentation

**Usage:**
```bash
python3 scripts/check_links.py
```

**What it checks:**
- Markdown link syntax `[text](url)`
- Internal file references
- Anchor links to headings
- Broken links detection

**Use case:** Preventing broken links in documentation after reorganization

---

## Script Organization

```
scripts/
├── sync_specs.py           # TOML → spec table generation
├── setup_hooks.sh          # Git hook installation
├── check_formatting.py     # Doc formatting validation
├── check_links.py          # Link validation
└── README.md              # This file
```

---

## When to Run

### Always Run
- **sync_specs.py** - After any TOML config change
- **Pre-commit hook** - Runs automatically before commits

### Periodic Checks
- **check_formatting.py** - Before major doc updates
- **check_links.py** - After reorganizing docs

---

## Adding New Scripts

When adding scripts to this directory:

1. Make script executable: `chmod +x scripts/your_script.sh`
2. Add shebang: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`
3. Document in this README
4. Follow naming convention: `lowercase_with_underscores`

---

**Last Updated:** 2025-11-21
