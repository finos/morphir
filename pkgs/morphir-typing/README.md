# Morphir Typing

`finos/morphir-typing` infers and checks the types of Morphir IR. It does not depend on a source language, and it
depends only on `finos/morphir-ir`. Any producer can use it: a frontend that does not know its types writes the
unknown marker, and this module fills in the types. A backend that needs types, such as the MoonBit generator, can
then use the IR.

The packages build and test on `wasm`, `wasm-gc`, `js` and `native`.

## The `infer` API

```moonbit
let filled = @typing.infer(file, deps, Fill) catch {
  InferenceFailed(problems) => ...
}
```

- `file` is an `@ir.IRFile`: a `Library`, an `Application` or a `Specs` distribution.
- `deps` maps each package name to its `@ir.PackageSpecification`. The file's own dependencies are added to it.
- `infer` raises `InferenceFailed(problems)` when there is any problem, in either mode. It collects the problems of
  every binding group first, and sorts them by logical path.

There are two modes:

| Mode | Result |
| --- | --- |
| `Fill` | The file with an `inferred_type` on every `Value` and `Pattern` of every body that inference walks. Each signature type that has a marked variable is replaced by its solution. |
| `Check` | The input file, unchanged. Use it to check the types that a file already has. |

In both modes, an existing `inferred_type` is a fact (below). In `Check`, an existing `inferred_type` that does
not agree with the solution is also `annotation_mismatch`. The existing types of one declaration are compared in its
`TypeScope` (below), so a node that has the wrong signature variable, or a variable without its class, is
`annotation_mismatch`.

### Facts

