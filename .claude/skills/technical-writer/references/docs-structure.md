# Morphir Documentation Structure Guide

This guide describes the organization of Morphir documentation and where different types of content should be placed.

## Documentation Sections

### getting-started/
**Purpose:** Entry point for new users

**Content Types:**
- Introduction and overview (intro.md)
- Installation instructions (installation.md)
- Quick start tutorials (tutorials.md)
- Editor/IDE setup guides
- First steps with Morphir

**Guidelines:**
- Keep content beginner-friendly
- Avoid jargon or explain it immediately
- Include screenshots and examples
- Link to deeper documentation for advanced topics

### cli-preview/
**Purpose:** Documentation for the next-generation Go CLI

**Content Types:**
- CLI overview and philosophy
- Command reference
- Getting started with the CLI
- Migration guides
- Release notes

**Guidelines:**
- Keep command documentation up-to-date with CLI changes
- Include practical examples for each command
- Document flags and options clearly

### concepts/
**Purpose:** Explain core Morphir concepts and theory

**Content Types:**
- Introduction to Morphir
- Morphir IR explanation
- Why functional programming
- SDK overview
- Theoretical foundations

**Guidelines:**
- Focus on "why" not just "how"
- Use diagrams where helpful
- Connect concepts to practical benefits

### spec/
**Purpose:** Technical specifications and schemas

**Content Types:**
- IR specification
- JSON schemas for IR versions
- Format documentation

**Guidelines:**
- Be precise and complete
- Version clearly
- Include schema examples

### user-guides/
**Purpose:** Practical guides for users

**Subdirectories:**
- `modeling-guides/` - How to model business logic
- `cli-tools/` - Using command-line tools
- `development-guides/` - Development techniques

**Guidelines:**
- Task-oriented content
- Step-by-step instructions
- Include working examples

### reference/
**Purpose:** Technical reference documentation

**Subdirectories:**
- `backends/` - Backend-specific documentation
  - `scala/` - Scala backend
  - `spark/` - Spark backend
  - `other-platforms/` - TypeScript, CADL, etc.
- `json-schema/` - JSON schema documentation
- `cli/` - CLI reference

**Guidelines:**
- Comprehensive API documentation
- Include all options and parameters
- Provide code examples

### developers/
**Purpose:** Guides for contributors

**Content Types:**
- Contributing guide
- Development setup
- Architecture documentation
- Release process

**Guidelines:**
- Keep up-to-date with processes
- Include troubleshooting tips
- Document development workflows

### community/
**Purpose:** Community resources

**Content Types:**
- Community information
- Code of conduct
- FAQs
- Media and presentations

**Guidelines:**
- Keep contact info current
- Maintain welcoming tone

### use-cases/
**Purpose:** Real-world applications

**Content Types:**
- Case studies
- Domain-specific examples
- Success stories

**Guidelines:**
- Focus on outcomes
- Include lessons learned

### adr/
**Purpose:** Architecture Decision Records

**Content Types:**
- Architectural decisions
- Technical choices
- Design rationale

**Guidelines:**
- Follow ADR template
- Include context and consequences
- Date decisions

## File Naming Conventions

- Use lowercase with hyphens: `my-document.md`
- Be descriptive but concise
- Avoid special characters
- Use index.md for directory landing pages

## Frontmatter Requirements

Every markdown file should have:

```yaml
---
title: Document Title
sidebar_position: 1
sidebar_label: Short Label  # Optional, if different from title
---
```

## Cross-Referencing

- Use relative paths for internal links
- Include file extension: `[link](./other-doc.md)`
- Check links before committing
