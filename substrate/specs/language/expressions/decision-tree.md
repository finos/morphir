# Decision Tree [Expression](../concepts/operation.md)

## Summary

A Decision Tree is a conditional expression: a generalization of the
familiar **if / then / else** construct. It selects between alternative
result values based on Boolean conditions and supports arbitrary
`else if` cascades expressed as a flat sequence of `if` clauses
terminated by a single `else`. A decision tree is written as a nested
markdown list whose keywords — `if`, `then`, `else` — are markdown
links to the anchors of this specification. Each keyword is followed,
on the same list item, by its expression payload.

A decision tree may appear anywhere an expression of its result type is
expected.

## Structure

A decision tree is written as a markdown list in which structural
keywords are identified by markdown links to the anchors defined on
this page:

- [`if`](#if) — opens a clause and is followed by the Boolean condition.
- [`then`](#then) — follows an `if` and is followed by the value to
  return when that `if`'s condition holds.
- [`else`](#else) — closes the tree and is followed by the value to
  return when no `if` matched.

Keyword recognition is based on the link target, not on the link text.
Authors may phrase the visible text however reads best at the call site
— for example, an `else` clause may be written as `[else]` or as
`[otherwise]` provided the link still points to the [`else`](#else)
anchor. The same flexibility applies to `if` and `then`: any visible
text is permitted as long as the link target identifies the intended
keyword.

For brevity, the remainder of this document writes the keywords as
plain words; in concrete usage each keyword is a link to this page's
corresponding anchor.

### Basic Form

The simplest decision tree has a single `if` clause with one `then` and
one `else`. The `if` item appears at the top level of the list. The
`then` item is nested as the first child of the `if`; the `else` item
appears at the top level, after the `if`:

```markdown
- if <condition>
  - then <value when condition is true>
- else <value when condition is false>
```

### Else-If Chain

A multi-way decision is expressed as a flat sequence of sibling `if`
items at the top level of the list. Each `if` carries its own nested
`then`. A single `else` at the top level closes the chain and supplies
the value when no preceding condition matched:

```markdown
- if <condition 1>
  - then <value 1>
- if <condition 2>
  - then <value 2>
- if <condition 3>
  - then <value 3>
- else <default value>
```

The flat shape — sibling `if` items rather than nested ones — is the
structural signal that the construct expresses an `else if` cascade.
There is no distinct `else if` keyword and no nesting of one decision
tree inside another `else` is required to chain conditions.

### If

The `if` item carries the Boolean condition as its inline payload. It
must contain exactly one nested child — either a `then` item (the
common case) or another `if` item that opens a [nested decision
tree](#nested-decision-trees) in the `then` position. Every `if` at
the outermost level of a decision tree appears as a sibling at the
same top-level position in the list.

The condition must evaluate to a [Boolean](boolean.md).

### Then

The `then` item carries, as its inline payload, the value expression to
return when its parent `if`'s condition evaluates to `true`. It appears
as the (only) nested child of its `if`.

### Else

The `else` item carries, as its inline payload, the value expression to
return when no preceding `if` matched. It appears as the final sibling
at the top level of the list, after every `if` item.

The `else` is mandatory: a decision tree is a total expression and must
produce a value when every condition is false.

Authors who prefer the phrasing **`otherwise`** may write the link text
as `otherwise` (or any other suitable word) while keeping the link
target pointing to this section. Both spellings denote the same
construct.

### Result Type

The result type of a decision tree is the common type of every `then`
payload and the `else` payload. All branches must produce values of
the same type; otherwise the decision tree is ill-typed.

## Nested Decision Trees

A decision tree may itself be the value returned by a `then` branch.
The `else` branch case requires no special syntax — the entire flat
[`else if` chain](#else-if-chain) form is already an `else`-position
nesting, expressed as sibling `if` items at the same level. This
section concerns only the `then`-position case, which has a dedicated
abbreviated form.

### Rule

When a decision tree appears as the value of a `then` branch, the
`then` keyword is **omitted**. The inner `if` appears directly as the
nested child of the outer `if`, in the structural slot otherwise
occupied by a `then` item:

```markdown
- if <outer condition>
  - if <inner condition>
    - then <value when both conditions are true>
  - else <value when outer is true and inner is false>
- else <value when outer condition is false>
```

The presence of an `if` item — rather than a `then` item — as the
nested child of an outer `if` is the structural signal that the outer
`then` value is itself a decision tree. No `then` keyword is written
between the two `if` items.

The `else` keyword may **not** be skipped in this case. The inner
decision tree's `else` (or `otherwise`) clause must always be written
explicitly as a sibling of the inner `if`, regardless of whether the
nesting occurs in a `then` position or an `else` position.

This abbreviation applies only to the `then`-position nesting. It is
not available in the `else` position because the flat sibling-`if`
form already handles that case without nesting.

### Example

Expressing
`if isMember then (if amount > 1000 then "discount-tier-2" else "discount-tier-1") else "no-discount"`:

```markdown
- [if](decision-tree.md#if) `isMember`
  - [if](decision-tree.md#if) `amount` > `1000`
    - [then](decision-tree.md#then) `"discount-tier-2"`
  - [else](decision-tree.md#else) `"discount-tier-1"`
- [else](decision-tree.md#else) `"no-discount"`
```

Note that no `then` keyword appears between the outer `if isMember`
and the inner `if amount > 1000`. The inner tree's `else` clause,
however, is written explicitly.

## Evaluation

Given values for every referenced name, the top-level items of the
list are considered in document order:

1. For each `if` item, in order, evaluate its condition.
2. On the first `if` whose condition is `true`, evaluate that `if`'s
   nested `then` payload and return its value as the value of the
   decision tree.
3. If no `if` matched, evaluate the `else` payload and return its
   value as the value of the decision tree.

Only the selected branch is evaluated. Conditions of `if` items after
the first matching one are not evaluated, and the payloads of
non-selected `then` and `else` items are not evaluated.

## [Test cases][tc]

A single-clause decision tree:

| Condition | Then | Else | Result |
| --------- | ---- | ---- | ------ |
| `true`    | `1`  | `2`  | `1`    |
| `false`   | `1`  | `2`  | `2`    |

A two-clause chain equivalent to
`if a then 1 else if b then 2 else 3`:

| `a`     | `b`     | Result |
| ------- | ------- | ------ |
| `true`  | `true`  | `1`    |
| `true`  | `false` | `1`    |
| `false` | `true`  | `2`    |
| `false` | `false` | `3`    |

## Relationship to Decision Table

A [Decision Table](../concepts/decision-table.md) is the tabular
counterpart to a decision tree. A decision tree with `N` `if` clauses
and one `else` is semantically equivalent to a decision table with
`N + 1` rules where each rule's condition columns encode one clause of
the tree. Authors choose the form that best communicates intent: a
decision tree for one-off branching logic embedded inside a larger
expression; a decision table when the same conditions determine
multiple related outputs and the rules form an authoritative table.

## Example

A simple two-way branch:

```markdown
- [if](decision-tree.md#if) `amount` > `0`
  - [then](decision-tree.md#then) `"credit"`
- [else](decision-tree.md#else) `"debit"`
```

A three-way chain expressing
`if score >= 90 then "A" else if score >= 80 then "B" else "C"`:

```markdown
- [if](decision-tree.md#if) `score` >= `90`
  - [then](decision-tree.md#then) `"A"`
- [if](decision-tree.md#if) `score` >= `80`
  - [then](decision-tree.md#then) `"B"`
- [otherwise](decision-tree.md#else) `"C"`
```

Note that the third top-level item is written as `[otherwise]` but
links to the [`else`](#else) anchor; it is therefore recognized as the
closing `else` of the decision tree.

[tc]: ../concepts/test-case.md
