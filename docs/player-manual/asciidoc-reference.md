# AsciiDoc Quick Reference Guide

## Document Header

```asciidoc
= Document Title
Author Name <author@email.com>
v1.0, 2025-12-05
:doctype: book
:toc: left
:toclevels: 3
:sectnums:
:sectnumlevels: 3
:icons: font
:source-highlighter: rouge
```

**Common Attributes:**
- `:toc:` - Table of contents position (left, right, macro, preamble)
- `:toclevels:` - TOC depth (1-5)
- `:sectnums:` - Enable section numbering
- `:icons:` - Icon style (font, image, or none)
- `:source-highlighter:` - Code highlighting (rouge, pygments, highlight.js)
- `:imagesdir:` - Default images directory

---

## Headers

```asciidoc
= Document Title (Level 0)

== Chapter Title (Level 1)

=== Section Title (Level 2)

==== Subsection Title (Level 3)

===== Subsubsection (Level 4)
```

**Note:** Use `=` signs equal to heading depth. Top-level is `=`, then `==`, `===`, etc.

---

## Paragraphs

```asciidoc
Normal paragraph text. Separate paragraphs with blank lines.

Another paragraph here.

.Optional paragraph title
This paragraph has a title above it.
```

**Line Breaks:**
```asciidoc
First line +
Second line (manual break with +)

Or use [%hardbreaks] attribute:

[%hardbreaks]
Line 1
Line 2
Line 3
```

---

## Text Formatting

```asciidoc
*bold text*
_italic text_
*_bold and italic_*
`monospace/code`
^superscript^
~subscript~
#highlight#
[.underline]#underlined text#
```

**Examples:**
- *bold text*
- _italic text_
- `code text`

---

## Lists

### Unordered Lists

```asciidoc
* Level 1
** Level 2
*** Level 3
**** Level 4

- Also works with hyphens
- Another item
- Third item
```

### Ordered Lists

```asciidoc
. First item
. Second item
.. Nested item
.. Another nested
. Third item

1. Explicit numbering
2. Second
3. Third
```

### Definition Lists

```asciidoc
Term 1:: Definition 1
Term 2:: Definition 2

Or horizontal style:

[horizontal]
CPU:: Central Processing Unit
RAM:: Random Access Memory
```

### Checklists

```asciidoc
* [*] Checked item
* [x] Also checked
* [ ] Unchecked item
```

---

## Links

### External Links

```asciidoc
https://example.com[Link text]
https://example.com (automatic)
link:path/to/file.pdf[PDF document]
```

### Internal Cross-References

```asciidoc
[[anchor-id]]
== Section Title

Reference it with: <<anchor-id>>
Or with custom text: <<anchor-id,Custom link text>>
```

### Email Links

```asciidoc
mailto:user@example.com[Email me]
```

---

## Images

```asciidoc
image::filename.png[]
image::filename.png[Alt text]
image::filename.png[Alt text,300,200]
image::filename.png[Alt text,width=300,height=200]

.Image with caption
image::diagram.png[System Architecture]

Inline image: image:icon.png[Icon]
```

**Attributes:**
- `width` - Image width
- `height` - Image height
- `align` - left, center, right
- `float` - left, right

---

## Code Blocks

### Listing Block

```asciidoc
----
Plain code block
No syntax highlighting
----
```

### Source Code Block

```asciidoc
[source,python]
----
def hello():
    print("Hello, World!")
----

[source,nim]
----
proc greet(name: string) =
  echo "Hello, ", name
----
```

**Supported Languages:** python, nim, javascript, ruby, java, c, cpp, rust, go, bash, etc.

### Inline Code

```asciidoc
Use `code` for inline code.
```

### Code with Line Numbers

```asciidoc
[source,python,linenums]
----
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n-1) + fibonacci(n-2)
----
```

---

## Tables

### Basic Table

