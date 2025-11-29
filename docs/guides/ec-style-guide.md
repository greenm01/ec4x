# Esterian Conquest Writing Style Guide

## Voice and Tone

### Core Characteristics
- **Confident and authoritative** without being condescending
- **Direct address** using "you" and "your" to engage the player
- **Aspirational tone** that treats the player as a capable commander
- **Matter-of-fact** about complexity while emphasizing accessibility

### Personality
- Enthusiastic but not hyperbolic
- Professional without being stiff
- Assumes player competence while providing necessary detail
- Uses grandeur appropriate to the sci-fi setting without melodrama

---

## Structural Principles

### Document Organization
- Clear hierarchical structure using standard heading levels
- Frontload key features before diving into details
- Reference material separated from tutorial content
- Horizontal rules (`---`) to separate major conceptual shifts
- Use definition lists for feature descriptions where supported

### Markdown Format

```markdown
# Major Section Name

Introduction and overview.

## Subsection Name

Subsection content with direct, confident voice.

### Feature or Concept Name

Detailed explanation.

**Key Term or Capability**: Description follows immediately.

---

Horizontal rule separates major conceptual shifts.
```

### AsciiDoc Format

```asciidoc
= Major Section Name

Introduction and overview.

== Subsection Name

Subsection content with direct, confident voice.

=== Feature or Concept Name

Detailed explanation.

*Key Term*:: Description in definition list format.

'''

Three apostrophes create horizontal rule for conceptual shifts.
```

### Heading Hierarchy
- **H1**: Document title or major section (game systems, campaign rules)
- **H2**: Subsections within major topics (combat mechanics, economic system)
- **H3**: Specific features or concepts (mission types, fleet composition)
- **H4**: Fine details (rare, use sparingly)

---

## Language Patterns

### Opening Statements
- Lead with bold declarations about capabilities
- "Welcome to..." for introductory material
- "The year is..." for narrative framing
- Use present tense for immediacy ("you are the leader...")

### Feature Descriptions
- Start with capability name in bold
- Follow with concrete details
- Use active verbs: "Command", "Order", "Direct", "Issue"
- Quantify where possible (7 types, 15 missions, 25 players)
- End feature lists with broad summative statements

### Instructional Voice
- "You can..." for describing player actions
- "You must..." only for critical requirements
- "You may..." for optional advanced features
- Avoid "should" — either it's required or it's optional

### Transitional Phrases
- "To our knowledge" for claims
- "We think you'll agree" for confident assertions
- "Note:" for important callouts
- "Remember:" for key concepts

---

## Vocabulary Choices

### Preferred Terms
- "Campaign" over "game session"
- "Round" over "turn"
- "Forces" over "units"
- "Mission" over "action" or "order"
- "Sophisticated" over "complex"
- "Easy to use" over "simple" or "user-friendly"

### Avoid
- Corporate jargon
- Academic hedging ("perhaps", "might", "possibly")
- Modern internet slang
- Overly casual contractions in formal sections
- Passive voice in instructions

---

## Sentence Structure

### Rhythm
- Vary sentence length but favor medium-length sentences (15-25 words)
- Use short sentences for impact: "Your goal is simple: Conquer and rule the universe."
- Break up longer technical descriptions with colons and semicolons
- Occasional fragments for emphasis acceptable in marketing copy

### Lists and Series
- Use parallel structure religiously
- Begin list items with verbs or noun phrases consistently
- Capitalize first word of each list item
- Include periods only if items are complete sentences

---

## Game-Specific Conventions

### Narrative Voice
- Year 3000 setting provides historical distance
- Refer to the Esterians as mysterious past rulers
- Frame player as emerging leader in power vacuum
- Maintain epic scale: "galactic", "empire", "conquest"

### Strategic Guidance
- Acknowledge challenge: "The odds are against you"
- Encourage discovery: "you must discover the best strategies on your own"
- Balance hand-holding with respect for player intelligence
- Separate basic from advanced strategies clearly

