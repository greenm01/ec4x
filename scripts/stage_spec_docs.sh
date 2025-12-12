#!/bin/bash
# This script stages all spec documentation markdown files for a commit.

set -e # Exit on error

echo "Staging all markdown files in docs/specs/..."
git add docs/specs/*.md
echo "Done."
