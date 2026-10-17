# Morphir Scheme

An embeddable Scheme dialect for writing Morphir transforms and executing Morphir IR.
It runs on MoonBit's `wasm`, `wasm-gc`, `js` and `native` targets.
This chapter is the index and the reference for the core language and its embedding. The other chapters cover
compiling Scheme to Morphir IR, running Morphir IR, transform scripts and the specification notation.

Chapters: index (this page) · next: [Writing models](frontend/README.mbt.md)

| Chapter | Covers |
| --- | --- |
| [Morphir Scheme](README.mbt.md) | The language, its limits and embedding a runtime |
| [Writing models](frontend/README.mbt.md) | Compiling Scheme to Morphir IR |
| [Running Morphir IR](backend/README.mbt.md) | Evaluating and emitting IR, externals, linking, the symbols sidecar |
| [Transform scripts](pipeline/README.mbt.md) | Scripts as `IRFile -> IRFile` procedures |
| [Specification notation](spec/README.mbt.md) | Package specifications as data |

## Overview

Morphir Scheme has two jobs.
Transform scripts written in it read and rewrite Morphir IR.
Morphir IR compiled to it runs in the same interpreter.

The separation of reader, evaluator and runtime takes inspiration from
[bobzhang/scheme-r6rs](https://mooncakes.io/docs/bobzhang/scheme-r6rs) and its
[MoonBit implementation](https://github.com/bobzhang/moonbit-scheme-r6rs).
This is an independent implementation of a specialized subset, not an R6RS implementation.
This chapter describes what the language does today, and says where a form or procedure differs from R6RS.
A difference that is a known deviation names bead `morphir-ukvn.5.48`, which tracks its fix; the others are by design.

Declare `finos/morphir-scheme@0.1.0` in your module and import the packages you need.
The MoonBit examples in these chapters use the aliases `scheme`, `frontend`, `backend`, `pipeline` and `ir`.

| Import | Responsibility |
| --- | --- |
| `finos/morphir-scheme` | Reader, runtime values, lexical evaluation and host procedures |
| `finos/morphir-scheme/frontend` | Scheme expressions and files → current Morphir IR |
| `finos/morphir-scheme/backend` | Morphir IR → executable Scheme; runtime support |
| `finos/morphir-scheme/pipeline` | Scripted IR transforms, JSON bridge and bottom-up traversal |
| `finos/morphir-scheme/spec` | The specification notation ([see the chapter](spec/README.mbt.md)) ↔ `@ir.PackageSpecification` |

[`morphir-engine`](../morphir-engine/README.md) provides file discovery, manifests,
configuration, frontend/backend registration, artifacts and diagnostics.

Compiling Scheme to Morphir IR is described in [Writing models](frontend/README.mbt.md), running it in
[Running Morphir IR](backend/README.mbt.md), and scripted IR transforms in [Transform scripts](pipeline/README.mbt.md).

Every `scheme` block in this chapter is a checked example.
Each block runs in a fresh `Runtime` and its last value is printed with `value_to_string`.
A `;; =>` line states the printed result.
A `;; error:` line states the start of the error message.

```scheme
(define (inc x) (+ x 1))
(inc 41)
;; => 42
```

## Lexical syntax

The reader turns source text into data before anything is evaluated.
A program is a sequence of data, separated by whitespace and comments.

| Datum | Written as | Notes |
| --- | --- | --- |
| List | `(a b c)` or `[a b c]` | A list closes with the delimiter that opened it |
| Dotted pair | `(a . b)`, `(a b . c)` | The dot needs at least one datum before it and exactly one after it |
| Quotation | `'datum` | Reads as `(quote datum)` |
| Vector | `#(a b c)` | |
| String | `"text"` | Escapes: `\n`, `\r`, `\t`, `\\`, `\"`, and a backslash before a vertical bar |
| Character | `#\a`, `#\space`, `#\newline`, `#\tab`, `#\return` | A delimiter such as `(` can follow `#\` directly |
| Escaped identifier | a name between vertical bars | Can hold spaces, delimiters and the same escapes as a string |
| Boolean | `#t`, `#true`, `#f`, `#false` | |
| Exact integer | `42`, `-7`, `+5` | Any size |
| Exact rational | `6/4` | Normalized: `6/4` reads as `3/2`, and `4/2` reads as `2` |
| Inexact real | `1.5`, `-0.25`, `1e3`, `2.5E-3` | JSON number syntax with an optional leading `+`; the literal must be finite |
| Symbol | any other token | |

Line comments start with `;` and run to the end of the line.
Block comments sit between `#|` and `|#`, and they nest.
A datum comment `#;` skips the next datum.

```scheme
#| outer #| inner |# |# #; (+ 9 9) '(1 . 2)
;; => (1 . 2)
```

Brackets read the same as parentheses.

```scheme
(let ([x 1] [y 2]) (+ x y))
;; => 3
```

Integers have arbitrary precision.

```scheme
(+ 18446744073709551616 1)
;; => 18446744073709551617
```

Rationals are exact and stay normalized.

```scheme
(+ 1/3 1/6)
;; => 1/2
```

An inexact real needs a digit before its point.
`.5` reads as a symbol, not a number.
This is a known deviation from R6RS, tracked by bead `morphir-ukvn.5.48`.

```scheme
(list 0.5 1e3 (symbol? '.5))
;; => (0.5 1000.0 #t)
```

Strings print with their escapes.

```scheme
"say \"hi\"\tthen go"
;; => "say \"hi\"\tthen go"
```

Characters print with their names.

```scheme
(list #\a #\( #\space #\newline)
;; => (#\a #\( #\space #\newline)
```

An escaped identifier reads as one symbol.

```scheme
(symbol->string '|two words|)
;; => "two words"
```

### Refused input

The table lists every `Syntax` error the reader raises.
Its message names the character offset where the reader stopped, counted from 0.

| Refused input | Message |
| --- | --- |
| The text ends inside a list | `Unclosed list` |
| A closing delimiter with no open list, or one that does not match the opening delimiter | `Unexpected closing delimiter` |
| A dot with nothing before it | `Dot requires a head` |
| More than one datum after a dot | `Expected closing delimiter after tail` |
| A vector written with a dot, such as `#(1 . 2)` | `Invalid vector` |
| The text ends inside a string or escaped identifier | `Unclosed quoted text` |
| The text ends right after a backslash inside a string or escaped identifier | `Unclosed escape` |
| An escape other than the six listed above | `Unsupported escape` |
| The text ends inside a block comment | `Unclosed block comment` |
| The text ends where a datum must follow: after a quotation, a datum comment or a dot | `Expected datum` |
| The text ends right after `#\` | `Expected character` |
| A character name other than the four listed above | `Expected one character` |
| A `#` token that is not a boolean, vector, character or comment, such as `#x10` | `Unknown reader token: #x10` |
| A token that starts with a digit but is not a number, such as `1abc` or `1.` | `Invalid numeric token` |
| Lists nested more than 256 deep | `Reader nesting limit` |

The rows about text that ends too early cannot be `scheme` examples.
An example's `;; error:` line is part of its text, so the text never ends where the row needs it to.
This test reads each such input directly.

```mbt check
///|
test "the reader refuses text that ends too early" {
  for
    refusal in [
      ("(1 2", "Syntax at character 4: Unclosed list"),
      ("\"abc", "Syntax at character 4: Unclosed quoted text"),
      ("\"a\\", "Syntax at character 3: Unclosed escape"),
      ("#| open", "Syntax at character 7: Unclosed block comment"),
      ("'", "Syntax at character 1: Expected datum"),
      ("#;", "Syntax at character 2: Expected datum"),
      ("(1 .", "Syntax at character 4: Expected datum"),
      ("#\\", "Syntax at character 2: Expected character"),
    ] {
    let (source, expected) = refusal
    let message = try {
      ignore(@scheme.parse_program(source))
      ""
    } catch {
      e => @scheme.error_message(e)
    }
    assert_eq(message, expected)
  }
}
```

```scheme
#(1 . 2)
;; error: Syntax at character 8: Invalid vector
```

```scheme
(1 . 2 3)
;; error: Syntax at character 7: Expected closing delimiter after tail
```

```scheme
#x10
;; error: Syntax at character 4: Unknown reader token: #x10
```

```scheme
"a\q"
;; error: Syntax at character 4: Unsupported escape
```

A backquote or a comma raises an `Unsupported` error, because quasiquotation is outside the language.
A number literal can also fail with an `Invalid` error: `1/0` raises `Division by zero`, and `1e400` raises
`Nonfinite number`.

```scheme
1/0
;; error: Division by zero
```

```scheme
1e400
;; error: Nonfinite number
```

## Values

| Value | Printed form | Example |
| --- | --- | --- |
| Exact integer | decimal digits | `42` |
| Exact rational | numerator `/` denominator | `1/2` |
| Inexact real | digits with a point or exponent | `2.5`, `1000.0` |
| Inexact real that is not finite | `NaN.0`, `Infinity.0` or `-Infinity.0` | made only by a host or by `evaluate` |
| Boolean | `#t` or `#f` | `#t` |
| Character | `#\` and the character or its name | `#\a`, `#\space` |
| String | between double quotes, with escapes | `"hi"` |
| Symbol | its name, between vertical bars when it needs escaping | `abc` |
| Empty list | `()` | `()` |
| Pair | a list, or a dotted list when the last tail is not the empty list | `(1 2)`, `(1 . 2)` |
| Vector | `#(` elements `)` | `#(1 2)` |
| Record | `#<record` key`=`value ... `>` | `#<record x=1>` |
| Tagged value | `#<` tag elements `>` | made by the backend for Morphir constructors |
| Unit | `#<unit>` | `#<unit>` |
| Procedure | `#<procedure>` | closures and host procedures |
| Morphir IR value, type or file | `#<morphir-value>`, `#<morphir-type>`, `#<morphir-file>` | made by host procedures |

Pairs, strings, records and vectors are immutable.
Values nested more than 256 deep cannot be printed: `value_to_string` raises `Limit exceeded: value printing depth`.

The reader, `string->number` and arithmetic never produce a real that is not finite.
A host procedure can return one, and so can the backend's `evaluate`, as listed in
[Two ways to run IR](backend/README.mbt.md#two-ways-to-run-ir).
Arithmetic on such a value raises `Nonfinite arithmetic result`.

```mbt check
///|
test "a host can return a real that is not finite" {
  let runtime = @scheme.Runtime::new()
  runtime.define_native("infinity", fn(_rt, _args) {
    @scheme.Value::Number(@scheme.Number::Real(1.0 / 0.0))
  })
  inspect(
    @scheme.value_to_string(runtime.eval("(infinity)")),
    content="Infinity.0",
  )
  let below = @scheme.Value::Number(@scheme.Number::Real(-1.0 / 0.0))
  inspect(@scheme.value_to_string(below), content="-Infinity.0")
  let nan = @scheme.Value::Number(@scheme.Number::Real(0.0 / 0.0))
  inspect(@scheme.value_to_string(nan), content="NaN.0")
  let message = try {
    ignore(runtime.eval("(+ (infinity) 1)"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Nonfinite arithmetic result")
}
```

### Truthiness

Only `#f` is false in the interpreter.
Every other value, including `0`, `()` and the empty string, is true.

```scheme
(if 0 'zero-is-true 'false)
;; => zero-is-true
```

### Equality

`equal?` compares two values by structure.

| Values | Equal when |
| --- | --- |
| Numbers | They have the same numeric value, whatever their exactness |
| Booleans, characters, strings, symbols | They have the same content |
| Empty lists, units | Always |
| Pairs, vectors | Their elements are equal, in order |
| Records | They have the same keys with equal values, in any order |
| Tagged values | They have the same tag and equal elements |
| Morphir IR values, types and files | They are equal as IR |
| Procedures | Never, not even a procedure and itself |
| Values of different kinds | Never |

Numbers compare by value, so `1` and `1.0` are equal; R6RS `equal?` says they are not.
Procedures are never equal; R6RS `equal?` says a procedure equals itself.
Both are known deviations, tracked by bead `morphir-ukvn.5.48`.
The language has no `eq?` or `eqv?`.

```scheme
(list (equal? 1 1.0) (equal? car car) (equal? '(1 #(2)) (list 1 (vector 2))))
;; => (#t #f #t)
```

## Special forms

A list whose head is one of these names is a special form, not a procedure call.

| Form | Syntax |
| --- | --- |
| `define` | `(define name expression)`, `(define (name parameter ...) body ...)` |
| `set!` | `(set! name expression)` |
| `lambda` | `(lambda (parameter ...) body ...)`, `(lambda (parameter ... . rest) body ...)`, `(lambda rest body ...)` |
| `if` | `(if test consequent alternative)` |
| `begin` | `(begin form ...)` |
| `and` | `(and form ...)` |
| `or` | `(or form ...)` |
| `let` | `(let ((name expression) ...) body ...)` |
| `let*` | `(let* ((name expression) ...) body ...)` |
| `letrec` | `(letrec ((name expression) ...) body ...)` |
| named `let` | `(let loop ((name expression) ...) body ...)` |
| `quote` | `(quote datum)` or `'datum` |

The evaluator recognizes a special form by its name before it looks up any binding.
A local binding named `if` therefore cannot be called as `(if ...)`.

```scheme
(let ((if (lambda (x) x))) (if 1))
;; error: if expects condition, consequent and alternative
```

### Evaluation and application

A symbol evaluates to its binding in the innermost scope that has one.
Numbers, strings, characters, booleans and vectors evaluate to themselves.
The elements of a vector literal are not evaluated.

```scheme
#(x (+ 1 2))
;; => #(x (+ 1 2))
```

Any other list is an application.
The evaluator evaluates the head, then the arguments from left to right, then calls the head with the arguments.

| Error | Message |
| --- | --- |
| A symbol has no binding | `Unbound identifier: name` |
| The list is empty | `Empty application` |
| The list is dotted | `Cannot evaluate an improper application` |
| The head is not a procedure | `Attempt to call a non-procedure` |

```scheme
(1 2)
;; error: Attempt to call a non-procedure
```

### define

`(define name expression)` evaluates the expression and binds the name in the current scope.
At the top level, the current scope is the session.
Inside a procedure or `let` body, it is that body's scope.
A second `define` of the same name in the same scope replaces the binding.
`(define (name parameter ...) body ...)` is short for `(define name (lambda (parameter ...) body ...))`, and a dotted
parameter list makes a variadic procedure.
The value of a `define` form is unit.

| Error | Message |
| --- | --- |
| Fewer than two parts after `define` | `define expects name and value` |
| More than one expression after a name | `define expects one value` |
| A target that is neither a symbol nor a non-empty list | `Invalid definition` |
| A procedure name that is not a symbol | `Expected identifier` |

```scheme
(define (square x) (* x x))
(square 7)
;; => 49
```

```scheme
(define answer 42)
;; => #<unit>
```

### set!

`(set! name expression)` evaluates the expression and assigns it to the innermost existing binding of the name.
The value of a `set!` form is unit.

| Error | Message |
| --- | --- |
| No binding of the name exists | `Unbound identifier: name` |
| The name is a `letrec` binding that is not yet initialized | `Uninitialized recursive binding: name` |
| Anything other than a name and one expression | `set! expects name and value` |

```scheme
(define count 0)
(set! count (+ count 1))
count
;; => 1
```

```scheme
(set! missing 1)
;; error: Unbound identifier: missing
```

### lambda

`lambda` makes a closure that captures the scope where it is evaluated.
A call binds the parameters to the arguments in a new scope, then evaluates the body forms in order.
The value of the call is the value of the last body form.
With a dotted parameter list, the rest parameter receives a list of the extra arguments.
With a single symbol instead of a list, that symbol receives a list of all the arguments.

| Error | Message |
| --- | --- |
| No body | `lambda expects parameters and body` |
| A repeated parameter | `Duplicate parameter: name` |
| A rest parameter that repeats a parameter | `Duplicate rest parameter: name` |
| Parameters that are neither a symbol nor a list | `Invalid lambda formals` |
| A parameter that is not a symbol | `Expected identifier` |
| A call with the wrong number of arguments | `Procedure argument count mismatch` |
| A call from another session | `Closure belongs to another runtime` |

```scheme
(define (make-adder x) (lambda (y) (+ x y)))
((make-adder 10) 32)
;; => 42
```

```scheme
((lambda (a . rest) rest) 1 2 3)
;; => (2 3)
```

```scheme
((lambda args args) 1 2)
;; => (1 2)
```

```scheme
((lambda (x) x))
;; error: Procedure argument count mismatch
```

### if

`(if test consequent alternative)` evaluates the test.
If the test is true, the form's value is the consequent's value; otherwise it is the alternative's value.
The alternative is required: R6RS allows `if` without one, and this language does not.

| Error | Message |
| --- | --- |
| Anything other than three parts after `if` | `if expects condition, consequent and alternative` |

```scheme
(if (< 1 2) 'yes 'no)
;; => yes
```

```scheme
(if #t 1)
;; error: if expects condition, consequent and alternative
```

### begin

`(begin form ...)` evaluates the forms in order, and its value is the last form's value.
`(begin)` has the value unit.
`begin` does not open a scope, so a `define` inside it binds in the enclosing scope.
It raises no error of its own.

```scheme
(begin (define x 1) (+ x 1))
;; => 2
```

```scheme
(begin)
;; => #<unit>
```

### and and or

`and` evaluates its forms from left to right and stops at the first false value, which is its value.
If no form is false, the value of `and` is the last form's value, and `(and)` is `#t`.
`or` evaluates its forms from left to right and stops at the first true value, which is its value.
If no form is true, the value of `or` is `#f`, and `(or)` is `#f`.
Neither raises an error of its own.

```scheme
(list (and 1 2 3) (and 1 #f 3) (or #f 'b) (and) (or))
;; => (3 #f b #t #f)
```

### let, let* and letrec

`let` evaluates every expression in the enclosing scope, from left to right.
It then binds the names in a new scope and evaluates the body there.

```scheme
(let ((x 1)) (let ((x 2) (y x)) y))
;; => 1
```

`let*` evaluates each expression in a scope that holds the bindings before it.
A name can repeat, and the later binding shadows the earlier one.

```scheme
(let* ((x 1) (x (+ x 1))) x)
;; => 2
```

`letrec` puts every name in scope for every expression, so its procedures can call each other.

```scheme
(letrec ((even? (lambda (n) (if (= n 0) #t (odd? (- n 1)))))
         (odd? (lambda (n) (if (= n 0) #f (even? (- n 1))))))
  (even? 10))
;; => #t
```

A `letrec` name cannot be read until every expression of the form has been evaluated.
Reading or assigning it earlier raises an error.
This applies to a binding whose own expression has already finished too: `(letrec ((a 1) (b a)) b)` fails.

```scheme
(letrec ((a b) (b 1)) a)
;; error: Uninitialized recursive binding: b
```

| Error | Message |
| --- | --- |
| No body | `let expects bindings and body` |
| Bindings that are not a list | `Expected proper syntax list` |
| A binding that is not a name and one expression | `Binding expects name and expression` |
| A binding name that is not a symbol | `Expected identifier` |
| A repeated name in `let` or `letrec` | `Duplicate binding: name` |
| An early read of a `letrec` name | `Uninitialized recursive binding: name` |

```scheme
(let ((x 1) (x 2)) x)
;; error: Duplicate binding: x
```

### Named let

`(let loop ((name expression) ...) body ...)` binds `loop` to a procedure with the given parameters, visible in its own
body.
It then calls that procedure with the values of the expressions, which are evaluated in the enclosing scope.
A call to `loop` in tail position runs in constant host stack.
The errors are those of `let`, and a named `let` without a body raises `Named let expects body`.

```scheme
(let loop ((n 10000) (sum 0))
  (if (= n 0) sum (loop (- n 1) (+ sum 1))))
;; => 10000
```

### quote

`(quote datum)` and `'datum` have the datum itself as their value, without evaluating it.
A quoted list becomes pairs, and a quoted symbol becomes a symbol.

| Error | Message |
| --- | --- |
| Anything other than one datum after `quote` | `quote expects one datum` |

```scheme
(list '(a b . c) (quote (+ 1 2)))
;; => ((a b . c) (+ 1 2))
```

## Built-in procedures

Every session starts with the procedures in these tables.
Each row gives the arguments, the result and an example.
The block after each table runs the table's examples and prints their results as one list.
A procedure with a fixed number of arguments raises `name: expected N arguments` when it receives another number, for
example `car: expected 1 arguments`.
The plural for one argument is a known defect, tracked by bead `morphir-ukvn.5.48`.

### Arithmetic

A result is exact when every argument is exact.
A result is inexact when any argument is inexact.
An exact rational result is normalized, and a rational with denominator 1 becomes an integer.

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `+` | zero or more numbers | their sum; `0` with no arguments | `(+ 1 2 3)` → `6` |
| `-` | one or more numbers | the first minus the rest; the negation of a single argument | `(- 10 4 1)` → `5` |
| `*` | zero or more numbers | their product; `1` with no arguments | `(* 2 3 4)` → `24` |
| `/` | one or more numbers | the first divided by the rest; the reciprocal of a single argument | `(/ 1 3)` → `1/3` |
| `quotient` | two exact integers | the quotient, truncated toward zero | `(quotient -7 2)` → `-3` |
| `remainder` | two exact integers | the remainder, with the sign of the first argument | `(remainder -7 2)` → `-1` |
| `number?` | one value | `#t` for any number | `(number? 1/2)` → `#t` |
| `integer?` | one value | `#t` for an exact integer | `(integer? 2.0)` → `#f` |

```scheme
(list (+ 1 2 3) (- 10 4 1) (* 2 3 4) (/ 1 3) (quotient -7 2) (remainder -7 2) (number? 1/2) (integer? 2.0))
;; => (6 5 24 1/3 -3 -1 #t #f)
```

```scheme
(list (+ 1 0.5) (* 2 1.0) (- 5) (/ 6 4))
;; => (1.5 2.0 -5 3/2)
```

`integer?` is `#f` for an inexact real with an integral value, such as `2.0`; R6RS says it is `#t`.
This is a known deviation, tracked by bead `morphir-ukvn.5.48`.

| Raised when | Message |
| --- | --- |
| An argument is not a number | `Expected number` |
| A call to `-` or `/` has no arguments | `- needs an operand`, `/ needs an operand` |
| A divisor is zero, exact or inexact | `Division by zero` |
| An inexact result overflows | `Nonfinite arithmetic result` |
| An exact integer is too large to convert to an inexact real | `Inexact conversion overflow` |
| An argument of `quotient` or `remainder` is a rational or a real | `Expected exact integers` |

```scheme
(/ 1 0)
;; error: Division by zero
```

### Comparison

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `=` | two or more numbers | `#t` when all are equal | `(= 1 1.0)` → `#t` |
| `<` | two or more numbers | `#t` when each is less than the next | `(< 1 2 3)` → `#t` |
| `>` | two or more numbers | `#t` when each is greater than the next | `(> 3 2 2)` → `#f` |
| `<=` | two or more numbers | `#t` when each is at most the next | `(<= 1 1 2)` → `#t` |
| `>=` | two or more numbers | `#t` when each is at least the next | `(>= 3 1 2)` → `#f` |
| `equal?` | two values | `#t` when they are equal by structure (see [Equality](#equality)) | `(equal? '(1 (2)) '(1 (2)))` → `#t` |

```scheme
(list (= 1 1.0) (< 1 2 3) (> 3 2 2) (<= 1 1 2) (>= 3 1 2) (equal? '(1 (2)) '(1 (2))))
;; => (#t #t #f #t #f #t)
```

A comparison checks every argument, even after it has found a false result.

| Raised when | Message |
| --- | --- |
| A numeric comparison has fewer than two arguments | `Comparison needs at least two operands` |
| An argument of a numeric comparison is not a number | `Expected number` |

```scheme
(< 2 1 'x)
;; error: Expected number
```

### Lists

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `cons` | two values | a pair of them | `(cons 1 2)` → `(1 . 2)` |
| `car` | a pair | its first part | `(car '(1 2))` → `1` |
| `cdr` | a pair | its second part | `(cdr '(1 2))` → `(2)` |
| `list` | zero or more values | a list of them | `(list 1 2)` → `(1 2)` |
| `null?` | one value | `#t` for the empty list | `(null? '())` → `#t` |
| `pair?` | one value | `#t` for a pair | `(pair? '())` → `#f` |
| `list?` | one value | `#t` for a proper list | `(list? '(1 . 2))` → `#f` |
| `length` | a proper list | its number of elements | `(length '(1 2 3))` → `3` |
| `append` | zero or more proper lists, then any value | the lists joined, ending in the last argument | `(append '(1) '(2 3))` → `(1 2 3)` |
| `reverse` | a proper list | its elements in reverse order | `(reverse '(1 2 3))` → `(3 2 1)` |

```scheme
(list (cons 1 2) (car '(1 2)) (cdr '(1 2)) (list 1 2) (null? '()) (pair? '()) (list? '(1 . 2)) (length '(1 2 3)) (append '(1) '(2 3)) (reverse '(1 2 3)))
;; => ((1 . 2) 1 (2) (1 2) #t #f #f 3 (1 2 3) (3 2 1))
```

`append` shares its last argument as the tail of the result, so the last argument does not have to be a list.

```scheme
(list (append) (append '(1) 2))
;; => (() (1 . 2))
```

| Raised when | Message |
| --- | --- |
| The argument of `car` or `cdr` is not a pair | `Expected pair` |
| The argument of `length` or `reverse`, or an argument of `append` before the last, is not a proper list | `Expected proper list` |

```scheme
(car '())
;; error: Expected pair
```

### Higher-order

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `map` | a procedure and one proper list | a list of the procedure's results for each element, in order | `(map (lambda (x) (* x x)) '(1 2 3))` → `(1 4 9)` |
| `fold-left` | a procedure, an initial value and a proper list | the procedure applied from the left: `(f (f init a) b)` | `(fold-left - 0 '(1 2 3))` → `-6` |
| `apply` | a procedure, zero or more values, then a proper list | the procedure's result for the values followed by the list's elements | `(apply + 1 '(2 3))` → `6` |
| `procedure?` | one value | `#t` for a closure or a host procedure | `(procedure? car)` → `#t` |

```scheme
(list (map (lambda (x) (* x x)) '(1 2 3)) (fold-left - 0 '(1 2 3)) (apply + 1 '(2 3)) (procedure? car))
;; => ((1 4 9) -6 6 #t)
```

`map` takes exactly one list; R6RS `map` takes one or more.

| Raised when | Message |
| --- | --- |
| A call to `map` has more than one list | `map: expected 2 arguments` |
| The procedure argument is not a procedure | `Expected procedure` |
| The list argument is not a proper list | `Expected proper list` |
| A call to `apply` has fewer than two arguments | `apply needs a procedure and list` |

```scheme
(map (lambda (x y) x) '(1 2) '(3 4))
;; error: map: expected 2 arguments
```

### Strings

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `string-append` | zero or more strings | the strings joined | `(string-append "ab" "cd")` → `"abcd"` |
| `string=?` | two strings | `#t` when they are the same | `(string=? "a" "a")` → `#t` |
| `string?` | one value | `#t` for a string | `(string? 'a)` → `#f` |

```scheme
(list (string-append "ab" "cd") (string=? "a" "a") (string? 'a))
;; => ("abcd" #t #f)
```

| Raised when | Message |
| --- | --- |
| An argument of `string-append` or `string=?` is not a string | `Expected string` |

```scheme
(string-append "a" 1)
;; error: Expected string
```

### Symbols and conversion

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `symbol?` | one value | `#t` for a symbol | `(symbol? 'a)` → `#t` |
| `symbol->string` | a symbol | its name | `(symbol->string 'abc)` → `"abc"` |
| `string->symbol` | a string | the symbol with that name | `(string->symbol "abc")` → `abc` |
| `number->string` | a number | its printed form | `(number->string 1/3)` → `"1/3"` |
| `string->number` | a string | the number the reader reads from it, or `#f` | `(string->number "2.5")` → `2.5` |

```scheme
(list (symbol? 'a) (symbol->string 'abc) (string->symbol "abc") (number->string 1/3) (string->number "2.5"))
;; => (#t "abc" abc "1/3" 2.5)
```

`string->symbol` accepts any string, and the result prints escaped when it needs to be.

```scheme
(string->symbol "two words")
;; => |two words|
```

`string->number` gives `#f` for text that is not a number.

```scheme
(string->number "ten")
;; => #f
```

| Raised when | Message |
| --- | --- |
| The argument of `symbol->string` is not a symbol | `Expected symbol` |
| The argument of `string->symbol` or `string->number` is not a string | `Expected string` |
| The argument of `number->string` is not a number | `Expected number` |
| The text given to `string->number` is a real that is not finite | `Nonfinite number` |
| The text given to `string->number` is a rational with denominator zero | `Division by zero` |

`string->number` raises an error for `"1e400"` and `"1/0"` instead of giving `#f`.
This is a known deviation from R6RS, tracked by bead `morphir-ukvn.5.48`.

```scheme
(string->number "1/0")
;; error: Division by zero
```

### Records

A record maps string keys to values.
Records are immutable: `record-set` makes a new record.
A record keeps its keys in the order they were added.

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `record` | zero or more pairs, each with a string key | a record of those fields | `(record (cons "x" 1))` → `#<record x=1>` |
| `record-ref` | a record and a key | the field's value | `(record-ref (record (cons "x" 1)) "x")` → `1` |
| `record-set` | a record, a key and a value | a new record with the field set, or added at the end | `(record-set (record (cons "x" 1)) "x" 2)` → `#<record x=2>` |
| `record-keys` | a record | a list of its keys | `(record-keys (record (cons "x" 1) (cons "y" 2)))` → `("x" "y")` |

```scheme
(list (record (cons "x" 1)) (record-ref (record (cons "x" 1)) "x") (record-set (record (cons "x" 1)) "x" 2) (record-keys (record (cons "x" 1) (cons "y" 2))))
;; => (#<record x=1> 1 #<record x=2> ("x" "y"))
```

```scheme
(define point (record (cons "x" 1)))
(define moved (record-set point "y" 2))
(list point moved)
;; => (#<record x=1> #<record x=1 y=2>)
```

| Raised when | Message |
| --- | --- |
| An argument of `record` is not a pair with a string key | `record expects pairs with string keys` |
| Two arguments of `record` have the same key | `Duplicate record field: key` |
| The first argument of `record-ref`, `record-set` or `record-keys` is not a record | `Expected record` |
| The key is not a string | `Expected string` |
| The key given to `record-ref` is not in the record | `Missing record field` |

```scheme
(record-ref (record (cons "x" 1)) "y")
;; error: Missing record field
```

### Vectors

Vectors are immutable, and indexes start at 0.

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `vector` | zero or more values | a vector of them | `(vector 1 2)` → `#(1 2)` |
| `vector-ref` | a vector and an exact integer index | the element at the index | `(vector-ref #(a b c) 1)` → `b` |
| `vector-length` | a vector | its number of elements | `(vector-length #(a b c))` → `3` |

```scheme
(list (vector 1 2) (vector-ref #(a b c) 1) (vector-length #(a b c)))
;; => (#(1 2) b 3)
```

| Raised when | Message |
| --- | --- |
| The arguments of `vector-ref` are not a vector and an exact integer | `Expected vector and integer` |
| The index is negative or not less than the length | `Vector index out of range` |
| The argument of `vector-length` is not a vector | `Expected vector` |

```scheme
(vector-ref #(a b c) 3)
;; error: Vector index out of range
```

### Other

| Procedure | Arguments | Result | Example |
| --- | --- | --- | --- |
| `not` | one value | `#t` for `#f`, and `#f` for any other value | `(not 0)` → `#f` |
| `boolean?` | one value | `#t` for a boolean | `(boolean? #f)` → `#t` |
| `unit` | none | the unit value | `(unit)` → `#<unit>` |
| `error` | zero or more values | raises an `Invalid` error and never returns | `(error "Not found:" 'key)` raises `"Not found:" key` |

```scheme
(list (not 0) (boolean? #f) (unit))
;; => (#f #t #<unit>)
```

The message of `error` is its arguments printed with `value_to_string` and joined by spaces.
A string argument keeps its quotes in the message; R6RS `error` shows the message string without quotes.
This is a known deviation, tracked by bead `morphir-ukvn.5.48`.

```scheme
(error "Not found:" 'key)
;; error: "Not found:" key
```

## Errors

Every failure raises a `SchemeError`.
The reader raises on bad text before any form of the program runs.
The evaluator raises while it runs, and definitions made before the error stay in the session.
The language has no way to catch an error, so it always reaches the host.
`error_message(error)` turns an error into the message shown in this chapter.

| Kind | Raised for | `error_message` gives |
| --- | --- | --- |
| `Syntax(message, offset)` | Text the reader refuses | `Syntax at character offset: message` |
| `Unbound(name)` | A name with no binding | `Unbound identifier: name` |
| `Invalid(message)` | A wrong form, a wrong argument or the `error` procedure | `message` |
| `Unsupported(message)` | A feature outside the language | `Unsupported: message` |
| `Limit(resource)` | An exhausted limit or a cancelled run | `Limit exceeded: resource` |
| `Domain(domain, message)` | A domain failure raised by another package | `message` |
| `Stage(stage, message)` | A failure in a named pipeline stage, raised by another package | `stage: message` |

```scheme
(define x 1) (car x))
;; error: Syntax at character 20: Unexpected closing delimiter
```

```scheme
undefined-name
;; error: Unbound identifier: undefined-name
```

```scheme
(car 1)
;; error: Expected pair
```

```scheme
`(1 ,x)
;; error: Unsupported: Quasiquotation is not in the Morphir Scheme core
```

```scheme
(define (deep n) (+ 1 (deep n)))
(deep 0)
;; error: Limit exceeded: evaluation depth
```

## Limits

`Limits` bounds evaluation steps, recursive evaluation depth and allocated
lexical frames. Defaults are 1,000,000 steps, depth 256 and 100,000 frames.
Each public evaluation/call starts a step budget; nested host callbacks share it.
Direct tail calls use a trampoline and constant host stack, but allocate frames
in a session-owned arena. Frames are retained until the session is released;
create fresh sessions for independent jobs. Calls through `apply` and host
callbacks are depth-bounded rather than trampoline tail calls.

| Limit | Default | Bounds | Message |
| --- | --- | --- | --- |
| `steps` | 1,000,000 | Evaluation steps in one public `eval`, `call` or `with_budget` | `Limit exceeded: evaluation steps` |
| `depth` | 256 | Nested evaluations, such as arguments inside arguments and calls that are not in tail position | `Limit exceeded: evaluation depth` |
| `frames` | 100,000 | Lexical scopes allocated in the session so far | `Limit exceeded: environment frames` |

A cancelled run raises `Limit exceeded: cancelled` (see [Embedding](#embedding)).
The reader and the printer have a fixed nesting limit of 256 of their own.

Every closure call allocates a frame, including a tail call, and so does every `let`, `let*` and `letrec`.
A loop of 100,000 iterations therefore exceeds the default frame limit, even though it runs in constant host stack.

```scheme
(let loop () (loop))
;; error: Limit exceeded: environment frames
```

```mbt check
///|
test "limits bound a session and leave it usable" {
  let runtime = @scheme.Runtime::new(limits={
    steps: 100,
    depth: 32,
    frames: 100,
  })
  let message = try {
    ignore(runtime.eval("(let loop () (loop))"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Limit exceeded: evaluation steps")
  inspect(@scheme.value_to_string(runtime.eval("(+ 1 2)")), content="3")
  assert_eq(@scheme.Limits::default(), {
    steps: 1000000,
    depth: 256,
    frames: 100000,
  })
}
```

The language has no filesystem or network procedures. Host extensions are trusted
capabilities. These limits are execution controls, not an OS sandbox or a complete
memory/time bound: parsing, large exact arithmetic, serialization and host I/O
also consume resources. IR lowering, rewriting and pattern matching impose depth
limits. Errors propagate through the embedding API.

## Embedding

A `Runtime` is one session.
`Runtime::eval` reads and evaluates source text and returns the last value.

```mbt check
///|
test "a runtime evaluates source text" {
  let runtime = @scheme.Runtime::new()
  ignore(runtime.eval("(define (inc x) (+ x 1))"))
  let answer = runtime.eval("(inc 41)")
  inspect(@scheme.value_to_string(answer), content="42")
}
```

Sessions retain definitions. Register host procedures explicitly with
`Runtime::define_native(name, (runtime, arguments) -> Value raise)`.
Closures belong to the session that created them; calling a closure in another
session raises an error. Use `error_message(error)` to include error details.

```mbt check
///|
test "a host procedure joins the session" {
  let runtime = @scheme.Runtime::new()
  runtime.define_native("shout", fn(_runtime, arguments) raise {
    @scheme.arity(arguments, 1, "shout")
    @scheme.Text(arguments[0].as_text() + "!")
  })
  inspect(
    @scheme.value_to_string(runtime.eval("(shout \"hi\")")),
    content="\"hi!\"",
  )
}

///|
test "a closure belongs to its session" {
  let first = @scheme.Runtime::new()
  let second = @scheme.Runtime::new()
  let closure = first.eval("(lambda (x) x)")
  let message = try {
    ignore(second.call(closure, [@scheme.Unit]))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  assert_true(message != "")
}

///|
test "error_message includes the error details" {
  let runtime = @scheme.Runtime::new()
  let message = try {
    ignore(runtime.eval("(letrec ((a b) (b 1)) a)"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Uninitialized recursive binding: b")
}
```

| Function | Purpose |
| --- | --- |
| `Runtime::new()`, `Runtime::new(limits=...)` | A new session with the built-in procedures; raises `Runtime limits must be positive` for a limit of zero or less |
| `Runtime::eval(source)` | Read and evaluate a program; the value of its last form |
| `Runtime::call(procedure, arguments)` | Call a procedure value from the host |
| `Runtime::define_native(name, procedure)` | Bind a host procedure, replacing any binding of the name, built-ins included |
| `Runtime::register_native_binding(name, arity, procedure)` | Bind a host procedure with a fixed arity; raises `Duplicate native binding: name` if the name has one |
| `Runtime::replace_native_binding(name, arity, procedure)` | Replace an existing host procedure; raises `No native binding to replace: name` otherwise |
| `Runtime::has_native(name)`, `Runtime::native_arity(name)` | Whether a host procedure exists, and its registered arity |
| `Runtime::set_global(name, value)`, `Runtime::lookup(name)` | Write and read a top-level binding |
| `Runtime::set_cancelled(cancelled)` | A check the evaluator runs at every step; `true` stops the run with `Limit exceeded: cancelled` |
| `Runtime::with_budget(work)` | Run host work and the Scheme calls it makes under one step budget |
| `eval_program(source)` | Evaluate a program in a fresh session |
| `parse_program(source)`, `parse_program_located(source)` | Read a program into data, without and with source offsets |
| `value_to_string(value)` | The printed form of a value |
| `error_message(error)` | The message of an error |
| `arity(arguments, count, name)` | Check a host procedure's argument count, raising `name: expected count arguments` |

A procedure registered with `register_native_binding` checks its arity before it runs.
A wrong call raises `name expects N arguments`.

## Outside the language

These R6RS features are not part of Morphir Scheme:

| Feature | What happens |
| --- | --- |
| Macros (`define-syntax`, `syntax-rules`) | The names are unbound |
| Quasiquotation (backquote, comma) | The reader raises `Unsupported` |
| Continuations (`call/cc`, `dynamic-wind`) | The names are unbound |
| Ports and input and output | No procedures exist |
| Mutable pairs (`set-car!`, `set-cdr!`) | The names are unbound |
| The full numeric tower: complex numbers, infinities, NaN, exactness conversion | Only exact integers, exact rationals and inexact reals exist. No literal, `string->number` or arithmetic gives a real that is not finite; only a host or `evaluate` can, as described in [Values](#values) |
| The library system (`library`, `import`) | The names are unbound |
| Error handling (`guard`, `with-exception-handler`) | Errors always reach the host |

```scheme
(call/cc (lambda (k) (k 1)))
;; error: Unbound identifier: call/cc
```
