# Morphir IR → Substrate Mapping

This document catalogues every feature of the Morphir IR and shows the
corresponding Elm syntax that each feature represents. It serves as the
authoritative reference for `substrate migrate from morphir` and
`substrate migrate to morphir`.

The Morphir IR is defined in the `Morphir.IR.*` Elm modules. The entry point
is `Morphir.IR.Distribution`, which is what `morphir-elm make` produces as
JSON.

---

## Naming

### `Name`

`Name` is a list of lowercase words. It is the building block for all
identifiers in the IR. Tools render it in different conventions depending on
context.

```elm
type alias Name =
    List String

-- "valueInUSD" → [ "value", "in", "u", "s", "d" ]
-- "MyRecord"   → [ "my", "record" ]
```

### `Path`

A `Path` is a list of `Name`s used to identify packages and modules.

```elm
type alias Path =
    List Name

-- "Morphir.Finance.LCR" → [ ["morphir"], ["finance"], ["l","c","r"] ]
```

### `FQName` (Fully-Qualified Name)

A three-part tuple uniquely identifying any type or value across all packages.

```elm
type alias FQName =
    ( Path       -- package path  e.g. [ ["morphir"], ["sdk"] ]
    , Path       -- module path   e.g. [ ["basics"] ]
    , Name       -- local name    e.g. [ "int" ]
    )

-- Morphir.SDK.Basics.Int →
--   ( [ ["morphir"], ["sdk"] ]
--   , [ ["basics"] ]
--   , [ "int" ]
--   )
```

---

## Structure

### `Distribution`

The top-level artefact produced by `morphir-elm make`. Currently only the
`Library` variant exists.

```elm
type Distribution
    = Library
        PackageName                                         -- globally unique package id
        (Dict PackageName (Package.Specification ()))       -- dependency type signatures
        (Package.Definition () (Type ()))                   -- this package's full definition
```

### `Package.Specification`

The public surface of a package: only publicly-exposed module specifications.

```elm
type alias Package.Specification ta =
    { modules : Dict ModuleName (Module.Specification ta)
    }
```

### `Package.Definition`

The complete package, including private modules and value implementations.

```elm
type alias Package.Definition ta va =
    { modules : Dict ModuleName (AccessControlled (Module.Definition ta va))
    }
```

### `Module.Specification`

The public surface of a single module.

```elm
type alias Module.Specification ta =
    { types  : Dict Name (Documented (Type.Specification ta))
    , values : Dict Name (Documented (Value.Specification ta))
    , doc    : Maybe String
    }
```

### `Module.Definition`

A complete module, including private types, private values, and implementations.

```elm
type alias Module.Definition ta va =
    { types  : Dict Name (AccessControlled (Documented (Type.Definition ta)))
    , values : Dict Name (AccessControlled (Documented (Value.Definition ta va)))
    , doc    : Maybe String
    }
```

### `AccessControlled`

A wrapper that attaches a public/private access level to any IR node.

```elm
type alias AccessControlled a =
    { access : Access   -- Public | Private
    , value  : a
    }

type Access = Public | Private

-- Elm: "exposing (..)" vs not-exposing → Public vs Private
```

### `Documented`

A wrapper that attaches a doc-comment string to any IR node.

```elm
type alias Documented a =
    { doc   : String
    , value : a
    }

-- Elm: {-| The doc comment. -}
```

---

## Types

### `Type` — type expressions

Used anywhere a type appears: right-hand side of aliases, field types, function
signatures, value annotations.

```elm
type Type a
    = Variable        a Name
    | Reference       a FQName (List (Type a))
    | Tuple           a (List (Type a))
    | Record          a (List (Field a))
    | ExtensibleRecord a Name (List (Field a))
    | Function        a (Type a) (Type a)
    | Unit            a
```

| Variant | Elm syntax |
|---|---|
| `Variable a name` | `a`, `comparable`, `number` |
| `Reference a fqn args` | `Int`, `List Int`, `Maybe a` |
| `Tuple a [t1, t2]` | `( Int, String )` |
| `Record a fields` | `{ foo : Int, bar : String }` |
| `ExtensibleRecord a var fields` | `{ r \| foo : Int }` |
| `Function a arg ret` | `Int -> String` |
| `Unit a` | `()` |

### `Field`

One field inside a record type.

```elm
type alias Field a =
    { name : Name
    , tpe  : Type a
    }

-- { price : Float } → Field { name = ["price"], tpe = Reference () floatFqn [] }
```

### `Type.Specification`

The public shape of a type (no implementation details).

```elm
type Type.Specification a
    = TypeAliasSpecification  (List Name) (Type a)
    | OpaqueTypeSpecification (List Name)
    | CustomTypeSpecification (List Name) (Constructors a)
    | DerivedTypeSpecification (List Name) (DerivedTypeSpecificationDetails a)
```

| Variant | Elm meaning |
|---|---|
| `TypeAliasSpecification` | `type alias Foo a = …` — constructors exposed |
| `OpaqueTypeSpecification` | `type Foo` with constructors hidden |
| `CustomTypeSpecification` | `type Foo = Bar \| Baz Int` — constructors exposed |
| `DerivedTypeSpecification` | opaque type with explicit serialisation functions |

### `Type.Definition`

The full declaration including implementation.

```elm
type Type.Definition a
    = TypeAliasDefinition (List Name) (Type a)
    | CustomTypeDefinition (List Name) (AccessControlled (Constructors a))

-- type alias Price = Float
-- type OrderStatus = Open | Closed
```

### Constructors