### Technical Descriptions
- Lead with user benefit before explaining mechanism
- "Sophisticated simulations" over "complex algorithms"
- Describe outcomes, not implementation details
- Use concrete numbers for clarity

---

## Formatting Conventions

### Emphasis
- **Bold** for feature names, key terms, and important concepts
- *Italic* for emphasis within sentences (use sparingly)
- `Code formatting` for technical terms, commands, or literal input
- Regular case for body text (avoid ALL CAPS in modern markdown)

### Spacing
- Single blank line between paragraphs
- Horizontal rules (`---`) between major conceptual shifts
- Consistent indentation for nested lists
- No extra spacing within code blocks or technical specifications

### Modern Adaptations
- Headers use standard markdown/AsciiDoc levels (no ASCII art decoration)
- Visual hierarchy comes from semantic markup, not decorative characters
- Tables for complex data (markdown tables or AsciiDoc table blocks)
- Code blocks for examples, commands, or technical specifications

---

## Special Elements

### Quick Reference Material
- Appendices for detailed specifications
- Bullet points acceptable in reference sections
- Tables for rules and statistics
- Internal links for cross-references (no page numbers in digital docs)

### Marketing Copy
- Lead with superlatives that can be defended
- "Most sophisticated", "Most popular" with qualifiers
- Feature lists with concrete capabilities
- Avoid vague promises ("better", "improved")

### Callouts and Admonitions

**Markdown:**
```markdown
**Note:** Important information that affects gameplay.

**Remember:** Key concept for strategic success.

**Warning:** Critical requirement or consequence.
```

**AsciiDoc:**
```asciidoc
NOTE: Important information that affects gameplay.

TIP: Strategic advice for experienced players.

WARNING: Critical requirement or consequence.
```

---

## Things to Avoid

- Don't apologize for complexity
- Don't oversell with empty adjectives
- Don't patronize with excessive hand-holding
- Don't break fourth wall once narrative is established
- Don't mix tutorial voice with reference voice in same section
- Don't use humor that dates the material
- Don't use decorative ASCII art (equals signs, dash lines for headers)
- Don't use ALL CAPS for headers in body text

---

## Voice Examples

**Strong:**
> Command the forces of a planetary empire, plan your campaign, colonize new worlds and defeat your enemies.

**Weak:**
> You'll be able to control various units and manage your civilization as you try to win.

**Strong:**
> The odds are against you, but if you survive, and plan your strategies well, you may indeed attain the emperor's crown.

**Weak:**
> It's pretty hard but you might win if you're lucky and play smart.

---

## Documentation Philosophy

- Players learn rules quickly; strategy takes time
- Separate "what you can do" from "how to do it well"
- Reference material supports play, doesn't replace discovery
- Manual is authoritative but game is teacher
- Respect player's time with clear organization
- Assume literate, motivated audience

---

## Modern Technical Adaptations

### Digital Distribution
- Internal hyperlinks replace page number references
- Search-friendly headers without decorative characters
- Mobile-responsive formatting considerations
- Semantic markup over visual decoration

### Rendering Targets
- HTML for web documentation
- PDF for traditional manual format
- In-game help systems with limited formatting
- README files for repository documentation

### Version Control
- Clean diffs matter: avoid ASCII art that creates noise
- Markdown for maximum compatibility
- AsciiDoc for complex multi-format output needs
- Plain text readability preserved in both formats

---

## Implementation Notes

The retro feel comes from **voice and tone**, not ASCII decoration. Modern semantic markup provides:
- Better accessibility
- Cleaner version control
- Multi-format output
- Search engine optimization
- Mobile compatibility

Preserve the confident, authoritative voice. Maintain the epic scale. Keep the direct address and active verbs. Let standard heading levels and horizontal rules provide structure. The style guide's power is in its language patterns, not its visual artifacts from the plain-text era.
