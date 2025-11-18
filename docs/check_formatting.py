#!/usr/bin/env python3
import re
import os
from pathlib import Path
from collections import defaultdict

def analyze_formatting(spec_files):
    """Analyze formatting consistency across spec files."""

    results = {
        'headings': defaultdict(list),
        'tables': defaultdict(list),
        'code_blocks': defaultdict(list),
        'lists': defaultdict(list),
        'bold_patterns': defaultdict(list),
        'spacing': defaultdict(list),
    }

    for spec_file in spec_files:
        file_path = os.path.join('/home/niltempus/dev/ec4x/docs/specs', spec_file)

        with open(file_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # Check heading patterns
        for i, line in enumerate(lines, 1):
            # Headings
            if re.match(r'^#{1,6}\s+', line):
                level = len(re.match(r'^(#+)', line).group(1))
                has_space_after = bool(re.match(r'^#+\s+', line))
                results['headings'][spec_file].append({
                    'line': i,
                    'level': level,
                    'text': line.strip(),
                    'has_space': has_space_after
                })

            # Tables (check alignment patterns)
            if '|' in line and not line.strip().startswith('<!--'):
                results['tables'][spec_file].append({
                    'line': i,
                    'text': line.strip(),
                    'has_leading_pipe': line.strip().startswith('|'),
                    'has_trailing_pipe': line.strip().endswith('|')
                })

            # Code blocks
            if line.strip().startswith('```'):
                results['code_blocks'][spec_file].append({
                    'line': i,
                    'text': line.strip()
                })

            # List items
            if re.match(r'^\s*[-*]\s+', line):
                indent = len(line) - len(line.lstrip())
                results['lists'][spec_file].append({
                    'line': i,
                    'indent': indent,
                    'marker': line.lstrip()[0],
                    'text': line.strip()
                })

            # Bold patterns
            if '**' in line:
                # Check if bold is followed by colon
                bold_with_colon = bool(re.search(r'\*\*[^*]+\*\*:', line))
                results['bold_patterns'][spec_file].append({
                    'line': i,
                    'has_colon': bold_with_colon,
                    'text': line.strip()
                })

    return results

def check_heading_consistency(results):
    """Check for heading style consistency."""
    issues = []

    # Check if all headings have space after #
    for file, headings in results['headings'].items():
        for h in headings:
            if not h['has_space']:
                issues.append(f"{file}:{h['line']} - Heading missing space after #: {h['text']}")

    # Check section numbering patterns
    for file, headings in results['headings'].items():
        h1_headings = [h for h in headings if h['level'] == 1]
        for h in h1_headings:
            # Check if it starts with a number (like "3.0 Economics")
            if re.match(r'^#\s+\d+\.\d+\s+', h['text']):
                # This is good - numbered section
                pass
            elif re.match(r'^#\s+[A-Z]', h['text']):
                # Title case without number
                pass
            else:
                issues.append(f"{file}:{h['line']} - Unusual H1 format: {h['text']}")

    return issues

def check_table_consistency(results):
    """Check table formatting consistency."""
    issues = []

    for file, tables in results['tables'].items():
        if not tables:
            continue

        # Group consecutive table lines
        table_groups = []
        current_group = []

        for i, table in enumerate(tables):
            if not current_group or table['line'] == tables[i-1]['line'] + 1:
                current_group.append(table)
            else:
                if current_group:
                    table_groups.append(current_group)
                current_group = [table]

        if current_group:
            table_groups.append(current_group)

        # Check each table for consistency
        for group in table_groups:
            if len(group) < 2:
                continue

            # Check if table has consistent pipe usage
            has_leading = [t['has_leading_pipe'] for t in group]
            has_trailing = [t['has_trailing_pipe'] for t in group]

            if not all(has_leading):
                issues.append(f"{file} - Table starting line {group[0]['line']}: Inconsistent leading pipes")
            if not all(has_trailing):
                issues.append(f"{file} - Table starting line {group[0]['line']}: Inconsistent trailing pipes")

    return issues

def check_list_consistency(results):
    """Check list formatting consistency."""
    issues = []

    for file, lists in results['lists'].items():
        if not lists:
            continue

        # Check if file uses consistent list markers (- vs *)
        markers = set(item['marker'] for item in lists)
        if len(markers) > 1:
            issues.append(f"{file} - Mixed list markers: {markers}")

    return issues

def check_code_block_consistency(results):
    """Check code block formatting."""
    issues = []

    for file, blocks in results['code_blocks'].items():
        # Code blocks should come in pairs (opening and closing)
        if len(blocks) % 2 != 0:
            issues.append(f"{file} - Unmatched code block delimiters (count: {len(blocks)})")

    return issues

def main():
    spec_files = [
        'index.md',
        'gameplay.md',
        'assets.md',
        'economy.md',
        'operations.md',
        'diplomacy.md',
        'reference.md'
    ]

    print("=" * 80)
    print("FORMATTING CONSISTENCY ANALYSIS")
    print("=" * 80)
    print()

    results = analyze_formatting(spec_files)

    all_issues = []

    # Check headings
    print("Checking heading consistency...")
    heading_issues = check_heading_consistency(results)
    all_issues.extend(heading_issues)

    # Check tables
    print("Checking table consistency...")
    table_issues = check_table_consistency(results)
    all_issues.extend(table_issues)

    # Check lists
    print("Checking list consistency...")
    list_issues = check_list_consistency(results)
    all_issues.extend(list_issues)

    # Check code blocks
    print("Checking code block consistency...")
    code_issues = check_code_block_consistency(results)
    all_issues.extend(code_issues)

    print()
    print("=" * 80)
    print("RESULTS")
    print("=" * 80)
    print()

    if all_issues:
        print(f"Found {len(all_issues)} formatting issues:\n")
        for issue in all_issues:
            print(f"  ❌ {issue}")
    else:
        print("✅ No formatting issues found!")

    print()
    print("=" * 80)
    print("FORMATTING PATTERNS SUMMARY")
    print("=" * 80)
    print()

    # Summary statistics
    for file in spec_files:
        print(f"\n{file}:")
        print(f"  Headings: {len(results['headings'].get(file, []))}")
        print(f"  Tables: {len(results['tables'].get(file, []))} lines")
        print(f"  Code blocks: {len(results['code_blocks'].get(file, []))} delimiters")
        print(f"  List items: {len(results['lists'].get(file, []))}")

        # Show list marker if any
        lists = results['lists'].get(file, [])
        if lists:
            markers = set(item['marker'] for item in lists)
            print(f"  List markers: {', '.join(markers)}")

if __name__ == '__main__':
    main()
