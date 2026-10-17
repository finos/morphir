# Writing models

The `finos/morphir-scheme/frontend` package lowers Scheme expressions and files to current Morphir IR.
This chapter covers what the frontend produces, `compile_expression` and `compile_file`, the functional subset form by
form with the IR each form lowers to, literals and their types, qualified references, type placeholders and inference,
and what the frontend rejects and why.
The core forms themselves are described in [Morphir Scheme](../README.mbt.md#special-forms); this chapter covers only
what changes when they are compiled.

Chapters: [index](../README.mbt.md) · previous: [Morphir Scheme](../README.mbt.md) · next: [Running Morphir IR](../backend/README.mbt.md)

## The package

Declare `finos/morphir-scheme@0.1.0` in your module and import `finos/morphir-scheme/frontend`.
The examples use the aliases `scheme`, `frontend`, `backend` and `ir`.
Running the compiled IR is described in [Running Morphir IR](../backend/README.mbt.md).

| Function | Result |
| --- | --- |
| `compile_expression(source)` | One expression as an `@ir.Value` |
| `compile_file(source, package_name="user", module_name="main")` | A whole file as an `@ir.IRFile` |
| `primitive(name)` | The fully qualified Morphir SDK name of a primitive, as text, or `None` |
| `result_type(value)` | The type the frontend writes in a signature whose body is `value` |
| `unknown_type()` | The placeholder type variable `scheme-value` |

The frontend lowers structure.
It does no type inference and no type checking.
Types that the source does not state are left as placeholders for the engine to solve, as described in
[Type placeholders and inference](#type-placeholders-and-inference).

## What the frontend produces

`compile_file` returns an `IRFile` whose distribution is a `Library`.

| Part | Value |
| --- | --- |
| Package | `package_name`, by default `user` |
| Dependencies | None |
| Modules | One public module, `module_name`, by default `main` |
| Types | None |
| Values | One per leading definition, and `main` when the file has trailing expressions |
| Each value | Public, with no documentation, and an `ExpressionBody` definition |

`package_name` and `module_name` are Morphir paths.
A path is one or more names separated by `/`, such as `my/pkg`.
Each name follows the rules in [Names](#names).

```mbt check
///|
test "compile_file produces a library with one module" {
  let file = @frontend.compile_file(
    "(define (inc x) (+ x 1)) (inc 41)",
    package_name="my/pkg",
    module_name="util",
  )
  guard file.distribution is Library(package_path, dependencies, definition) else {
    fail("expected a library")
  }
  inspect(package_path.to_canonical(), content="my/pkg")
  assert_true(dependencies.is_empty())
  let names = definition.modules.keys().map(m => m.to_canonical()).collect()
  assert_eq(names, ["util"])
  guard definition.modules.get(@ir.Path::parse("util")) is Some(module_) else {
    fail("expected module util")
  }
  let values = module_.value.values.keys().map(n => n.to_canonical()).collect()
  values.sort()
  assert_eq(values, ["inc", "main"])
  let answer = @backend.run_file(file, @ir.FQName::parse("my/pkg:util#main"), [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

## Compile an expression

`compile_expression(source)` lowers exactly one expression to a value.
The expression cannot contain a `define`.
Placeholders in its signatures stay as `unknown_type()`, the type variable `scheme-value` without the unknown marker.
Only `compile_file` numbers them, as described in [Type placeholders and inference](#type-placeholders-and-inference).

| Error | Message |
| --- | --- |
| The source holds no expression or more than one | `Expected one expression` |
| The expression is a `define` | `Unsupported: Cannot lower define to functional Morphir IR` |

```mbt check
///|
test "compile and evaluate one expression" {
  let value = @frontend.compile_expression("(let ((x 6)) (* x 7))")
  let result = @backend.evaluate(value)
  inspect(@scheme.value_to_string(result), content="42")
  let refused = try {
    ignore(@frontend.compile_expression("1 2"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(refused, content="Expected one expression")
  let bound = @frontend.compile_expression("(let ((f (lambda (x) x))) f)")
  assert_true(
    bound is LetDefinition(_, _, ExpressionBody([(_, input)], _, _), _) &&
    input == @frontend.unknown_type(),
  )
}
```

## Compile a file

`compile_file(source)` reads a file as leading definitions followed by trailing expressions.
Each leading definition becomes a public module value.
The trailing expressions, if there are any, become a value named `main`.
`main` has no inputs, unless its body is a `lambda`.
Then the lambda's parameters become the inputs of `main`, as for a definition.
`main` runs the expressions in order, and its value is the value of the last one.

```mbt check
///|
test "compile a file and run its main" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let answer = @backend.run_file(file, @ir.FQName::parse("user:main#main"), [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

In the Scheme examples of this chapter, each block is compiled as a file in module `main` and its `main` is run.
Its printed result is compared with the `;; =>` line, and the start of its error message with the `;; error:` line.
An error comes from the frontend, or, for a file the frontend accepts, from running it.

A block that starts with `;; file: src/<module>.scm` is a file of a project, compiled as module `<module>`.
Consecutive `;; file:` blocks form one project, checked as a whole.
Every file is compiled and loaded into one runtime in order, then the last file's `main` is run.
So a file can call a definition of an earlier file by its qualified reference, as shown in
[Qualified references](#qualified-references).
Only the last block states the expectation.

```scheme
(define (inc x) (+ x 1))
(inc 41)
;; => 42
```

A definition has one of two forms.

| Form | Value |
| --- | --- |
| `(define name expression)` | `name`, with the expression's value |
| `(define (name parameter ...) body ...)` | `name`, a function with the parameters as its inputs |

The second form is short for `(define name (lambda (parameter ...) body ...))`.
The leading lambdas of a definition's expression become the inputs of its definition, so both forms give the same IR.

```scheme
(define pi 3.14)
(define area (lambda (r) (* pi (* r r))))
(area 2.0)
;; => 12.56
```

Every definition name is in scope in the whole file.
A definition can therefore use a definition that comes after it.

```scheme
(define (twice x) (inc (inc x)))
(define (inc x) (+ x 1))
(twice 40)
;; => 42
```

A definition name also hides a primitive of the same name in the whole file.

```scheme
(define (length x) 0)
(length '(1 2 3))
;; => 0
```

| Error | Message |
| --- | --- |
| A definition after a trailing expression | `Unsupported: Definitions must precede expressions` |
| `define` with no expression | `Incomplete definition` |
| More than one expression after a name | `define needs one expression` |
| A function with no parameter, such as `(define (name) body)`, or a target that is neither a symbol nor a list | `Unsupported: Top-level function requires at least one parameter` |
| A function name that is not a symbol | `Expected identifier` |
| Two definitions of one name | `Duplicate definition: name` |
| A definition named `main` and trailing expressions | `Final expression conflicts with definition main` |

```scheme
1
(define x 1)
;; error: Unsupported: Definitions must precede expressions
```

```scheme
(define x 1)
(define x 2)
x
;; error: Duplicate definition: x
```

```scheme
(define (main x) x)
(main 1)
;; error: Final expression conflicts with definition main
```

```scheme
(define (answer) 42)
(answer 1)
;; error: Unsupported: Top-level function requires at least one parameter
```

## The functional subset

The frontend accepts the functional subset of the language.
The table lists each form and the IR it lowers to.
In the IR column, `x` stands for the lowered form of `x`.

| Form | Lowers to |
| --- | --- |
| A literal | `Literal`, as listed in [Literals and their types](#literals-and-their-types) |
| A local name `x` | `Variable(x)` |
| A primitive name such as `+` | `Reference(morphir/SDK:basics#add)` |
| A qualified name `package:module#name` | `Reference(package:module#name)` |
| `(f a b)` | `Apply(Apply(f, a), b)` |
| `(+ a b c)` | `Apply(Apply(add, Apply(Apply(add, a), b)), c)` |
| `(- a)`, `(/ a)` | `Apply(Apply(subtract, 0), a)`, `Apply(Apply(divide, 1), a)` |
| `(+)`, `(*)`, `(string-append)` | `Literal(0)`, `Literal(1)`, `Literal("")` |
| `(lambda (x y) body)` | `Lambda(x, Lambda(y, body))` |
| `(if c t e)` | `IfThenElse(c, t, e)` |
| `(begin a b)` | `LetDefinition(scheme-temporary-n, a, b)` |
| `(begin)` | `Unit` |
| `(let ((x e)) body)` | `LetDefinition(scheme-temporary-n, e, LetDefinition(x, Variable(scheme-temporary-n), body))` |
| `(let* ((x e) (y f)) body)` | `LetDefinition(x, e, LetDefinition(y, f, body))` |
| `(letrec ((f e)) body)` | `LetRecursion({f: e}, body)` |
| `(list a b)` | `List([a, b])` |
| `'(1 2)` | `List([Literal(1), Literal(2)])` |

```scheme
(define (fact n)
  (if (= n 0) 1 (* n (fact (- n 1)))))
(let* ((a 4) (b (+ a 1)))
  (list (fact b) (+ 1 2 3)))
;; => (120 6)
```

### Names

A name lowers in this order.

1. A name bound by a parameter, a `let` form or a definition lowers to `Variable(name)`.
2. A primitive name lowers to a `Reference` to its Morphir SDK function.
3. A name that contains `#` is a qualified reference; see [Qualified references](#qualified-references).
4. Any other name lowers to `Variable(name)`.

A name that lowers to a variable, and each part of a qualified name, follows Morphir's canonical naming rules.
A name is one or more words separated by single `-` characters.
Each word holds only lowercase letters and digits, or only uppercase letters and digits.
A name such as `even?`, `myName` or `my_x` is refused with the message
`finos/morphir-ir/common.NameError.InvalidName`, which does not name the offending name.

```scheme
(define (even? n) (= n 0))
(even? 2)
;; error: finos/morphir-ir/common.NameError.InvalidName
```

| Primitive | Morphir SDK reference |
| --- | --- |
| `+` | `morphir/SDK:basics#add` |
| `-` | `morphir/SDK:basics#subtract` |
| `*` | `morphir/SDK:basics#multiply` |
| `/` | `morphir/SDK:basics#divide` |
| `=` | `morphir/SDK:basics#equal` |
| `<` | `morphir/SDK:basics#less-than` |
| `>` | `morphir/SDK:basics#greater-than` |
| `<=` | `morphir/SDK:basics#less-than-or-equal` |
| `>=` | `morphir/SDK:basics#greater-than-or-equal` |
| `not` | `morphir/SDK:basics#not` |
| `length` | `morphir/SDK:list#length` |
| `string-append` | `morphir/SDK:string#append` |

A primitive used as a value is the curried Morphir SDK function.
It takes its arguments one at a time.

```scheme
(let ((add +))
  ((add 40) 2))
;; => 42
```

Other built-in procedures and special forms of the interpreter, such as `map`, `and`, `or` and `cond`, are not part of
the subset.
The frontend lowers their names to variables, as it does any other name.
Running the result fails because the variable has no binding.

```scheme
(and #t #f)
;; error: Unbound identifier: v:and
```

### Calls

`(f a b ...)` applies `f` to one argument at a time.
Any form can be in the head, and the arguments are lowered from left to right.

| Error | Message |
| --- | --- |
| A call with no arguments | `Unsupported: Zero-argument calls require explicit unit in Morphir` |
| A dotted call such as `(f . x)` | `Unsupported: Improper application` |
| The empty list `()` | `Empty application` |

```scheme
(define (add x y) (+ x y))
((add 40) 2)
;; => 42
```

### Arithmetic and comparison

A direct call of `+`, `-`, `*`, `/` or `string-append` takes any number of arguments.
The frontend folds the arguments from the left into curried calls of the two-argument SDK function.
With one argument, `-` subtracts it from the integer `0` and `/` divides the integer `1` by it.
Negating a Float this way fails; see [Literals and their types](#literals-and-their-types).
With no argument, `+` is `0`, `*` is `1` and `string-append` is `""`.
This folding happens only at a direct call: a primitive bound to a local name takes exactly two arguments.

`/` is the Morphir SDK `divide`, so its result is a Float.

```scheme
(list (+ 1 2 3) (- 5) (/ 7 2) (+) (string-append "a" "b" "c"))
;; => (6 -5 3.5 0 "abc")
```

A direct call of `=`, `<`, `>`, `<=` or `>=` takes exactly two arguments.

| Error | Message |
| --- | --- |
| `-` or `/` with no argument | `Arithmetic needs an operand` |
| A comparison with one, or three or more, arguments | `Unsupported: Morphir comparison calls need two operands` |

```scheme
(< 1 2 3)
;; error: Unsupported: Morphir comparison calls need two operands
```

### lambda

`(lambda (parameter ...) body ...)` lowers to one `Lambda` per parameter, nested from the first parameter to the last.
Each parameter becomes an `AsPattern` over a `WildcardPattern`, named after the parameter.
A call can therefore pass fewer arguments and get a function of the rest.

| Error | Message |
| --- | --- |
| No body | `lambda needs a body` |
| No parameter | `Unsupported: Morphir lambdas require a parameter; use unit explicitly` |
| A rest parameter, as in `(lambda args ...)` or `(lambda (a . rest) ...)` | `Expected proper syntax list`, a placeholder; bead `morphir-ukvn.5.46` tracks a clear error |
| A parameter that is not a symbol | `Expected identifier` |
| A repeated parameter | `Duplicate parameter` |

```scheme
((lambda (x y) (- x y)) 50 8)
;; => 42
```

```scheme
(lambda (x x) x)
;; error: Duplicate parameter
```

### if

`(if test consequent alternative)` lowers to `IfThenElse`.
Morphir conditions must be boolean, so programs that rely on Scheme truthiness are outside the portable subset.
The frontend refuses a condition that is a literal other than `#t` or `#f`.
It does not check any other condition, but running one that is not a boolean fails.

| Error | Message |
| --- | --- |
| Anything other than three parts after `if` | `if expects three arguments` |
| A literal condition that is not a boolean | `Unsupported: Morphir conditions must be boolean` |

```scheme
(if (< 1 2) "yes" "no")
;; => "yes"
```

```scheme
(if 0 1 2)
;; error: Unsupported: Morphir conditions must be boolean
```

```scheme
(if (+ 1 1) 1 2)
;; error: Morphir condition must be boolean
```

### begin and bodies

`(begin form ...)` is a body.
The body of a `lambda` or a `let` form is a body too, and so are the trailing expressions of a file.
A body with one form lowers to that form.
A body with more forms lowers each form but the last to a `LetDefinition` of a fresh name, `scheme-temporary-n`, around
the rest.
The frontend picks each temporary name so that it differs from every symbol in the source.
`(begin)` lowers to `Unit`.
`begin` raises no error of its own.

```scheme
(begin 1 2 3)
;; => 3
```

```scheme
(begin)
;; => #<unit>
```

### let, let* and letrec

`let*` lowers each binding to a `LetDefinition`, nested in order, so each expression sees the bindings before it.
`let` first binds each expression to a temporary name, then binds each name to its temporary.
This keeps the expressions of a `let` outside all of its new bindings.
`letrec` lowers to one `LetRecursion` that holds every binding, so each expression sees all of them.
In `let*` and `letrec`, a binding whose expression is a `lambda` gets the lambda's parameters as the inputs of its
definition.
In `let`, the lambda's parameters become the inputs of the temporary's definition, and the named binding has no inputs.

| Error | Message |
| --- | --- |
| No body | `let needs a body` |
| Bindings that are not a list, including a named `let` | `Expected proper syntax list` |
| A binding that is not a list, such as `(let (x) x)` | `Expected proper syntax list` |
| A binding that is not a name and one expression, such as `(let ((x)) x)` | `Binding expects name and expression` |
| A binding name that is not a symbol | `Expected identifier` |
| A repeated name in `let` or `letrec` | `Duplicate binding: name` |

```scheme
(let ((x 1)) (let ((x 2) (y x)) y))
;; => 1
```

```scheme
(let* ((x 1) (x (+ x 1))) x)
;; => 2
```

`letrec` is how to write a loop, because the frontend rejects a named `let`.

```scheme
(letrec ((loop (lambda (n sum) (if (= n 0) sum (loop (- n 1) (+ sum n))))))
  (loop 4 0))
;; => 10
```

### list and quote

`(list form ...)` lowers to a `List` of the lowered forms, and raises no error of its own.
`(quote datum)` and `'datum` lower the datum as a literal.
A quoted list becomes a `List` of literals, and `'()` is the empty `List`.
Only literals and proper lists of them can be quoted; see [What the frontend rejects](#what-the-frontend-rejects).

| Error | Message |
| --- | --- |
| Anything other than one datum after `quote` | `quote expects one argument` |

```scheme
(list (list 1 2) '(3 4) '())
;; => ((1 2) (3 4) ())
```

### Lowering, checked

This test pins the IR shape of each row of the table above.

```mbt check
///|
test "each form lowers to its IR shape" {
  let add = @ir.FQName::parse("morphir/SDK:basics#add")
  let call = @frontend.compile_expression("(f 1 2)")
  assert_true(
    call
    is Apply(
      _,
      Apply(_, Variable(_, f), Literal(_, IntegerLiteral("1"))),
      Literal(_, IntegerLiteral("2"))
    ) &&
    f.to_canonical() == "f",
  )
  let sum = @frontend.compile_expression("(+ 1 2 3)")
  assert_true(
    sum
    is Apply(
      _,
      Apply(
        _,
        Reference(_, outer),
        Apply(_, Apply(_, Reference(_, inner), _), _)
      ),
      Literal(_, IntegerLiteral("3"))
    ) &&
    outer == add &&
    inner == add,
  )
  let primitive = @frontend.compile_expression("+")
  assert_true(primitive is Reference(_, name) && name == add)
  let negate = @frontend.compile_expression("(- 5)")
  assert_true(
    negate
    is Apply(
      _,
      Apply(_, Reference(_, subtract), Literal(_, IntegerLiteral("0"))),
      Literal(_, IntegerLiteral("5"))
    ) &&
    subtract.to_canonical() == "morphir/SDK:basics#subtract",
  )
  let reciprocal = @frontend.compile_expression("(/ 4)")
  assert_true(
    reciprocal
    is Apply(
      _,
      Apply(_, Reference(_, divide), Literal(_, IntegerLiteral("1"))),
      Literal(_, IntegerLiteral("4"))
    ) &&
    divide.to_canonical() == "morphir/SDK:basics#divide",
  )
  assert_true(
    @frontend.compile_expression("(+)") is Literal(_, IntegerLiteral("0")),
  )
  assert_true(
    @frontend.compile_expression("(*)") is Literal(_, IntegerLiteral("1")),
  )
  assert_true(
    @frontend.compile_expression("(string-append)")
    is Literal(_, StringLiteral("")),
  )
  let lambda = @frontend.compile_expression("(lambda (x y) x)")
  assert_true(
    lambda
    is Lambda(
      _,
      AsPattern(_, WildcardPattern(_), x),
      Lambda(_, AsPattern(_, WildcardPattern(_), y), Variable(_, body))
    ) &&
    x.to_canonical() == "x" &&
    y.to_canonical() == "y" &&
    body == x,
  )
  let condition = @frontend.compile_expression("(if #t 1 2)")
  assert_true(condition is IfThenElse(_, Literal(_, BoolLiteral(true)), _, _))
  let sequence = @frontend.compile_expression("(begin 1 2)")
  assert_true(
    sequence
    is LetDefinition(
      _,
      temporary,
      ExpressionBody([], _, Literal(_, IntegerLiteral("1"))),
      Literal(_, IntegerLiteral("2"))
    ) &&
    temporary.to_canonical() == "scheme-temporary-0",
  )
  assert_true(@frontend.compile_expression("(begin)") is Unit(_))
  let simultaneous = @frontend.compile_expression("(let ((x 6)) x)")
  assert_true(
    simultaneous
    is LetDefinition(
      _,
      temporary,
      _,
      LetDefinition(
        _,
        x,
        ExpressionBody(_, _, Variable(_, read)),
        Variable(_, _)
      )
    ) &&
    read == temporary &&
    x.to_canonical() == "x",
  )
  let bound = @frontend.compile_expression("(let ((f (lambda (x) x))) f)")
  assert_true(
    bound
    is LetDefinition(
      _,
      temporary,
      ExpressionBody([(x, _)], _, Variable(_, _)),
      LetDefinition(_, f, ExpressionBody([], _, Variable(_, read)), _)
    ) &&
    x.to_canonical() == "x" &&
    f.to_canonical() == "f" &&
    read == temporary,
  )
  let sequential = @frontend.compile_expression("(let* ((x 1) (y x)) y)")
  assert_true(
    sequential
    is LetDefinition(
      _,
      x,
      _,
      LetDefinition(_, y, ExpressionBody(_, _, Variable(_, read)), _)
    ) &&
    x.to_canonical() == "x" &&
    y.to_canonical() == "y" &&
    read == x,
  )
  let recursive = @frontend.compile_expression(
    "(letrec ((f (lambda (n) n))) (f 1))",
  )
  assert_true(
    recursive is LetRecursion(_, definitions, Apply(_, _, _)) &&
    definitions.get(@ir.Name::parse("f"))
    is Some(ExpressionBody([(n, _)], _, _)) &&
    n.to_canonical() == "n",
  )
  assert_true(
    @frontend.compile_expression("(list 1 \"a\")")
    is List(
      _,
      [Literal(_, IntegerLiteral("1")), Literal(_, StringLiteral("a"))]
    ),
  )
  assert_true(
    @frontend.compile_expression("'(1 2)")
    is List(
      _,
      [Literal(_, IntegerLiteral("1")), Literal(_, IntegerLiteral("2"))]
    ),
  )
  assert_true(@frontend.compile_expression("'()") is List(_, []))
  assert_true(
    @frontend.compile_expression("(user:util#inc 41)")
    is Apply(_, Reference(_, inc), _) &&
    inc.to_canonical() == "user:util#inc",
  )
}
```

## Literals and their types

| Scheme | IR literal | Type in a signature |
| --- | --- | --- |
| `#t`, `#f` | `BoolLiteral` | `morphir/SDK:basics#bool` |
| An exact integer, such as `42` | `IntegerLiteral`, holding its digits at any size | `morphir/SDK:basics#int` |
| An inexact real, such as `2.5` or `1e3` | `FloatLiteral` | `morphir/SDK:basics#float` |
| A string | `StringLiteral` | `morphir/SDK:string#string` |
| A character | `CharLiteral` | `morphir/SDK:char#char` |
| A quoted proper list | `List` of literals | a placeholder |

The type column is the type the frontend writes in a signature whose body is the literal, as `result_type` gives it.
An integer literal also carries `morphir/SDK:basics#int` as its inferred type, because Scheme integers are exact.

```mbt check
///|
test "a literal gives its definition a concrete type" {
  let file = @frontend.compile_file("(define answer 42) (define pi 3.14)")
  guard file.distribution is Library(_, _, definition) else { fail("library") }
  guard definition.modules.get(@ir.Path::parse("main")) is Some(module_) else {
    fail("module")
  }
  let int = @ir.FQName::parse("morphir/SDK:basics#int")
  let float = @ir.FQName::parse("morphir/SDK:basics#float")
  guard module_.value.values.get(@ir.Name::parse("answer"))
    is Some({ value: { value: ExpressionBody([], output, body), .. }, .. }) else {
    fail("answer")
  }
  assert_true(output is Reference(_, name, []) && name == int)
  assert_true(
    body is Literal(attributes, IntegerLiteral("42")) &&
    attributes.inferred_type is Some(Reference(_, name, [])) &&
    name == int,
  )
  guard module_.value.values.get(@ir.Name::parse("pi"))
    is Some({ value: { value: ExpressionBody([], output, _), .. }, .. }) else {
    fail("pi")
  }
  assert_true(output is Reference(_, name, []) && name == float)
}
```

Integers and reals are different Morphir types.
An integer literal is always an `Int`, so arithmetic on Floats needs decimal literals.
Write `(* 2.5 2.0)`, not `(* 2.5 2)`.

```scheme
(* 2.5 2.0)
;; => 5.0
```

```scheme
(* 2.5 2)
;; error: morphir/SDK:basics#multiply: incompatible numeric operands
```

[Inference](#type-placeholders-and-inference) with `fill` refuses it too, with `type_mismatch`: expected `Float`, found
`Int`.

Decimal literals are not enough for a one-argument `-`.
The frontend subtracts the argument from the integer literal `0`, so negating a Float mixes an `Int` and a Float.
This is current behaviour, and bead `morphir-ukvn.5.49` tracks it.
Write `(- 0.0 x)` to negate a Float.

```scheme
(- 2.5)
;; error: morphir/SDK:basics#subtract: incompatible numeric operands
```

```scheme
(- 0.0 2.5)
;; => -2.5
```

## Qualified references

A name of the form `package:module#name` is a qualified reference.
It lowers to `Reference` with that fully qualified name, unless a local binding has the same name.
A qualified reference to the Morphir SDK runs directly.

```scheme
(morphir/SDK:basics#add 40 2)
;; => 42
```

A qualified reference to another module compiles, but running it needs that module.
Linking several files is described in [Running Morphir IR](../backend/README.mbt.md).

```scheme
(user:util#inc 41)
;; error: Unbound identifier: r:user:util#inc
```

In a project, a later file can call a definition of an earlier file by its qualified reference.
The first file is module `util` of package `user`, so its `inc` is `user:util#inc`.

```scheme
;; file: src/util.scm
(define (inc x) (+ x 1))
```

```scheme
;; file: src/main.scm
(user:util#inc 41)
;; => 42
```

A reference needs all three parts.
A name such as `module#name`, with no package, is refused with the name error.

```scheme
(util#inc 41)
;; error: finos/morphir-ir/common.NameError.InvalidName
```

## Type placeholders and inference

Scheme source states no types, so most positions in a signature have no type the frontend can write.
`compile_file` writes each such position as a type variable named `t-<n>` with the unknown marker.
The marker is the type attribute extension `morphir.inference` with the value `unknown`.
It tells inference that the variable may be solved to any type.
Each position gets its own variable.
The numbering starts at 0 in each definition and runs through its inputs, then its output, then the signatures of the
`let` definitions in its body, in order.

```mbt check
///|
test "compile_file numbers the placeholders of a signature" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1))")
  guard file.distribution is Library(_, _, definition) else { fail("library") }
  guard definition.modules.get(@ir.Path::parse("main")) is Some(module_) else {
    fail("module")
  }
  guard module_.value.values.get(@ir.Name::parse("inc"))
    is Some(
      { value: { value: ExpressionBody([(x, input)], output, _), .. }, .. }
    ) else {
    fail("inc")
  }
  inspect(x.to_canonical(), content="x")
  assert_true(
    input is Variable(attributes, name) &&
    attributes.is_unknown() &&
    name.to_canonical() == "t-0",
  )
  assert_true(
    output is Variable(attributes, name) &&
    attributes.is_unknown() &&
    name.to_canonical() == "t-1",
  )
}
```

The engine solves the placeholders when `pipeline.inference` is set to `"fill"`, in `morphir.toml` or with
`(inference "fill")` in a `pipeline` script.
`fill` writes the solved types into the IR, and `check` checks the IR without changing it.
The settings are described in the engine's [Type inference](../../morphir-engine/README.md#type-inference) section.

> **Planned.** Bead `morphir-ukvn.5.22.8` will lower a name that refers to a top-level definition of the same module to
> `Reference` with its fully qualified name, and will keep `Variable` for local names.
> Today the frontend lowers that name to `Variable`.
> A call from one top-level definition to another, or a definition that calls itself, therefore fails `fill` and
> `check` with `unknown_reference`, for example `inc is not defined`.
> Running the file is not affected.

```mbt check
///|
test "a call to another top-level definition is a variable today" {
  let file = @frontend.compile_file(
    "(define (inc x) (+ x 1)) (define (twice x) (inc (inc x)))",
  )
  guard file.distribution is Library(_, _, definition) else { fail("library") }
  guard definition.modules.get(@ir.Path::parse("main")) is Some(module_) else {
    fail("module")
  }
  guard module_.value.values.get(@ir.Name::parse("twice"))
    is Some({ value: { value: ExpressionBody(_, _, body), .. }, .. }) else {
    fail("twice")
  }
  assert_true(
    body is Apply(_, Variable(_, inc), _) && inc.to_canonical() == "inc",
  )
}
```

## What the frontend rejects

Morphir IR is functional, and every Morphir function takes exactly one argument.
The frontend rejects the forms that have no direct Morphir equivalent.

| Rejected | Message | Why |
| --- | --- | --- |
| `set!` | `Unsupported: Cannot lower set! to functional Morphir IR` | Morphir IR has no mutation |
| `define` inside an expression, `define-syntax`, `quasiquote` | `Unsupported: Cannot lower <form> to functional Morphir IR` | They have no functional equivalent; only leading definitions of a file are accepted |
| A lambda with no parameter | `Unsupported: Morphir lambdas require a parameter; use unit explicitly` | A Morphir lambda takes one argument |
| A call with no argument | `Unsupported: Zero-argument calls require explicit unit in Morphir` | A Morphir application passes one argument |
| A named `let` | `Expected proper syntax list` | The frontend has no loop form; use `letrec` |
| An exact rational literal | `Unsupported: Exact rational literals have no direct Morphir literal` | Morphir has no rational literal |
| A vector, a quoted symbol or a quoted dotted list | `Unsupported: Quoted symbols, vectors and improper lists cannot be lowered to Morphir literals` | Morphir has no literal for them |
| Forms nested too deep | `Limit exceeded: Frontend depth` | The frontend stops at 256 nested lowering steps |

```scheme
(let ((x 1)) (set! x 2) x)
;; error: Unsupported: Cannot lower set! to functional Morphir IR
```

```scheme
(lambda () 1)
;; error: Unsupported: Morphir lambdas require a parameter; use unit explicitly
```

```scheme
(define (f x) x)
(f)
;; error: Unsupported: Zero-argument calls require explicit unit in Morphir
```

```scheme
(let loop ((n 3)) n)
;; error: Expected proper syntax list
```

The message for a named `let` is a placeholder; bead `morphir-ukvn.5.46` tracks a clear error for it.

```scheme
(+ 1/2 1/2)
;; error: Unsupported: Exact rational literals have no direct Morphir literal
```

```scheme
#(1 2)
;; error: Unsupported: Quoted symbols, vectors and improper lists cannot be lowered to Morphir literals
```

```scheme
(quote (a b))
;; error: Unsupported: Quoted symbols, vectors and improper lists cannot be lowered to Morphir literals
```

The depth limit counts nested lowering steps, not lists.
Each `begin` takes two steps, so 130 nested `begin` forms pass the limit and stay under the reader's limit of 256
nested lists.

```mbt check
///|
test "deep nesting reaches the frontend depth limit" {
  let source = "(begin ".repeat(130) + "1" + ")".repeat(130)
  let message = try {
    ignore(@frontend.compile_expression(source))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Limit exceeded: Frontend depth")
}
```
