# Versions

## versions-0001: Reading a v3 literal into the model {node=Value version=3}

A v3 tagged array with capitalized tags decodes to the same value the v4 spelling does.

```json canonical
["Literal", {}, ["WholeNumberLiteral", 42]]
```

## versions-0002: Writing a Hole to v3 is refused {node=Value status=pending}

The CLI refuses v4 to v3 downgrade with `unsupported_v4_downgrade`. Bead morphir-diwy specifies the rules; until then this case records the refusal.

```json rejected diagnostic=unsupported_v4_downgrade
{ "Hole": { "reason": { "UnresolvedReference": { "target": "my-org/project:module#deleted" } } } }
```
