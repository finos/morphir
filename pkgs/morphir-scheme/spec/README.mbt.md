# Specification notation

The `finos/morphir-scheme/spec` package reads and writes package specifications in a small notation.
This chapter covers the notation, its forms, type expressions and naming rules, the API, and every error it reports.
The Scheme reader that the notation uses is described in [Morphir Scheme](../README.mbt.md#lexical-syntax).

Chapters: [index](../README.mbt.md) · previous: [Transform scripts](../pipeline/README.mbt.md)

## The notation

The notation is data.
It is read with the Morphir Scheme reader and is never evaluated.
Each file holds one package.
Line comments, block comments and datum comments are allowed.
`pkgs/morphir-sdk-spec/sdk.scm` is written in this notation.

In the examples of this chapter, a block that holds a `package` form is read with `read_package` and printed with
`print_package`.
The printer puts each module, type and val on a line of its own.
The `;; =>` line shows the same text joined onto one line.
Any other block holds one type expression.
It is read with `read_type_text` in package `my/pkg`, module `m`, and printed with `print_type`.
An `;; error:` line shows the line and the column of the refusal, then its message.

```scheme
(package "morphir/SDK"
  (module basics
    (doc "Core types.")
    (type order (custom (LT) (EQ) (GT)))
    (val add ((a number) (b number)) number)
    (val compare ((a comparable) (b comparable)) basics#order))
  (module maybe
    (type maybe (custom (just a) (nothing)) a)
    (val map ((f (-> a b)) (maybe (maybe#maybe a))) (maybe#maybe b)
      (doc "Map a value."))))
;; => (package "morphir/SDK" (module basics (doc "Core types.") (type order (custom (LT) (EQ) (GT))) (val add ((a number) (b number)) number) (val compare ((a comparable) (b comparable)) basics#order)) (module maybe (type maybe (custom (just a) (nothing)) a) (val map ((f (-> a b)) (maybe (maybe#maybe a))) (maybe#maybe b) (doc "Map a value."))))
```

Comments are skipped, and a datum comment removes the form after it.

```scheme
(package "my/pkg" ; a line comment
  #| a block comment |#
  (module m
    #;(type removed (opaque))
    (type id (opaque))))
;; => (package "my/pkg" (module m (type id (opaque))))
```

## The API

| Function | Purpose |
| --- | --- |
| `read_package(source)` | Read a file. It returns the package name and its `PackageSpecification`. |
| `read_type_text(text, package_name~, module_path~)` | Read one type expression. `module#name` references resolve in `package_name`. |
| `print_package(name, spec)` | Write a package in the canonical layout |
| `print_type(t, package_name~)` | Write one type expression |

Every refusal raises `SpecError { line, column, message }`.
`read_type_text` refuses a `package_name` or a `module_path` that `Path::parse` refuses.
It checks `module_path` but does not use it, because every reference names its module.

Read, then print, then read gives the same result.
The printer is lossless only for what the reader makes.
It drops constructor argument names, `Named` annotation argument names, module and type annotations, annotation
data that is not a literal or a list, and `Compact` annotation text.

```mbt check
///|
test "read, print, then read gives the same result" {
  let source =
    #|(package "morphir/SDK"
    #|  (module basics
    #|    (type order (custom (LT) (EQ) (GT)))
    #|    (val add ((a number) (b number)) number)))
  let (name, spec) = @spec.read_package(source)
  let printed = @spec.print_package(name, spec)
  let (name2, spec2) = @spec.read_package(printed)
  assert_eq(name2, name)
  assert_eq(@spec.print_package(name2, spec2), printed)
}
```

The canonical layout indents a module by two spaces and its items by four.
A val's `doc` and `annotation` forms go on lines of their own, six spaces in.

```mbt check
///|
test "the canonical layout" {
  let (name, spec) = @spec.read_package(
    "(package \"my/pkg\" (module m (doc \"M.\") (type id (opaque)) (val now () m#id (doc \"Now.\") (annotation m#since \"1.0\"))) (module n (val zero () m#id)))",
  )
  inspect(
    @spec.print_package(name, spec),
    content=(
      #|(package "my/pkg"
      #|  (module m
      #|    (doc "M.")
      #|    (type id (opaque))
      #|    (val now () m#id
      #|      (doc "Now.")
      #|      (annotation my/pkg:m#since "1.0")))
      #|  (module n
      #|    (val zero () m#id)))
    ),
  )
}
```

## Forms

| Form | Meaning |
| --- | --- |
| `(package "pkg/path" module…)` | The whole package. The name is a canonical path. |
| `(module name item…)` | A module. `name` is a canonical module path written as a symbol, for example `json/encode`. |
| `(doc "text")` | Documentation. In a module it must be the first item. In a type it comes right after the name. In a val it must be the first trailing item. |
| `(type name body param…)` | A type. The trailing params are its type variables. |
| `(val name ((arg type)…) result item…)` | A value signature. The inputs keep their order. The trailing items are a `doc` and `annotation` forms. |
| `(annotation fqname arg…)` | An annotation of a val. The arguments are data: a string, an integer, a boolean or a list of data. `(annotation fq)` with no arguments is `Compact(fq, None)`. |

A type, a value, a constructor, a record field or a module that appears twice in its scope is refused.

### package

A file holds exactly one `package` form, and the package may have no modules.

```scheme
(package "my/pkg")
;; => (package "my/pkg")
```

The name is a string that holds a canonical path.

```scheme
(package "My/Pkg")
;; error: 1:10: package name `My/Pkg` is not canonical
```

```scheme
(package my/pkg)
;; error: 1:10: expected a package name
```

A second form after the package is refused at the first form.

```scheme
(package "my/pkg")
(package "other")
;; error: 1:1: expected (package "name" module...)
```

Every item of a package is a `module` form.

```scheme
(package "my/pkg" (modul m))
;; error: 1:19: expected (module name item...)
```

### module

A module name is a symbol that holds a canonical module path.

```scheme
(package "my/pkg" (module json/encode))
;; => (package "my/pkg" (module json/encode))
```

```scheme
(package "my/pkg" (module Json))
;; error: 1:27: module name `Json` is not canonical
```

```scheme
(package "my/pkg" (module "m"))
;; error: 1:27: expected a module name
```

```scheme
(package "my/pkg" (module))
;; error: 1:19: a module is (module name item...)
```

Every item of a module is a `doc`, `type` or `val` form.

```scheme
(package "my/pkg" (module m (frob x)))
;; error: 1:29: unknown item form `frob`
```

```scheme
(package "my/pkg" (module m x))
;; error: 1:29: expected an item form
```

### doc

A `doc` form documents a module, a type or a val.

```scheme
(package "my/pkg"
  (module m
    (doc "Money.")
    (type amount (doc "An amount in cents.") (alias basics#int))
    (val zero () m#amount (doc "No money."))))
;; => (package "my/pkg" (module m (doc "Money.") (type amount (doc "An amount in cents.") (alias basics#int)) (val zero () m#amount (doc "No money."))))
```

In a module, a `doc` after another item is refused.

```scheme
(package "my/pkg" (module m (type t (opaque)) (doc "Late.")))
;; error: 1:47: a doc must be the first item
```

In a val, a `doc` after an annotation is refused.

```scheme
(package "my/pkg" (module m (val f () a (annotation m#x) (doc "Late."))))
;; error: 1:58: a doc must be the first item
```

In a type, a `doc` after the body is read as a type parameter, so it is refused as a name.

```scheme
(package "my/pkg" (module m (type t (opaque) (doc "Late."))))
;; error: 1:46: expected a name
```

A `doc` holds exactly one string.

```scheme
(package "my/pkg" (module m (doc 1)))
;; error: 1:29: a doc is (doc "text")
```

### type

A type has a name, an optional `doc`, a body and its type parameters.
The body is one of four forms.

| Body | Meaning |
| --- | --- |
| `(opaque)` | An opaque type |
| `(alias type)` | A type alias |
| `(custom (ctor type…)…)` | A custom type. The constructors keep their order. The notation names no constructor arguments, so they are `arg-1`, `arg-2`, …. |
| `(derived base from-fqname to-fqname)` | A derived type |

```scheme
(package "my/pkg" (module m (type id (opaque))))
;; => (package "my/pkg" (module m (type id (opaque))))
```

```scheme
(package "my/pkg" (module m (type pair (alias (tuple a b)) a b)))
;; => (package "my/pkg" (module m (type pair (alias (tuple a b)) a b)))
```

```scheme
(package "my/pkg" (module m (type maybe (custom (just a) (nothing)) a)))
;; => (package "my/pkg" (module m (type maybe (custom (just a) (nothing)) a)))
```

```scheme
(package "my/pkg" (module m (type money (derived basics#int m#from-cents m#to-cents))))
;; => (package "my/pkg" (module m (type money (derived basics#int m#from-cents m#to-cents))))
```

The errors of a type and its body:

```scheme
(package "my/pkg" (module m (type t)))
;; error: 1:29: a type is (type name body param...)
```

```scheme
(package "my/pkg" (module m (type t x)))
;; error: 1:37: expected a type body
```

```scheme
(package "my/pkg" (module m (type t (unknown))))
;; error: 1:37: unknown type body `unknown`
```

```scheme
(package "my/pkg" (module m (type t (opaque x))))
;; error: 1:37: opaque takes no arguments
```

```scheme
(package "my/pkg" (module m (type t (alias a b))))
;; error: 1:37: alias takes one type
```

```scheme
(package "my/pkg" (module m (type t (custom A))))
;; error: 1:45: a constructor is (name type...)
```

```scheme
(package "my/pkg" (module m (type t (derived a b))))
;; error: 1:37: derived is (derived type from-name to-name)
```

```scheme
(package "my/pkg" (module m (type t (derived a b c))))
;; error: 1:48: expected a qualified name
```

### val

A val has a name, a list of `(name type)` inputs, a result type, then an optional `doc` and any number of
annotations.

```scheme
(package "my/pkg" (module m (val add ((a number) (b number)) number)))
;; => (package "my/pkg" (module m (val add ((a number) (b number)) number)))
```

```scheme
(package "my/pkg" (module m (val now () basics#int (doc "The time."))))
;; => (package "my/pkg" (module m (val now () basics#int (doc "The time."))))
```

The errors of a val:

```scheme
(package "my/pkg" (module m (val f)))
;; error: 1:29: a val is (val name ((arg type)...) result item...)
```

```scheme
(package "my/pkg" (module m (val f a b)))
;; error: 1:36: expected a parameter list
```

```scheme
(package "my/pkg" (module m (val f (a) b)))
;; error: 1:37: a parameter is (name type)
```

```scheme
(package "my/pkg" (module m (val f () b x)))
;; error: 1:41: expected a doc or an annotation
```

```scheme
(package "my/pkg" (module m (val f () a (frob))))
;; error: 1:41: unknown item form `frob`
```

### annotation

An annotation names a value with `module#name` or `pkg:module#name`.
Its arguments are data: strings, integers, booleans and lists of data.
With no arguments it is `Compact(fq, None)`; with arguments it is `Structured`.
The printer writes the annotation name in full, as `pkg:module#name`, even in the file's own package.
That is current behaviour, tracked by bead `morphir-ukvn.5.52`.

```scheme
(package "my/pkg" (module m (val f () a (annotation m#deprecated))))
;; => (package "my/pkg" (module m (val f () a (annotation my/pkg:m#deprecated))))
```

```scheme
(package "my/pkg" (module m (val f () a (doc "F.") (annotation m#since "1.0" 2 #t (1 2)))))
;; => (package "my/pkg" (module m (val f () a (doc "F.") (annotation my/pkg:m#since "1.0" 2 #t (1 2)))))
```

The errors of an annotation:

```scheme
(package "my/pkg" (module m (val f () a (annotation))))
;; error: 1:41: an annotation is (annotation name arg...)
```

```scheme
(package "my/pkg" (module m (val f () a (annotation x))))
;; error: 1:53: an annotation needs a qualified name
```

```scheme
(package "my/pkg" (module m (val f () a (annotation m#x 1.5))))
;; error: 1:57: annotation arguments are data
```

### Duplicates

A duplicate is refused at the second form.

```scheme
(package "my/pkg" (module m) (module m))
;; error: 1:30: duplicate module `m`
```

```scheme
(package "my/pkg" (module m (type t (opaque)) (type t (opaque))))
;; error: 1:47: duplicate type `t`
```

```scheme
(package "my/pkg" (module m (val f () a) (val f () a)))
;; error: 1:42: duplicate value `f`
```

```scheme
(package "my/pkg" (module m (type t (custom (A) (A)))))
;; error: 1:49: duplicate constructor `A`
```

```scheme
(record (a basics#int) (a basics#int))
;; error: 1:24: duplicate field `a`
```

## Type expressions

| Syntax | IR |
| --- | --- |
| A bare symbol, for example `a` or `comparable` | `Variable`. A name that starts with `number`, `comparable`, `appendable` or `compappend` also gets the constraint `typeclass` with that class. |
| `module#name`, `pkg:module#name` | A `Reference` with no arguments |
| `(module#name t…)`, `(pkg:module#name t…)` | A `Reference` with arguments, for example `(list#list a)` |
| `(-> a b c)` | A curried `Function`, `a -> b -> c`. It needs at least two types. |
| `(tuple a b …)` | `Tuple`, with at least two types |
| `(record (field t)…)` | `Record` |
| `(record r (field t)…)` | `ExtensibleRecord` over the row variable `r` |
| `()` | `Unit` |

A variable prints as its name.

```scheme
comparable-key
;; => comparable-key
```

The constraint does not show in the notation, so this test checks it on the IR.

```mbt check
///|
test "a variable named after a class gets its constraint" {
  let t = @spec.read_type_text(
    "comparable-key",
    package_name="my/pkg",
    module_path="m",
  )
  guard t is Variable(attributes, _) else { fail("expected a variable") }
  assert_eq(
    attributes.constraints.get("typeclass"),
    Some(@ir.Data::Text("comparable")),
  )
}
```

```scheme
basics#int
;; => basics#int
```

```scheme
(list#list a)
;; => (list#list a)
```

A reference to another package can be applied in the same way.

```scheme
(other/pkg:dict#dict string#string a)
;; => (other/pkg:dict#dict string#string a)
```

A reference applied to no types is the same as the bare reference.

```scheme
(maybe#maybe)
;; => maybe#maybe
```

```scheme
(-> a b c)
;; => (-> a b c)
```

```scheme
(tuple a b basics#int)
;; => (tuple a b basics#int)
```

```scheme
(record (name string#string) (age basics#int))
;; => (record (name string#string) (age basics#int))
```

```scheme
(record r (name string#string) (age basics#int))
;; => (record r (name string#string) (age basics#int))
```

```scheme
()
;; => ()
```

The errors of type expressions:

```scheme
(-> a)
;; error: 1:1: a function type needs at least two types
```

```scheme
(tuple a)
;; error: 1:1: a tuple needs at least two types
```

```scheme
(record (a))
;; error: 1:9: a record field is (name type)
```

```scheme
(frob a)
;; error: 1:1: unknown type form `frob`
```

```scheme
(1 a)
;; error: 1:1: expected a type form
```

```scheme
"text"
;; error: 1:1: expected a type
```

`read_type_text` reads exactly one type expression.

```scheme
a b
;; error: 1:1: expected one type
```

`read_type_text` also refuses a `package_name` or a `module_path` argument that `Path::parse` refuses, at line 1,
column 1.

```mbt check
///|
test "read_type_text refuses a bad package or module name" {
  fn refusal(package_name : String, module_path : String) -> String {
    try {
      ignore(@spec.read_type_text("a", package_name~, module_path~))
      ""
    } catch {
      @spec.SpecError(line~, column~, message~) =>
        "\{line}:\{column}: \{message}"
    }
  }
  inspect(
    refusal("Bad Name!", "m"),
    content="1:1: invalid package name `Bad Name!`",
  )
  inspect(
    refusal("my/pkg", "Bad Name!"),
    content="1:1: invalid module name `Bad Name!`",
  )
}
```

## The `module#name` rule

A reference is `module#name` or `pkg:module#name`.
`module#name` resolves in the file's own package, for example `basics#order` in `morphir/SDK`.
`pkg:module#name` names any package.
The printer writes `module#name` when the package is the file's package, and `pkg:module#name` otherwise.

```scheme
(tuple other/pkg:list#list my/pkg:basics#int)
;; => (tuple other/pkg:list#list basics#int)
```

There is no `#name` form for the current module.
The Scheme reader refuses a token that starts with `#`, other than its own literals.
Accepting `#name` would change the reader for every Scheme program.
The reader reports the position after the token, so `#order` at column 1 is refused at column 7.

```scheme
#order
;; error: 1:7: Unknown reader token: #order
```

## Names

Names follow the canonical v4 rules and are parsed with `Name::parse`, for example `less-than`, `map-2` and `LT`.
A name that is not canonical is refused, and the message suggests a spelling.

```scheme
(package "my/pkg" (module m (type order (custom (LT) (EQ) (GT))) (val less-than ((a m#order) (b m#order)) basics#bool)))
;; => (package "my/pkg" (module m (type order (custom (LT) (EQ) (GT))) (val less-than ((a m#order) (b m#order)) basics#bool)))
```

```scheme
lessThan
;; error: 1:1: name `lessThan` is not canonical (use `less-than`)
```

The suggestion only splits a camelCase name into words.
For other names it repeats the name.
That is current behaviour, tracked by bead `morphir-ukvn.5.52`.

```scheme
less_than
;; error: 1:1: name `less_than` is not canonical (use `less_than`)
```

A reference must also be canonical.
`FQName::parse` refuses the references that are not canonical, so the message says that the text is not a reference.

```scheme
basics#lessThan
;; error: 1:1: `basics#lessThan` is not a reference
```

## Reserved `!` heads

A symbol that ends in `!` is reserved for macros, which a later pre-pass will expand into plain data.
The reader refuses it as the head of a module, an item, a type body or a type form, and as a type variable.
A file whose only form is `(package! …)` is refused with `expected (package "name" module...)` instead.

```scheme
(val-family! a)
;; error: 1:1: `val-family!` is reserved for macros
```

```scheme
a!
;; error: 1:1: `a!` is reserved for macros
```

```scheme
(package "my/pkg" (module m (type! t (opaque))))
;; error: 1:29: `type!` is reserved for macros
```

In other name positions, such as a type parameter, a constructor or an input name, a name that ends in `!` is not
canonical.
The message then repeats the name as its suggestion.
That is current behaviour, tracked by bead `morphir-ukvn.5.52`.

```scheme
(package "my/pkg" (module m (type t (opaque) a!)))
;; error: 1:46: name `a!` is not canonical (use `a!`)
```

## Errors

Every refusal is a `SpecError` with the line and the column of the form that is wrong, and a short message.
Lines and columns count from 1.

```scheme
(package "my/pkg"
  (module m
    (type t (opaque))
    (type t (opaque))))
;; error: 4:5: duplicate type `t`
```

An error of the Scheme reader keeps the reader's message and position.

```scheme
(package "my/pkg"
  (module m (type t #order)))
;; error: 2:27: Unknown reader token: #order
```

The table lists every message.

| Message | Refused |
| --- | --- |
| `expected (package "name" module...)` | A file with no form, with more than one form, or with a form other than `package` |
| `expected (module name item...)` | A package item that is not a `module` form |
| `expected a package name` | A package name that is not a string |
| ``package name `p` is not canonical`` | A package name that `Path::parse` refuses. The code also has a form that adds ``(use `q`)``, but it does not occur today, because `Path::parse` accepts only canonical text. |
| ``module name `m` is not canonical`` | A module name that `Path::parse` refuses. The ``(use `q`)`` form does not occur today, for the same reason. |
| `expected a module name` | A module name that is not a symbol |
| `a module is (module name item...)` | A module with no name |
| `expected an item form` | A module item that is not a form |
| ``unknown item form `x` `` | A module item or a val item with an unknown head |
| `a doc must be the first item` | A `doc` after another item of a module or a val |
| `a doc is (doc "text")` | A `doc` that does not hold exactly one string |
| `a type is (type name body param...)` | A type with no name or no body |
| `expected a type body` | A type body that is not a form |
| ``unknown type body `x` `` | A type body with an unknown head |
| `opaque takes no arguments` | `(opaque x)` |
| `alias takes one type` | An `alias` with no type or more than one |
| `a constructor is (name type...)` | A constructor that is not a form headed by a name |
| `derived is (derived type from-name to-name)` | A `derived` without exactly three parts |
| `expected a qualified name` | A `derived` conversion that is not a `module#name` reference |
| `a val is (val name ((arg type)...) result item...)` | A val that lacks a name, an input list or a result |
| `expected a parameter list` | Val inputs that are not a list |
| `a parameter is (name type)` | An input that is not a `(name type)` pair |
| `expected a doc or an annotation` | A val item that is not a form |
| `an annotation is (annotation name arg...)` | An annotation with no name |
| `an annotation needs a qualified name` | An annotation name that is not a `module#name` reference |
| `annotation arguments are data` | An annotation argument that is not a string, an integer, a boolean or a list |
| ``duplicate module `m` `` and the same for `type`, `value`, `constructor` and `field` | A name that appears twice in its scope |
| `a function type needs at least two types` | `(-> a)` |
| `a tuple needs at least two types` | `(tuple a)` |
| `a record field is (name type)` | A record field that is not a `(name type)` pair |
| ``unknown type form `x` `` | A type form with an unknown head |
| `expected a type form` | A type form whose head is not a symbol |
| `expected a type` | A type that is neither a symbol nor a proper list, such as a string or a number |
| `expected one type` | `read_type_text` text with no type or more than one |
| ``invalid package name `p` `` | A `package_name` argument of `read_type_text` that is not a path |
| ``invalid module name `m` `` | A `module_path` argument of `read_type_text` that is not a path |
| `expected a name` | A name that is not a symbol |
| ``name `x` is not canonical (use `y`)`` | A name that `Name::parse` refuses. `y` is `x` with each capital letter after the first character replaced by a hyphen and its small letter. |
| `` `x` is not a reference`` | A reference that does not parse as a canonical `pkg:module#name` |
| ``reference `x` is not canonical (use `y`)`` | Does not occur today. `FQName::parse` accepts only canonical text, so a reference that is not canonical gets `` `x` is not a reference`` instead. |
| `` `x!` is reserved for macros`` | A head or a type variable that ends in `!` |
| The reader's message | Text that the Scheme reader refuses with a syntax error, at the reader's position |
| The reader's error as text | Text that the Scheme reader refuses with another error, at line 1, column 1 |
