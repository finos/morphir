# Composing Expressions

Each file in this directory documents a [type](../concepts/datatype.md) or
[type class](../concepts/type-class.md) together with the
[operations](../concepts/operation.md) it provides. An operation in
isolation is a single node; real specifications compose operations into
larger **expression trees** whose leaves are literals or variables
and whose internal nodes are operation applications.

This document defines two surface forms for writing such expression
trees in markdown:

- the [Nested List Form](#nested-list-form), which is the canonical
  shape and works for every operation regardless of arity, and
- the [Infix Form](#infix-form), an abbreviated shape available only
  for binary operations.

Both forms denote the same expression tree. A specification may mix
them freely — for example, using the nested list form at the outer
level while writing a binary sub-expression inline.

## Literals

A *literal* is a leaf of an expression tree that denotes a constant
value of some type — a particular number, Boolean, date, string, …
Like operation references, literals are written explicitly as markdown
links so that every leaf carries an unambiguous type. The link text is
the value as it would be written on paper; the link target is the
anchor of the **Literals** section in the file that defines the
literal's type.

For example, to write the number *one thousand five hundred* as a leaf
of an expression, link the text `1500` to the [number literal
section](number.md#literals):

```markdown
[1500][num]

[num]: number.md#literals
```

As with operation references, snippets are easier to read when each
literal target is given a short [reference-style alias][refs] at the
bottom of the document. The aliases conventionally used are `num` for
[Number literals](number.md#literals), `bool` for [Boolean
literals](boolean.md#literals), `date` for [Date
literals](date.md#literals), and `str` for [String
literals](string.md#literals). The condition `amount > 1500` from the
[infix form](#infix-examples) example then reads:

```markdown
[amount][var] [>][gt] [1500][num]

[gt]: ordering-relation.md#greater-than-derived-operation
[num]: number.md#literals
[var]: #variables
```

## Variables

A *variable* is a leaf of an expression tree that refers to a named
value bound elsewhere — a parameter, a field, a local binding, an
iteration variable, … Like literals and operation references,
variables are written explicitly as markdown links so that every leaf
of an expression carries an unambiguous role. The link text is the
variable's name as it would appear in prose; the link target is the
anchor of this **Variables** section.

For example, to refer to a variable named `amount` as a leaf of an
expression, link the text `amount` to this section:

```markdown
[amount][var]

[var]: #variables
```

As with literals and operations, snippets are easier to read when the
link target is given a short [reference-style alias][refs] at the
bottom of the document. The conventional alias is `var`, pointing at
this section. Authors are encouraged to use this shorthand in their
examples. The sum `a + b` then reads:

```markdown
[a][var] [+][add] [b][var]

[add]: number.md#addition-operation
[var]: #variables
```

Because every variable shares the same link target, the `var` alias
is defined once per document regardless of how many variables appear
in it.

## Operation References

In both forms an operation is identified by a markdown link whose target
is the anchor of that operation's heading in its defining file. The link
text is free: authors may choose whatever reads best at the call site
(`+`, `add`, `plus`, `Addition`, …); recognition is based on the link
target, not the visible text. This mirrors the convention already used
by the [Decision Tree](decision-tree.md) expression for its `if` / `then`
/ `else` keywords.

For example, [Addition][add] on [Number](number.md), [AND][and] on
[Boolean](boolean.md), and [Integer Division][idiv] on
[Integer](integer.md) are all referenced by linking to the anchor of
their respective `### Operation` heading.

Authors are encouraged to keep example snippets readable by using
[reference-style link definitions][refs] with short aliases for each
operator — `add`, `sub`, `mul`, `div`, `mod`, `neg`, `abs`, `and`,
`or`, `not`, `xor`, `eq`, `neq`, `lt`, `lte`, `gt`, `gte`, … — and
collecting the definitions at the bottom of the enclosing document.
The snippets below follow this convention: each example uses the
short alias inline and lists its link definitions at the end of the
snippet, so the snippet is self-contained.

## Nested List Form

An expression tree is written as a markdown list. Each list item carries
one node of the tree:

- The item's inline payload is a link to the operation that node
  applies.
- The item's nested children — in document order — are that operation's
  arguments. Each child is itself either another list item denoting a
  sub-expression, or a leaf payload (literal, named reference, …).

This list structure mirrors the expression tree exactly: the depth of a
list item equals the depth of its node in the tree, and sibling items at
the same level are sibling arguments of the same parent operation.

### Basic Form

A unary operation has one nested child; a binary operation has two; an
*n*-ary operation has *n*. Leaves appear as ordinary list items
without nested children.

### Examples

The arithmetic expression `(a + b) * c` written in nested list form,
using [Addition][add] and [Multiplication][mul]:

```markdown
- [×][mul]
  - [+][add]
    - [a][var]
    - [b][var]
  - [c][var]

[add]: number.md#addition-operation
[mul]: number.md#multiplication-operation
[var]: #variables
```

The Boolean expression `not (x and y)` using [NOT][not] and [AND][and]:

```markdown
- [not][not]
  - [and][and]
    - [x][var]
    - [y][var]

[and]: boolean.md#and-operation
[not]: boolean.md#not-operation
[var]: #variables
```

Leaves may themselves be any kind of payload — a literal, a named
reference, a [Decision Tree](decision-tree.md), or any other expression
form — and need not be list items if no further nesting is required.

## Infix Form

For binary operations, the nested list form may be abbreviated to a
single inline expression of the shape:

```markdown
<left expression> <operator link> <right expression>
```

The pattern recognized is: an expression, followed by a markdown link
whose target is the anchor of a binary operation, followed by another
expression — all on the same line, within a single list item or
paragraph. The link target identifies the operation; the link text is
free.

### Infix Examples

The condition `amount > 1000` using [greater-than][gt] on a numeric
type:

```markdown
[amount][var] [>][gt] [1000][num]

[gt]: ordering-relation.md#greater-than-derived-operation
[num]: number.md#literals
[var]: #variables
```

A simple sum `a + b` using [Addition][add]:

```markdown
[a][var] [+][add] [b][var]

[add]: number.md#addition-operation
[var]: #variables
```

### Grouping and Associativity

The infix form has no notion of operator precedence or parentheses.
When more than one binary operator appears on the same line, the
expression's associativity is therefore ambiguous and the snippet is
ill-formed. To express grouping explicitly, fall back to the
[Nested List Form](#nested-list-form): the list hierarchy directly
encodes which operator applies first.

For example, `(a + b) * c` cannot be written purely infix. Instead
either use the fully nested form shown [above](#examples), or mix the
two forms — keeping the outer multiplication as a list and writing the
inner addition inline:

```markdown
- [×][mul]
  - [a][var] [+][add] [b][var]
  - [c][var]

[add]: number.md#addition-operation
[mul]: number.md#multiplication-operation
[var]: #variables
```

### Mixing Forms

Infix sub-expressions may appear inside the nested list form wherever
an argument is expected, as in the grouping example above. Conversely,
a nested list may appear in place of either operand of an infix
expression when the operand is too complex to read inline. The
[Decision Tree](decision-tree.md) examples already use this mixing:
each `if` carries an infix Boolean condition as its payload while the
surrounding tree is a nested list.

### Restriction to Binary Operations

The infix form applies only when the operation being referenced is
binary. Unary operations (e.g. [NOT][not], [Negation][neg],
[Absolute Value][abs]) and *n*-ary operations with arity other than
two must be written in the [Nested List Form](#nested-list-form).

[abs]: number.md#absolute-value-operation
[add]: number.md#addition-operation
[and]: boolean.md#and-operation
[gt]: ordering-relation.md#greater-than-derived-operation
[idiv]: integer.md#integer-division-required-operation
[mul]: number.md#multiplication-operation
[neg]: number.md#negation-operation
[not]: boolean.md#not-operation
[refs]: ../README.md#link-references
[var]: #variables