```asciidoc
|===
|Header 1 |Header 2 |Header 3

|Cell 1,1
|Cell 1,2
|Cell 1,3

|Cell 2,1
|Cell 2,2
|Cell 2,3
|===
```

### Table with Options

```asciidoc
[cols="1,2,3", options="header"]
|===
|Name |Description |Value

|Item 1
|Description of item 1
|100

|Item 2
|Description of item 2
|200
|===
```

**Common Options:**
- `header` - First row is header
- `footer` - Last row is footer
- `autowidth` - Auto-size columns
- `width="50%"` - Table width

### Column Alignment

```asciidoc
[cols="<,^,>", options="header"]
|===
|Left |Center |Right

|Left-aligned
|Center-aligned
|Right-aligned
|===
```

**Alignment:**
- `<` - Left
- `^` - Center
- `>` - Right

### CSV Table

```asciidoc
[%header,format=csv]
|===
Name,Age,City
Alice,30,NYC
Bob,25,LA
|===
```

---

## Block Elements

### Sidebar

```asciidoc
.Optional Title
****
Sidebar content here.
Sidebars are used for related content.
****
```

### Example Block

```asciidoc
.Example Title
====
This is an example block.
Use it to highlight examples.
====
```

### Quote Block

```asciidoc
[quote,Author Name,Book Title]
____
This is a quote from someone famous.
It can span multiple lines.
____

Or simple quote:

____
Just a quote without attribution.
____
```

### Admonition Blocks

```asciidoc
NOTE: This is a note.

TIP: This is a helpful tip.

IMPORTANT: This is important information.

WARNING: This is a warning.

CAUTION: Be cautious about this.
```

**Block Style:**

```asciidoc
[NOTE]
====
This is a multi-line note
with more detailed information
spanning multiple paragraphs.
====
```

---

## Horizontal Rules

```asciidoc
'''

Content above the rule.

'''

Content below the rule.
```

---

## Page Breaks

```asciidoc
<<<

Content after page break (PDF output).
```

---

## Comments

```asciidoc
// Single line comment

////
Multi-line comment block
Everything here is ignored
////
```

---

## Includes

```asciidoc
include::chapter1.adoc[]

include::shared-content.adoc[lines=1..10]

include::code-example.py[lines=5..15]
```

---

## Special Characters

```asciidoc
(C) → ©
(R) → ®
(TM) → ™
-- → —  (em dash)
... → …  (ellipsis)
-> → →  (right arrow)
<- → ←  (left arrow)
=> → ⇒  (double right arrow)
<= → ⇐  (double left arrow)
```

---

## Document Structure

### Book with Chapters

```asciidoc
= Book Title
:doctype: book

[preface]
== Preface
Preface content.

[[chapter-1]]
== Chapter 1: Introduction
Chapter 1 content.

[[chapter-2]]
== Chapter 2: Details
Chapter 2 content.

[appendix]
== Appendix A: Reference
Appendix content.

[glossary]
== Glossary
Term:: Definition

[index]
== Index
Generated automatically.
```

### Article Structure

```asciidoc
= Article Title
:doctype: article

[abstract]
Abstract text goes here.

== Section 1
Content.

== Section 2
More content.
```

---

## PDF-Specific Features

### Title Page

```asciidoc
= Document Title
Author Name
:doctype: book
:title-page:
:front-cover-image: image:cover.png[]
:back-cover-image: image:backcover.png[]
```

### PDF Theme

```asciidoc
= Document Title
:pdf-theme: custom-theme.yml
:pdf-themesdir: themes
```

### Page Numbering

```asciidoc
:pagenums:
:chapter-label: Chapter
```

---

## Conditional Content

### If Attribute Set

```asciidoc
ifdef::draft[]
This content only appears if draft attribute is set.
endif::[]

ifndef::final[]
This appears unless final attribute is set.
endif::[]
```

### Multiple Conditions

```asciidoc
ifdef::draft,review[]
Appears if either draft OR review is set.
endif::[]

ifdef::draft+review[]
Appears only if BOTH draft AND review are set.
endif::[]
```

