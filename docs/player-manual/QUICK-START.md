# EC4X Player Manual - Quick Start

## ✓ STATUS: READY FOR PDF GENERATION

All errors fixed. Manual validated. Ready to generate professional PDF.

## Generate PDF (3 Easy Steps)

### Step 1: Install AsciiDoctor

```bash
# Install Ruby (if not already installed)
sudo pacman -S ruby

# Install asciidoctor gems
gem install asciidoctor asciidoctor-pdf rouge --user-install

# Add to PATH (run once)
echo 'export PATH="$HOME/.local/share/gem/ruby/3.3.0/bin:$PATH"' >> ~/.config/fish/config.fish
source ~/.config/fish/config.fish
```

### Step 2: Navigate and Generate

```bash
cd /mnt/user-data/outputs
asciidoctor-pdf EC4X-Player-Manual.adoc
```

### Step 3: View Result

```bash
zathura EC4X-Player-Manual.pdf
# or
evince EC4X-Player-Manual.pdf
# or
okular EC4X-Player-Manual.pdf
```

## What You Get

- **210-page professional manual** (estimated)
- **11 chapters** with proper numbering
- **53 data tables** beautifully formatted
- **Clean table of contents** with 3 levels
- **Professional typography**

## Files Ready

```
/mnt/user-data/outputs/
├── EC4X-Player-Manual.adoc          ✓ Fixed and validated
├── README.md                         ✓ Full documentation
├── asciidoc-reference.md             ✓ Syntax guide
├── FIX-SUMMARY.md                    ✓ What was fixed
├── VALIDATION-REPORT.md              ✓ Validation results
├── BEFORE-AFTER-COMPARISON.txt       ✓ Visual examples
└── QUICK-START.md                    ✓ This file
```

## Troubleshooting

### If 'gem' command not found:
```bash
sudo pacman -S ruby
```

### If asciidoctor-pdf not found after install:
```bash
# Check gem bin directory
ls ~/.local/share/gem/ruby/*/bin/

# Add correct version to PATH
export PATH="$HOME/.local/share/gem/ruby/3.3.0/bin:$PATH"
```

### If you see warnings about 'rouge':
```bash
gem install rouge --user-install
```

## Custom Styling (Optional)

Create `ec4x-theme.yml`:

```yaml
extends: default
page:
  margin: [0.75in, 1in, 0.75in, 1in]
  size: Letter
base:
  font-family: Noto Sans
  font-size: 10
heading:
  font-family: Noto Sans
  font-weight: bold
  h1-font-size: 28
code:
  font-family: JetBrains Mono
  font-size: 9
```

Generate with theme:
```bash
asciidoctor-pdf -a pdf-theme=ec4x-theme.yml EC4X-Player-Manual.adoc
```

## Alternative: Docker Method

If you don't want to install Ruby:

```bash
docker pull asciidoctor/docker-asciidoctor
docker run --rm -v $(pwd):/documents asciidoctor/docker-asciidoctor \
  asciidoctor-pdf EC4X-Player-Manual.adoc
```

## What Was Fixed

✓ Chapter numbering (= → ==)
✓ All 53 tables converted to AsciiDoc
✓ Single-line cell formatting
✓ Column alignment preserved
✓ No syntax errors
✓ Validated and ready

## Need Help?

Check these files:
- `VALIDATION-REPORT.md` - What was fixed
- `README.md` - Full documentation
- `asciidoc-reference.md` - Syntax help

---

**Ready to generate your manual!**

Just run: `asciidoctor-pdf EC4X-Player-Manual.adoc`
