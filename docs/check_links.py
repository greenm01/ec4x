#!/usr/bin/env python3
import re
import os
import sys
from pathlib import Path

def extract_links(file_path):
    """Extract all markdown links from a file."""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Match [text](url) or [text](url#anchor)
    pattern = r'\[([^\]]+)\]\(([^\)]+)\)'
    links = re.findall(pattern, content)
    return links

def generate_anchor(heading_text):
    """Generate markdown anchor from heading text."""
    # Convert to lowercase
    anchor = heading_text.lower()
    # Remove special chars except spaces and hyphens
    anchor = re.sub(r'[^a-z0-9\s\-]', '', anchor)
    # Replace spaces with hyphens
    anchor = re.sub(r'\s+', '-', anchor)
    return anchor

def extract_headings(file_path):
    """Extract all headings from a markdown file."""
    if not os.path.exists(file_path):
        return []

    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Match headings (# through ######)
    pattern = r'^#{1,6}\s+(.+)$'
    headings = re.findall(pattern, content, re.MULTILINE)

    # Generate anchors for each heading
    anchors = [generate_anchor(h) for h in headings]
    return anchors

def check_links(base_dir, file_path):
    """Check all links in a file."""
    links = extract_links(file_path)
    results = []

    file_rel = os.path.relpath(file_path, base_dir)

    for link_text, link_url in links:
        # Skip external links (http, https, mailto, etc.)
        if link_url.startswith(('http://', 'https://', 'mailto:', 'ftp://')):
            continue

        # Split URL and anchor
        if '#' in link_url:
            url_part, anchor_part = link_url.split('#', 1)
        else:
            url_part = link_url
            anchor_part = None

        # Resolve the target file path
        if url_part:
            # Relative link
            target_path = os.path.normpath(os.path.join(os.path.dirname(file_path), url_part))
        else:
            # Anchor-only link (same file)
            target_path = file_path

        # Check if file exists
        if url_part and not os.path.exists(target_path):
            results.append({
                'file': file_rel,
                'link_text': link_text,
                'link_url': link_url,
                'status': 'BROKEN',
                'reason': f'File not found: {os.path.relpath(target_path, base_dir)}'
            })
            continue

        # Check if anchor exists
        if anchor_part:
            headings = extract_headings(target_path)
            if anchor_part not in headings:
                results.append({
                    'file': file_rel,
                    'link_text': link_text,
                    'link_url': link_url,
                    'status': 'BROKEN',
                    'reason': f'Anchor not found: #{anchor_part} in {os.path.relpath(target_path, base_dir)}'
                })
                continue

        # Link is valid
        results.append({
            'file': file_rel,
            'link_text': link_text,
            'link_url': link_url,
            'status': 'OK',
            'reason': None
        })

    return results

def main():
    base_dir = '/home/niltempus/dev/ec4x/docs'
    spec_files = [
        'specs/assets.md',
        'specs/diplomacy.md',
        'specs/economy.md',
        'specs/gameplay.md',
        'specs/glossary.md',
        'specs/index.md',
        'specs/operations.md',
        'specs/reference.md'
    ]

    all_results = []
    broken_count = 0
    ok_count = 0

    for spec_file in spec_files:
        file_path = os.path.join(base_dir, spec_file)
        results = check_links(base_dir, file_path)
        all_results.extend(results)

    # Print results
    print("=" * 80)
    print("LINK VALIDATION REPORT")
    print("=" * 80)
    print()

    # Group by file
    current_file = None
    for result in all_results:
        if result['file'] != current_file:
            current_file = result['file']
            print(f"\n{current_file}:")
            print("-" * 80)

        status_icon = "✅" if result['status'] == 'OK' else "❌"
        print(f"  {status_icon} [{result['link_text']}]({result['link_url']})")

        if result['status'] == 'BROKEN':
            print(f"      ERROR: {result['reason']}")
            broken_count += 1
        else:
            ok_count += 1

    # Summary
    print()
    print("=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"Total links checked: {len(all_results)}")
    print(f"✅ Valid links: {ok_count}")
    print(f"❌ Broken links: {broken_count}")
    print()

    if broken_count > 0:
        sys.exit(1)
    else:
        print("All links are valid!")
        sys.exit(0)

if __name__ == '__main__':
    main()
