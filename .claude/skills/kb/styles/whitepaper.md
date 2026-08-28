# Register: white-paper

For content that argues a position: Decision Records, design notes, synthesis and guidance concepts that rank
alternatives. The reader is a skeptical peer deciding whether to trust the conclusion. Apply
[voice.md](./voice.md) throughout.

## Shape

1. **Conclusion first.** The position, in the first paragraph, in plain words. Not "this document explores".
2. **Context.** The problem and the constraints that make it hard. Only the constraints that bear on the
   decision; background for its own sake dilutes the argument.
3. **Argument.** Claims in order, each with its evidence next to it: a citation, a measurement, a worked
   example, or a named assumption. An unsupported claim is marked as an assumption, visibly.
4. **Alternatives.** What was rejected and the specific reason. "Considered and rejected because X" is the most
   load-bearing sentence in the register; a paper with no rejected alternatives has not argued.
5. **Unresolved.** What this position does not settle, and what would change the conclusion. This section is
   mandatory; an argument that admits no revisit condition overclaims.

## Tone

- Third person or first plural. No direct address.
- No contractions.
- Every "because" earns its clause. Trade-off tables are welcome where alternatives repeat the same fields.
- Confidence must be graded: state what is proven, what is judged likely, and what is assumed, as three
  different things.

## Limits

- Architecture, dependency, and flow claims deserve a diagram beside the argument; see
  [diagrams.md](./diagrams.md). Mark diagrams of proposed designs as proposed, exactly like prose claims.
- Prose that instructs the reader step by step belongs in the [article](./article.md) register.
- Raw lookup material (signatures, tables of variants) belongs in the [reference](./reference.md) register;
  cite it rather than inlining it.
- Decision Records additionally follow their register schema in kb/AGENTS.md: past tense, immutable,
  superseded rather than edited.
