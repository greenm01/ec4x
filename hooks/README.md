# Git Hooks

This directory contains git hooks that should be installed in your local repository.

## Installation

To install the pre-commit hook:

```bash
cp hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Pre-Commit Hook

The pre-commit hook runs automatically before each commit and checks:

1. **Code Quality**
   - All enums are {.pure.}
   - Constants use camelCase

2. **Build Verification**
   - Project compiles successfully

3. **Test Suite**
   - Critical integration tests pass

4. **Stress Testing** (NEW)
   - Quick stress test validates engine stability
   - Runs in ~2 seconds
   - Catches performance regressions and state corruption

## Bypassing the Hook

If you need to commit without running checks (not recommended):

```bash
git commit --no-verify
```
