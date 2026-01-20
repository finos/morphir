---
title: "Attributes"
description: "Specification for Attributes in Morphir IR v4"
---

# Attributes

In version 4, attributes are explicit structures attached to Type and Value nodes, rather than generic parameters.

## TypeAttributes

Attached to every `Type` node.

Structure:
```json
{
  "source": { "startLine": 1, "startColumn": 1, "endLine": 1, "endColumn": 10 },
  "constraints": { ... },
  "extensions": { ... }
}
```

- **source**: Optional `SourceLocation`
- **constraints**: Optional `TypeConstraints`
- **extensions**: Dictionary mapping `FQName` keys to arbitrary extension values

## ValueAttributes

Attached to every `Value` node.

Structure:
```json
{
  "source": { ... },
  "inferredType": { ... },
  "extensions": { ... }
}
```

- **source**: Optional `SourceLocation`
- **inferredType**: Optional `Type` expression representing the inferred type of the value
- **extensions**: Dictionary mapping `FQName` keys to arbitrary extension values
