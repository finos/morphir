---
sidebar_position: 3
sidebar_label: Core Concepts
---

# Core Concepts

This section explains the fundamental concepts behind Morphir and how it works.

## 📋 Contents

### Overview & Philosophy
- **[Introduction to Morphir](introduction-to-morphir.md)** - Complete introduction to the Morphir framework
- **[What's It About?](whats-it-about.md)** - Understanding business logic as the core focus
- **[Why Functional Programming?](why-functional-programming.md)** - The role of FP in Morphir

### Technical Architecture
- **[Morphir IR](morphir-ir.md)** - The Intermediate Representation structure (Distribution → Package → Module → Types/Values)
- **[Morphir SDK](morphir-sdk.md)** - Standard library and built-in functions

## 🔑 Key Concepts

### The Morphir IR Hierarchy

The Morphir Intermediate Representation follows a hierarchical structure (as documented in PR #378):

```
Distribution (Complete package with dependencies)
    ↓
Package (Versioned set of modules)
    ↓
Module (Container for types and values)
    ↓
Types & Values (Domain model and business logic)
```

**Important Distinctions:**
- **Specifications** contain only public interfaces (no implementation) - used for dependencies
- **Definitions** contain complete implementations including private items

### Naming System

Morphir uses a naming-agnostic approach where names are stored as lists of lowercase words, independent of any specific naming convention:

- **Name**: `["value", "in", "u", "s", "d"]`
- **Path**: List of Names (hierarchical location)
- **QName** (Qualified Name): Module path + local name
- **FQName** (Fully-Qualified Name): Package path + module path + local name

This allows the same IR to be rendered in different conventions (camelCase, snake_case, etc.) for different platforms.

## 🎯 Why These Concepts Matter

Understanding these concepts is crucial because:

1. **Portability**: The IR allows business logic to be translated to any target language
2. **Type Safety**: Complete type information is preserved throughout
3. **Clarity**: Naming-agnostic representation works across platforms
4. **Separation of Concerns**: Business logic is separate from implementation details

## 📚 Learn More

After understanding these core concepts, you can:

- Apply them in [User Guides](../user-guides/) to model business logic
- See technical details in [Reference](../reference/) documentation
- Explore [Use Cases](../use-cases/) for real-world applications

---

[← Back to Documentation Home](../README.md)