In `Fill` and `Check`, an existing `inferred_type` on a `Value` or `Pattern` node is a fact. Inference unifies it
with the type of the node before the binding group generalizes. The fact is converted by the hole rule (see "Other
bodies"): a variable in scope is that rigid variable, any other variable is a fresh variable, and a marked
variable stays flexible. So a partial fact such as `List a` is only a constraint, and the node gets the solution.
A fact that does not unify is `annotation_mismatch` at the node. In `Fill`, the fact is `expected` and the
inferred type is `found`; `Check` swaps them, as its comparison does. `Fill` does not overwrite an existing type
silently. Because `Check` uses facts too, the `Int` fact that the Scheme frontend writes on an integer literal
narrows the `number` variable of the literal, so `(define (inc x) (+ x 1))` checks.

A `Specs` file has no bodies. `Fill` returns it unchanged. `Check` checks that every type reference in its
signatures and type bodies resolves.

In a `Library` or an `Application`, every type reference must also resolve, in both modes. A reference into a
package that has no specification or definition is `missing_dependency`. A reference to a name that a known
package does not have is `unknown_reference`. The problem is at the logical path of the node that holds the
reference:

- a value signature: the declaration, `value:<package>:<module>#<name>`;
- a let signature: the definition, `…/definition` or `…/definitions/<name>`;
- the declared type of a hole: the hole;
- an alias body or a constructor argument: the type, `type:<package>:<module>#<name>`.

The packages that an `Application` bundles are dependencies, so inference trusts them. It checks the type
references of their public interface (public types and public value signatures, at the paths above with the
bundled package name), and a reference to a private type of the same package resolves. It does not infer bundled
bodies, and `Fill` writes no types into them.

Inference uses only the signature of an `IncompleteBody`. It does not infer the partial value, so the value's
nodes get no types and report no problems. Without an output type, callers see a fresh type.

`types_equivalent(a, b)` compares two IR types up to a bijective renaming of their variables. It ignores
attributes, and it treats `Tuple []` and `Unit` as the same type. It does not expand aliases. It compares one pair
of types alone.

`TypeScope::of_definition(def)` makes the scope of one declaration, and `scope.equivalent(a, b)` compares one of
its types. It is stricter than `types_equivalent`:

- one bijection holds for every type of the declaration, because inference names the variables of a declaration
  consistently;
- each signature variable of the declaration (one without the unknown marker) maps only to itself;
- two paired variables must have the same class set, from the `typeclass` constraint or the name prefix.

A comparison that fails does not change the scope. Like `types_equivalent`, it does not expand aliases.

### Native untagged unions

Explicit result and call boundaries accept Union members without conversion. Every source alternative must
be justified when narrowing. Generic signatures, aliases and contextual if/case/list/tuple/record/lambda checks
retain the complete type. Equality unification never tries Union arms against live metavariables. Unannotated
expressions do not synthesize unions. Unresolved disjunctive equations are unsupported; numeric literals need
concrete type evidence at a Union boundary.

`TypeContext::from(file, deps)` shares inference's visibility and alias environment. `assignable` and `equivalent`
return `Proven`, `Refuted` or `Unknown(reason)`. Scoped variable names are identities. Source positions and textual
`example/union:provenance#note` are descriptive; other constraints/extensions remain obligations. Known refined
sources may widen, but extra destination obligations need evidence. Alias-site and body obligations remain
separate. Nominal arguments are invariant; function inputs are contravariant. Proofs have 4096 pair and 128 depth
limits. Shape comparison ignores attributes and keeps consistent candidate bijections across the whole signature
and later TypeScope calls, with 4096 operation, 128 depth and 256 candidate limits. Exhaustion returns false.

`substitute_type` preserves authored alternatives and attributes, raising `AttributeConflict` when occurrence
and substituted attributes cannot share a node. Fill preserves valid facts and solved template attributes.

`compare_types(expected, actual, deps, mask_signatures?)` compares every node type and every signature type of
two files (`compare_files.mbt`). It expands the aliases of `deps`, of the file's own dependencies and of its own
package. It compares the types of each declaration in that declaration's `TypeScope`, made from `expected`. It
writes one line per difference, `<path>: expected <t1>, found <t2>`, where a path is a logical path or
`<path>:input/<i>` and `<path>:output` for a signature. A path that only one side has is a difference too.

A let-signature type of `expected` with a morphir-elm placeholder (`t-<digits>`, see
[Classic let placeholders](#classic-let-placeholders)) is compared only outside its placeholders: each placeholder
position is `()` on both sides, and a placeholder row compares only the fields that `expected` lists. So `List t8`
must still be a list. With `mask_signatures=true`, the placeholders of top-level signatures are masked in the same
way and are not fixed in the scope. morphir-elm `make` writes the top-level signature of an unannotated value from
a first inference pass, so the placeholders there are not declared types. The node types are compared everywhere.
The typing oracle (`pkgs/morphir-typing-tools/oracle`) and the Elm parity harness
(`pkgs/morphir-elm/conformance`) use it.

### The caller supplies the SDK

This module has no built-in SDK, because it depends only on `finos/morphir-ir`. Add the SDK specification to
`deps`:

```moonbit
let deps = Map::from_array([
  (@sdk_spec.sdk_package_name(), @sdk_spec.sdk_specification()),
])
```

`@sdk_spec` is the module `finos/morphir-sdk-spec`. Without it, every reference to `morphir/SDK` is
`missing_dependency`.

## The unknown marker

A type variable is *unknown* when its attributes hold `extensions["morphir.inference"] = Data::Text("unknown")`.
`@typing.unknown_type(name)` makes such a variable. Inference may solve an unknown variable to any type.

- All occurrences of one unknown name in one signature are the same variable.
- A top-level value is *declared* when it has an output type and no signature variable is unknown. Other
  values are *undeclared*.
- Classic IR has no markers, so inference checks it strictly.

## Rigid variables

Every type variable in a signature that is not unknown is *rigid*, as in an Elm annotation.

- A rigid variable stands for any type. The body must work for every type.
- When the body needs a narrower type, the problem is `rigid_variable`. For example, `id : a -> a` with the body
  `\x -> 1` fails, because `1` is a number and `a` is any type.
- A class failure at a rigid variable is also `rigid_variable`, not `no_instance`. For example, a body that needs
  `comparable` for a rigid `a` fails with `rigid_variable`. This includes a rigid inside a type, as in
  `List a` used as `comparable`.
- A rigid variable takes its class from its `typeclass` constraint, else from its name prefix.
- The rigid variables of a signature belong to its declaration. Two declarations that both write `a` have two
  different variables, also inside one binding group. When the group is generalized, the scheme of an undeclared
  member quantifies the rigid variables of every member, so `f x = g x` is as general as `g`. A let annotation that writes a variable of its
  declaration's signature means that variable. Output and messages show the plain name, such as `a`.
- The other rigid variables of a let annotation belong to that let. If one escapes into the type of an outer
  value, the problem is `rigid_variable`. Two `LetRecursion` siblings that both write `a` have two different
  variables.
- A declared value is used through its scheme everywhere, also in its own body. So it can be polymorphically
  recursive.

### Classic let placeholders

Classic IR from morphir-elm writes a signature for every let definition. When the Elm source has no annotation
for a let, that signature holds the variables that the frontend made before inference: `t` and digits, as in
`t8` (canonical `t-8`). The solved types are only on the nodes.

Inference reads every unmarked signature variable as rigid, so it reads these placeholders as rigid too. A body
that needs a narrower type then fails with `rigid_variable`. For example, `let discount = price * 0.1` with the
output `t8` fails, because the body needs `Float`.

These variables must have the unknown marker before `Fill` or `Check`. Migration from classic IR
(`@migration.to_current`) marks each `t-<digits>` variable of a let signature, and it leaves top-level signatures
as they are.

## How inference works

Inference is constraint-based Hindley-Milner, in the manner of morphir-elm's `Morphir.Type.Infer`. It uses meta
variables, a union-find substitution, levels for generalization and an occurs check.

1. The environment holds the types, constructors and values of every dependency, and the types and constructors
   of the file.
2. Each declared signature enters the environment as a scheme before any body is solved.
3. The undeclared values form binding groups: the strongly connected components of the references between them.
   The groups are solved in dependency order. Inside a group, the undeclared values are monomorphic. They are
   generalized after the group.
4. Each group stops at its first problem. Other groups go on. A value of a failed group gets an unconstrained
   scheme, so its dependants do not report the same problem again.
5. `LetDefinition` generalizes, which is let-polymorphism. `LetRecursion` is one group: a sibling with a complete
   annotation is used through the scheme of its annotation in the whole group, and the other siblings are
   monomorphic until the group is generalized. `Destructure` binds its variables monomorphically.

### Literals

| Literal | Type |
| --- | --- |
| Integer | A fresh `number` variable |
| Float | `Float` |
| Decimal | `decimal#decimal` |
| String | `String` |
| Char | `Char` |
| Bool | `Bool` |
| Document | `morphir/SDK:document#document` when that type is known, otherwise `unsupported` |

### Other bodies

- A `NativeBody` or an `IncompleteBody` uses its signature as declared. Inference does not walk an incomplete
  body's value.
- An `ExternalBody` checks its fallback value against the signature.
- A `Hole` is a todo: it stands for code that is not written yet and does not fail the run by itself. A
  variable of its declared type that is in scope (a signature or let-annotation variable) is that rigid
  variable. Any other variable is a fresh variable for each occurrence of the hole, and keeps the class of its
  `typeclass` constraint or name prefix. A hole without a declared type is a fresh variable.

### Output

- Inference expands an alias only when unification needs it. So a type keeps the alias references that it got
  from a signature or a constructor.
- Variables are named in walk order: `a`, `b`, …. A constrained variable takes its class as a prefix:
  `comparable-a`. Names of rigid variables are reserved first, so a new name never captures one.
- The output is deterministic: the same input gives the same bytes.

## Constraint classes

The four classes of Elm apply to type variables. A variable's class comes from its `typeclass` constraint, else
from its name prefix (`number`, `comparable`, `appendable`, `compappend`). Classes propagate through unification.

| Class | Satisfied by |
| --- | --- |
| `number` | `Int`, `Float` |
| `comparable` | `Int`, `Float`, `Char`, `String`, `List c`, tuples of 2 or 3 comparables |
| `appendable` | `String`, `List a` |
| `compappend` | `String`, `List c` |

- `comparable` and `appendable` together give `compappend`.
- `number` and `comparable` together give `number`.
- Any other pair is `no_instance`.
- `Decimal` and `LocalDate` belong to no class.
- A `typeclass` constraint that names any other class is `unsupported`, with the message "inference does not
  support the type class `<name>`". The problem is at the declaration's root for a top-level signature, at
  `/definition` (or `/definitions/<name>`) for a let signature, at the hole for a hole's type, and at the node
  that uses a global value or constructor whose signature has such a class. Inference never treats it as a class.

## Records and rows

`Record` and `ExtensibleRecord` unify through row variables.

| Value | Type rule |
| --- | --- |
| `Field(v, f)` | `v : { r \| f : t }`, and the result is `t` |
| `FieldFunction f` | `{ r \| f : t } -> t` |
| `UpdateRecord` | The result has its target's type. Each field that it sets must exist with the new value's type. |
| Record literal | Closed: it has exactly its fields |

A closed record that lacks a field gives `missing_field`.

Aliases expand during unification. Opaque types and custom types are nominal. A constructor has the type
`args -> T params`. An alias of a closed record is a constructor too, as in Elm and in morphir-elm: with
`type alias Point = { x : Int, y : Int }`, the constructor `Point` has the type `Int -> Int -> Point`. It takes
the fields in declaration order and gives the alias type.

## Diagnostics

Each problem is an `InferenceProblem { code, node, message, expected, found, source }`. `node` is a logical path.
`expected` and `found` are IR types when the problem has two types. `source` is the node's source location, if the
IR has one. Messages are short sentences with types in Elm notation.

| Code | Meaning | Example message |
| --- | --- | --- |
| `type_mismatch` | Two types do not unify | expected Int, found String |
| `occurs` | The type would be infinite | the type would be infinite: a occurs in List a |
| `rigid_variable` | A body narrows an annotated variable | the variable `a` is annotated as any type, but the body needs number |
| `no_instance` | No type satisfies the constraint class | the type String is not a number |
| `missing_field` | The record has no such field | the record has no field `count` |
| `unknown_reference` | The name is not defined, but its package is known | `x` is not defined |
| `missing_dependency` | No specification for the package of the name | there is no specification for the package of `x` |
| `arity` | A non-function is applied, or a constructor pattern has the wrong number of arguments | the type Int is not a function, so it cannot take an argument |
| `annotation_mismatch` | An existing `inferred_type` disagrees with inference | the node has the type Int, but inference gives String |
| `unsupported` | A construct that inference does not handle | inference does not support `x` |

### Aliases that ignore a parameter

An alias can ignore a parameter, as `type alias Token a = Int`. Then `Token String` and `Token Bool` are both
`Int`, as in Elm. So when both sides of a unification name the same alias, inference expands both sides and does
not compare the arguments. Only a nominal type compares its arguments.

The occurs check looks through such an alias: `a ~ Token a` binds `a` to `Int`. When a variable occurs in a type,
inference expands every alias of the type, and the check fails only when the variable occurs in the expansion.

### Cyclic aliases

An alias that refers to itself, directly or through other aliases, is `unsupported`. Examples are `A = A`,
`A = B` with `B = A`, and the growing `T a = T (List a)`. Inference cannot expand such an alias.

- The problem is at the type path `type:<package>:<module>#<name>`, in both modes.
- This includes cyclic aliases in dependencies. A file then fails even when it does not use the alias.

## Logical paths

A logical path names one `Value` or `Pattern` node. It does not depend on the JSON encoding.

- A declaration's root is `value:<package>:<module>#<name>`, with canonical names, for example
  `value:acme/app:orders#total`.
- Each step below adds `/<step>` to the path of the parent. `<i>` is a 0-based index and `<name>` is a canonical
  name.

| Child | Steps |
| --- | --- |
| A declaration's body | `/body` |
| `Apply` | `/function`, `/argument` |
| `Lambda` | `/pattern`, `/body` |
| `LetDefinition` | `/definition/body`, `/in` |
| `LetRecursion` | `/definitions/<name>/body`, `/in` |
| `Destructure` | `/pattern`, `/value`, `/in` |
| `IfThenElse` | `/condition`, `/then`, `/else` |
| `PatternMatch` | `/subject`, `/cases/<i>/pattern`, `/cases/<i>/body` |
| `Tuple`, `List` | `/items/<i>` |
| `Record` | `/fields/<name>` |
| `Field` | `/record` |
| `UpdateRecord` | `/record`, `/fields/<name>` |
| `AsPattern` | `/pattern` |
| `TuplePattern` | `/items/<i>` |
| `ConstructorPattern` | `/args/<i>` |
| `HeadTailPattern` | `/head`, `/tail` |

For example, `value:acme/app:orders#total/body/argument` is the argument of the `Apply` that is the body of
`total`. The grammar is defined in `paths.mbt`. A later plan moves it to `finos/morphir-ir/identities`.

## Out of scope

- Type classes other than the four built-in classes.
- Inference across a package whose specification is missing. That is `missing_dependency`.
- Expansion of cyclic aliases. They are `unsupported`.
- Document literals when no `morphir/SDK:document#document` type is known. The SDK specification has no such
  type today, so they are `unsupported`.
- Source languages. This module reads only IR. The engine stage, which runs inference inside the Morphir
  pipeline, comes in a later plan.
