# EC4X Player Manual

## Overview

This directory contains the complete EC4X Player Manual in AsciiDoc format, consolidated from the game specification markdown files following the EC style guide.

## Manual Statistics

- **Format**: AsciiDoc (.adoc)
- **Total Lines**: 4,303
- **Sections**: 215 headings
- **Chapters**: 11 (plus dedication, preface, and reference tables)
- **Size**: 214 KB

## Chapter Structure

1. **Chapter 1: How to Play** - Core gameplay, prestige, turns, victory conditions
2. **Chapter 2: Game Assets** - Star maps, ships, units, facilities
3. **Chapter 3: Economics** - Production, taxation, research & development
4. **Chapter 4: Operations** - Fleet movement, orders, colonization
5. **Chapter 5: Combat** - Space combat, invasions, bombardment
6. **Chapter 6: Diplomacy & Espionage** - Diplomatic relations, covert operations
7. **Reference Tables** - Complete data tables for ships, units, and mechanics
8. **Chapter 11: Glossary** - Comprehensive term definitions

## Generating PDF

### Option 1: Using Asciidoctor (Recommended)

```bash
# Install asciidoctor and PDF backend
gem install asciidoctor asciidoctor-pdf

# Generate PDF with default styling
asciidoctor-pdf EC4X-Player-Manual.adoc

# Generate with custom theme (if you create one)
asciidoctor-pdf -a pdf-theme=custom-theme.yml EC4X-Player-Manual.adoc
```

### Option 2: Using Docker (No Ruby installation needed)

```bash
# Pull the official asciidoctor image
docker pull asciidoctor/docker-asciidoctor

# Generate PDF
docker run --rm -v $(pwd):/documents asciidoctor/docker-asciidoctor \
  asciidoctor-pdf EC4X-Player-Manual.adoc
```

### Option 3: Online Conversion

Upload `EC4X-Player-Manual.adoc` to one of these online converters:

- https://www.asciidoctoronline.com/ (supports PDF export)
- https://dillinger.io/ (markdown-focused but handles AsciiDoc)
- Use any AsciiDoc-to-PDF converter service

## Customization

### PDF Styling

Create a custom PDF theme YAML file for styling:

```yaml
# custom-theme.yml
page:
  margin: [0.75in, 1in, 0.75in, 1in]
  size: Letter
  
base:
  font-family: Liberation Sans
  font-size: 10
  line-height: 1.4
  
heading:
  font-family: Liberation Sans
  font-weight: bold
  h1-font-size: 24
  h2-font-size: 18
  h3-font-size: 14
  
code:
  font-family: Liberation Mono
  font-size: 9
```

Then generate with: `asciidoctor-pdf -a pdf-theme=custom-theme.yml EC4X-Player-Manual.adoc`

### Table of Contents

The TOC is already configured in the document header:

```asciidoc
:toc: left          # Position (left sidebar)
:toclevels: 3       # Depth (show up to h3)
:sectnums:          # Enable section numbering
:sectnumlevels: 3   # Number up to h3
```

To modify, edit the document header in the .adoc file.

## Source Files

The manual was generated from these markdown specification files:

- `index.md` - Introduction and overview
- `gameplay.md` - Chapter 1 (How to Play)
- `assets.md` - Chapter 2 (Game Assets)
- `economy.md` - Chapter 3 (Economics)
- `operations.md` - Chapters 4-5 (Operations & Combat)
- `diplomacy.md` - Chapter 6 (Diplomacy & Espionage)
- `reference.md` - Reference Tables
- `glossary.md` - Chapter 11 (Glossary)

## Conversion Notes

The manual was converted from Markdown to AsciiDoc with these transformations:

- Headers: `#` → `=` (with proper nesting)
- Bold: `**text**` → `*text*`
- Horizontal rules: `---` → `'''`
- Code blocks: ` ```python` → `[source,python]----`
- Internal links: `[text](file.md#anchor)` → `<<anchor,text>>`
- Tables: Preserved in original format (AsciiDoc-compatible)

## EC Style Guide Compliance

The manual follows the EC writing style guide principles:

✓ **Direct address** - "You command..." not "The player commands..."
✓ **Active voice** - "Command your forces" not "Forces can be commanded"
✓ **Confident tone** - Assertive without condescension
✓ **Minimal formatting** - Prose-first, lists only where necessary
✓ **Clear hierarchy** - Semantic markup, no decorative ASCII art
✓ **Strategic framing** - Emphasizes player agency and strategic decision-making

## Building From Source

To rebuild the manual from the specification markdown files:

```bash
python3 build_manual.py
```

This will regenerate `EC4X-Player-Manual.adoc` from the latest source files.

## License

See the main EC4X repository for license information.

---

Generated: 2025-12-05
Version: 0.1
