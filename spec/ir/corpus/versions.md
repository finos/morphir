# Versions

## versions-0001: Reading a v3 literal into the model {node=Value version=3}

A v3 tagged array with capitalized tags decodes to the same value the v4 spelling does.

```json canonical
["Literal", {}, ["WholeNumberLiteral", 42]]
```

## versions-0002: Writing a Hole to v3 is refused {node=Value version=3 status=pending}

The CLI refuses a v4 to v3 downgrade with `unsupported_v4_downgrade`. The corpus grammar has no role for a write refusal yet; plan 2 adds one, and bead morphir-diwy specifies the rules. Until then this case is prose only.
