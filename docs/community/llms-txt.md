---
title: "LLM-Friendly Documentation"
sidebar_position: 5
description: "Access Morphir documentation in LLM-optimized formats"
---

# LLM-Friendly Documentation

Morphir provides documentation optimized for Large Language Models (LLMs) following the [llms.txt specification](https://llmstxt.org/).

## Available Files

| File | Description | Use Case |
|------|-------------|----------|
| [/llms.txt](/llms.txt) | Compact version with curated links | Quick context loading, smaller context windows |
| [/llms-full.txt](/llms-full.txt) | Full version with inline content | Comprehensive context, larger context windows |

## What is llms.txt?

The `/llms.txt` file is a markdown file that provides LLM-friendly content at a well-known location. Rather than requiring LLMs to parse full HTML pages, this standardized format offers:

- **Concise, expert-level documentation** in a single file
- **Structured sections** with curated links and descriptions
- **Context window friendly** sizing for different LLM capabilities

## Using with LLMs

### ChatGPT, Claude, and Other Chat Interfaces

You can reference the Morphir documentation by sharing the URL:

```
Please read https://morphir.finos.org/llms.txt and help me understand how to get started with Morphir.
```

### Programmatic Access

Fetch the documentation for use in your LLM applications:

```python
import requests

# Compact version
response = requests.get("https://morphir.finos.org/llms.txt")
morphir_docs = response.text

# Full version with inline content
response = requests.get("https://morphir.finos.org/llms-full.txt")
morphir_docs_full = response.text
```

```javascript
// Node.js / Deno
const compactDocs = await fetch("https://morphir.finos.org/llms.txt").then(r => r.text());
const fullDocs = await fetch("https://morphir.finos.org/llms-full.txt").then(r => r.text());
```

### With AI Code Assistants

Many AI code assistants can fetch and use llms.txt files directly:

```
@fetch https://morphir.finos.org/llms.txt
How do I validate a Morphir IR file against the JSON schema?
```

## File Structure

### llms.txt (Compact)

The compact version includes:

1. **Project summary** - Brief description of what Morphir is
2. **Docs section** - Links to key documentation with descriptions
3. **Specifications section** - Links to IR specs and JSON schemas
4. **Optional section** - Additional resources like ADRs and community guides

### llms-full.txt (Full)

The full version includes everything in the compact version plus:

- **Inline content** from key documents (README, IR Specification, etc.)
- **Complete documentation index** organized by section
- **Full descriptions** without truncation

## Best Practices for LLM Queries

When using Morphir's llms.txt with an LLM:

1. **Start with the compact version** - It's usually sufficient for most queries
2. **Use the full version for deep dives** - When you need comprehensive information
3. **Be specific in your questions** - Reference specific sections or concepts
4. **Verify generated code** - Always test LLM-generated Morphir code

## Example Queries

Here are some effective ways to query Morphir documentation via LLMs:

### Getting Started
```
Using the Morphir documentation, explain how to install and set up Morphir for an Elm project.
```

### Understanding Concepts
```
Based on the Morphir IR specification, explain how types are represented in the intermediate representation.
```

### Technical Implementation
```
Using the Morphir JSON schemas, show me how to validate a morphir-ir.json file with Python.
```

### Backend Development
```
What backends does Morphir support and how do I generate Scala code from my Morphir model?
```

## Contributing

The llms.txt files are automatically generated from the documentation source. If you'd like to improve them:

1. **Improve source documentation** - Better source docs = better llms.txt
2. **Suggest priority changes** - Open an issue if important docs are missing
3. **Report issues** - Let us know if the llms.txt content causes LLM confusion

## Related Resources

- [llms.txt Specification](https://llmstxt.org/) - The official specification
- [Morphir Documentation](/) - Full documentation site
- [JSON Schemas](/docs/spec/ir/schemas/) - Formal IR specifications