```elm
type alias Constructors a =
    Dict Name (ConstructorArgs a)

type alias ConstructorArgs a =
    List ( Name, Type a )

-- type Shape = Circle Float | Rect Float Float
-- → Dict.fromList
--     [ ( ["circle"], [ ( ["radius"], floatType ) ] )
--     , ( ["rect"],   [ ( ["width"], floatType )
--                     , ( ["height"], floatType ) ] )
--     ]
```

### `DerivedTypeSpecificationDetails`

```elm
type alias DerivedTypeSpecificationDetails a =
    { baseType    : Type a   -- the serialisable representation type
    , fromBaseType : FQName  -- function converting base → derived
    , toBaseType   : FQName  -- function converting derived → base
    }
```

---

## Values

### `Value` — value expressions

```elm
type Value ta va
    = Literal        va Literal
    | Constructor    va FQName
    | Tuple          va (List (Value ta va))
    | List           va (List (Value ta va))
    | Record         va (Dict Name (Value ta va))
    | Variable       va Name
    | Reference      va FQName
    | Field          va (Value ta va) Name
    | FieldFunction  va Name
    | Apply          va (Value ta va) (Value ta va)
    | Lambda         va (Pattern va) (Value ta va)
    | LetDefinition  va Name (Definition ta va) (Value ta va)
    | LetRecursion   va (Dict Name (Definition ta va)) (Value ta va)
    | Destructure    va (Pattern va) (Value ta va) (Value ta va)
    | IfThenElse     va (Value ta va) (Value ta va) (Value ta va)
    | PatternMatch   va (Value ta va) (List ( Pattern va, Value ta va ))
    | UpdateRecord   va (Value ta va) (Dict Name (Value ta va))
    | Unit           va
```

| Variant | Elm syntax |
|---|---|
| `Literal va lit` | `42`, `True`, `"hello"`, `3.14`, `'x'` |
| `Constructor va fqn` | `Just`, `Nothing`, `Ok` |
| `Tuple va [a, b]` | `( a, b )` |
| `List va [x, y]` | `[ x, y ]` |
| `Record va fields` | `{ foo = 1, bar = "x" }` |
| `Variable va name` | `x`, `myValue` |
| `Reference va fqn` | `Basics.add`, `List.map` |
| `Field va expr name` | `expr.fieldName` |
| `FieldFunction va name` | `.fieldName` |
| `Apply va f arg` | `f arg` (curried: `f a b` = `Apply (Apply f a) b`) |
| `Lambda va pat body` | `\x -> body`, `\( a, b ) -> …` |
| `LetDefinition va name def body` | `let x = … in body` |
| `LetRecursion va defs body` | `let f x = … g y = … in body` (mutually recursive) |
| `Destructure va pat scrut body` | `let (a, b) = expr in body` |
| `IfThenElse va cond t f` | `if cond then t else f` |
| `PatternMatch va scrut cases` | `case scrut of …` |
| `UpdateRecord va rec updates` | `{ rec \| field = newVal }` |
| `Unit va` | `()` |

### `Value.Specification`

The signature of a value without its implementation.

```elm
type alias Value.Specification ta =
    { inputs : List ( Name, Type ta )
    , output : Type ta
    }

-- add : Int -> Int -> Int
-- → { inputs = [ (["a"], intType), (["b"], intType) ]
--   , output = intType }
```

### `Value.Definition`

A complete value with argument names, types, and body.

```elm
type alias Value.Definition ta va =
    { inputTypes : List ( Name, va, Type ta )
    , outputType : Type ta
    , body       : Value ta va
    }

-- add a b = a + b
-- → { inputTypes = [ (["a"], (), intType), (["b"], (), intType) ]
--   , outputType = intType
--   , body       = Apply (Apply (Reference plus) (Variable ["a"])) (Variable ["b"]) }
```

---

## Literals

```elm
type Literal
    = BoolLiteral    Bool     -- True, False
    | CharLiteral    Char     -- 'a', 'Z'
    | StringLiteral  String   -- "hello"
    | WholeNumberLiteral Int  -- 0, -1, 42
    | FloatLiteral   Float    -- 3.14, -0.5
    | DecimalLiteral Decimal  -- exact decimal (no floating-point rounding)
```

---

## Patterns

```elm
type Pattern a
    = WildcardPattern     a
    | AsPattern           a (Pattern a) Name
    | TuplePattern        a (List (Pattern a))
    | ConstructorPattern  a FQName (List (Pattern a))
    | EmptyListPattern    a
    | HeadTailPattern     a (Pattern a) (Pattern a)
    | LiteralPattern      a Literal
    | UnitPattern         a
```

| Variant | Elm syntax |
|---|---|
| `WildcardPattern` | `_` |
| `AsPattern pat name` | `pat as name`; bare variable `x` = `WildcardPattern \|> AsPattern x` |
| `TuplePattern [p1, p2]` | `( p1, p2 )` |
| `ConstructorPattern fqn args` | `Just x`, `Ok val`, `Node left right` |
| `EmptyListPattern` | `[]` |
| `HeadTailPattern h t` | `head :: tail` |
| `LiteralPattern lit` | `0`, `"foo"`, `True` |
| `UnitPattern` | `()` |

---

## Type aliases used in the IR

| Alias | Underlying type | Meaning |
|---|---|---|
| `Name` | `List String` | identifier word-list |
| `Path` | `List Name` | package / module path |
| `PackageName` | `Path` | globally unique package id |
| `ModuleName` | `Path` | module id within a package |
| `FQName` | `( Path, Path, Name )` | fully-qualified identifier |
| `RawValue` | `Value () ()` | unannotated value |
| `TypedValue` | `Value () (Type ())` | value with type annotations |
