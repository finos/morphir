# Design Agent Guidelines

Working agreement for AI agents and contributors working on Morphir v4 IR design documents.

## Code Example Requirements

All design documents that include code examples **must** provide examples in:

1. **Gleam** — Primary implementation language for Morphir toolchain
2. **Scala 3** — Functional programming community and existing Morphir Scala users
3. **Rust** — Systems programming, Wasm backend implementation candidate
4. **Type-annotated Python** — For Python SDK and accessibility
5. **Java 21+** — Using modern Java features (records, sealed classes, pattern matching)

### Rationale

- Gleam is our implementation language; examples must be directly usable
- Scala reaches the functional programming community and has strong type system features
- Rust is a candidate for Wasm backend implementation and systems-level tooling
- Python reaches the data science and ML communities
- Java reaches enterprise developers and demonstrates modern typed Java

### Example Format

For `.mdx` files (Docusaurus), use the native `Tabs` component for multi-language examples.

**Structure:**

1. Import the Tabs components at the top of the file:
   - `import Tabs from '@theme/Tabs';`
   - `import TabItem from '@theme/TabItem';`

2. Wrap code examples in `<Tabs groupId="language">` with `<TabItem>` for each language:
   - `value="gleam" label="Gleam" default` for Gleam (set as default)
   - `value="scala" label="Scala 3"` for Scala
   - `value="rust" label="Rust"` for Rust
   - `value="python" label="Python"` for Python
   - `value="java" label="Java 21+"` for Java

See the existing `.mdx` files in this directory for working examples of this pattern.

For plain `.md` files (non-Docusaurus), use sequential fenced code blocks:

```gleam
// Gleam - Primary implementation
pub type NumericConstraint {
  Arbitrary
  Signed(bits: IntWidth)
  Unsigned(bits: IntWidth)
}
```

```scala
// Scala 3 - Enums and case classes
enum NumericConstraint:
  case Arbitrary
  case Signed(bits: IntWidth)
  case Unsigned(bits: IntWidth)
```

```rust
// Rust - Enums with struct variants
pub enum NumericConstraint {
    Arbitrary,
    Signed { bits: IntWidth },
    Unsigned { bits: IntWidth },
}
```

```python
# Python - Type-annotated
from dataclasses import dataclass
from typing import Literal

IntWidth = Literal[8, 16, 32, 64]

@dataclass(frozen=True)
class Signed:
    bits: IntWidth

@dataclass(frozen=True)
class Unsigned:
    bits: IntWidth

NumericConstraint = None | Signed | Unsigned  # None = Arbitrary
```

```java
// Java 21+ - Records and sealed types
public sealed interface NumericConstraint {
    record Arbitrary() implements NumericConstraint {}
    record Signed(int bits) implements NumericConstraint {}
    record Unsigned(int bits) implements NumericConstraint {}
}
```

## Design Principles

### IR Semantic Embedding

> **Key Principle**: If a concept affects the meaning of a program (codegen, runtime behavior, type compatibility), it belongs in the IR itself, not in sidecar files.

This applies to:
- Type constraints (bounds, signedness, encoding)
- ABI metadata for boundary functions
- Representation hints for code generation

Sidecar files are appropriate for:
- Documentation and descriptions
- Linting configuration
- IDE-specific hints
- User-defined decorators that don't affect semantics

### Progressive Disclosure

Design documents should:
1. Start with the simplest useful case
2. Build complexity incrementally
3. Provide "confidence checks" before advancing to complex topics

### Constraint vs. Decorator Distinction

| Aspect | Constraints | Decorators |
|--------|-------------|------------|
| **Audience** | Extension authors, tooling | End users |
| **Location** | IR attributes | Sidecar or IR extensions |
| **Affects semantics** | Yes | No (advisory only) |
| **Examples** | `Bounded { min: 0, max: 100 }` | `@deprecated("use X instead")` |

## Document Structure

Each design document should include:

1. **Frontmatter** with status tracking (optional for non-docusaurus files)
2. **Overview** — What problem this solves
3. **Design** — The proposed solution with code examples in all three languages
4. **Examples** — Concrete usage scenarios
5. **Migration** — How existing code/IR adapts
6. **Open Questions** — Unresolved design decisions

## Version Control

- Design documents live in `docs/design/draft/` until approved
- Link to beads issues for tracking
- Reference GitHub issues and discussions where applicable