---

## Macros

### Keyboard Shortcuts

```asciidoc
Press kbd:[Ctrl+C] to copy.
kbd:[Ctrl+Alt+Del]
```

### Buttons

```asciidoc
Click btn:[OK] to continue.
```

### Menu Selections

```asciidoc
Select menu:File[Open] to open a file.
menu:View[Zoom > 200%]
```

---

## Advanced Tables

### Cell Spanning

```asciidoc
|===
|Column 1 |Column 2 |Column 3

|Normal cell
2+|Spans 2 columns

|Spans 2 rows .2+|Normal
|Normal

|Normal cell
|Normal cell
|===
```

### Cell Formatting

```asciidoc
|===
|Normal |*Bold* |`Code`

a|
* Item 1
* Item 2

|Normal cell

|[source,python]
----
def hello():
    pass
----
|===
```

**Cell Specifiers:**
- `a` - AsciiDoc content (allows formatting)
- `l` - Literal (monospace)
- `s` - Strong (bold)
- `e` - Emphasis (italic)
- `m` - Monospace

---

## Generation Commands

### HTML Output

```bash
asciidoctor document.adoc
asciidoctor -o output.html document.adoc
```

### PDF Output

```bash
asciidoctor-pdf document.adoc
asciidoctor-pdf -a pdf-theme=custom.yml document.adoc
```

### With Attributes

```bash
asciidoctor -a toc=left -a toclevels=3 document.adoc
asciidoctor-pdf -a pdf-themesdir=themes document.adoc
```

---

## Best Practices

### Document Organization

1. **Use semantic markup** - Don't use formatting for structure
2. **One sentence per line** - Easier version control
3. **Blank lines** - Separate paragraphs and blocks
4. **Consistent indentation** - Use 2 spaces for nested content
5. **Cross-references** - Use anchors and links liberally

### Performance

1. **Split large documents** - Use includes for chapters
2. **Optimize images** - Compress before including
3. **Cache builds** - Use build tools for large projects

### Maintainability

1. **Comment complex sections** - Use `//` comments
2. **Consistent naming** - Use kebab-case for file names
3. **Anchor naming** - Use descriptive IDs
4. **Validate often** - Check output regularly

---

## Common Gotchas

### Bold vs Headers

```asciidoc
*This is bold*

== This is a header
```

**Don't forget the space after `==`!**

### List Continuation

```asciidoc
* First item
+
Continued paragraph for first item.

* Second item
```

**Use `+` on its own line to continue.**

### Inline Passthrough

```asciidoc
Use +++<u>HTML</u>+++ for raw HTML.
Use pass:[<u>HTML</u>] for inline passthrough.
```

---

## Resources

**Official Documentation:**
- https://docs.asciidoctor.org/asciidoc/latest/
- https://docs.asciidoctor.org/pdf-converter/latest/

**Cheat Sheets:**
- https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/

**Editor Support:**
- VSCode: `asciidoctor.asciidoctor-vscode`
- Vim: `habamax/vim-asciidoctor`
- Emacs: `adoc-mode`

**PDF Theming:**
- https://docs.asciidoctor.org/pdf-converter/latest/theme/

---

## Quick Start Template

```asciidoc
= My Document Title
Author Name
v1.0, 2025-12-05
:doctype: book
:toc: left
:toclevels: 3
:sectnums:
:icons: font
:source-highlighter: rouge

[preface]
== Introduction

Your introduction text here.

== Chapter 1: Getting Started

Chapter content here.

=== Section 1.1

Subsection content.

== Chapter 2: Advanced Topics

More content.

[appendix]
== Appendix A: Reference

Reference material.

[glossary]
== Glossary

Term:: Definition of term
Another Term:: Definition here
```

---

**Generate PDF:**

```bash
asciidoctor-pdf my-document.adoc
```

**View output:**

```bash
zathura my-document.pdf
```

---

*Last Updated: December 5, 2025*
