# Running Morphir IR

The `finos/morphir-scheme/backend` package turns Morphir IR into executable Scheme and runs it.
This chapter covers the two ways to run IR, the three emitters and what each one writes, `install` and its options,
`call_entry`, `run_file` and `run_file_in`, how IR values become Scheme values, the Morphir SDK bridge, externals,
natives and accelerators, linking, and the units that carry a symbols sidecar and source comments.
The Scheme language itself is described in [Morphir Scheme](../README.mbt.md), and compiling Scheme to IR in
[Writing models](../frontend/README.mbt.md).

Chapters: [index](../README.mbt.md) · previous: [Writing models](../frontend/README.mbt.md) · next: [Transform scripts](../pipeline/README.mbt.md)

## The package

Declare `finos/morphir-scheme@0.1.0` in your module and import `finos/morphir-scheme/backend`.
The examples use the aliases `scheme`, `frontend`, `backend` and `ir`.
The IR in them comes from the frontend, as described in [Writing models](../frontend/README.mbt.md), or is built by
hand.
The examples that read a symbols sidecar also use `moonrockz/ion/ion` as `ion` and `moonrockz/ion/binary` as
`ion_binary`.

| Function | Purpose |
| --- | --- |
| `evaluate(value, limits~)` | Run one IR value in a fresh runtime |
| `evaluate_in(runtime, value)` | Run one IR value in a runtime you own |
| `emit_expression(value)` | The Scheme text of one IR value |
| `emit_file(file)` | The Scheme text of every value in an IR file |
| `emit_unit(unit, source_path~)` | The text of `emit_file` with source comments, and a symbols sidecar |
| `install(runtime, accelerators~, model_errors~)` | Define the procedures that emitted text calls |
| `call_entry(runtime, entry, arguments)` | Call a value whose text the runtime has evaluated |
| `run_file(file, entry, arguments, limits~)` | Run a value of an IR file in a fresh runtime |
| `run_file_in(runtime, file, entry, arguments)` | Run a value of an IR file in a runtime you own |
| `link_file(runtime, file)` | Check that the runtime has the bindings that a file needs |
| `register_external`, `register_native`, `register_accelerator` | Give the runtime a host procedure |
| `replace_external`, `replace_native`, `replace_accelerator` | Replace a host procedure |

In the Scheme examples of this chapter, each block is evaluated in a runtime prepared with `install`.
Its printed result is compared with the `;; =>` line, and the start of its error message with the `;; error:` line.

```scheme
(((r:morphir/SDK:basics#add) 40) 2)
;; => 42
```

## Two ways to run IR

There are two ways to run an IR value.

| Way | Steps | Runtime |
| --- | --- | --- |
| Evaluate | Call `evaluate(value)` or `evaluate_in(runtime, value)` | `evaluate` makes one and installs support; `evaluate_in` takes yours |
| Emit and evaluate the text | Call `emit_expression(value)`, then `Runtime::eval(text)` | Yours, prepared with `install` first |

`evaluate` runs some IR without emitting text.
A literal becomes its Scheme value directly, except a document literal.
A reference applied to all of its arguments calls a registered accelerator directly, when one exists with that arity.
The SDK's `and` and `or`, applied to both operands, are evaluated directly.
Their second operand is skipped when the first decides the result, as it is in the emitted text.
Every other expression is emitted and evaluated as Scheme text.
Both ways give the same result for most values.

```mbt check
///|
test "evaluate and the emitted text agree" {
  let value = @frontend.compile_expression("(+ 40 2)")
  let text = @backend.emit_expression(value)
  inspect(text, content="(((r:morphir/SDK:basics#add) 40) 2)")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let direct = @backend.evaluate_in(runtime, value)
  let emitted = runtime.eval(text)
  inspect(@scheme.value_to_string(direct), content="42")
  inspect(@scheme.value_to_string(emitted), content="42")
}
```

They differ in the cases below.
One would expect both ways to agree in every case.
Each difference is current behaviour, tracked by `morphir-ukvn.5.50`.

| Case | `evaluate` | Emitted text |
| --- | --- | --- |
| A call to an accelerator for a value that has no definition | Calls the accelerator | `Unbound identifier: r:<fqname>` |
| A call to an SDK value whose accelerator the host replaced or registered | Calls the host's accelerator | Calls the SDK bridge, as described in [Externals, natives and accelerators](#externals-natives-and-accelerators) |
| An operand of the SDK's `and` or `or` that is not a boolean | `Expected Morphir Bool` | `Morphir condition must be boolean` |
| An integer literal outside JSON number syntax, such as `+5` or `007` | The integer, such as `5` | The IR codec's error |
| An integer literal that is not an integer, such as `abc` or `1.5` | `Expected integer` | The IR codec's error |
| A float literal that is not finite | The value, printed `NaN.0`, `Infinity.0` or `-Infinity.0` | The IR codec's error |
| A decimal literal that is not a valid decimal, such as `abc` | The tagged value, `#<decimal "abc">` | The IR codec's error |
| Accelerator calls nested so deep that the IR is more than 256 levels deep | The result | `Limit exceeded: IR backend depth` |

The IR codec's error is described in [Emitting Scheme text](#emitting-scheme-text).

```mbt check
///|
test "evaluate and the emitted text differ on bad operands and literals" {
  let a = @ir.ValueAttributes::default()
  let both = fn(value : @ir.Value) -> (String, String) {
    let direct = @scheme.value_to_string(@backend.evaluate(value)) catch {
      e => @scheme.error_message(e)
    }
    let emitted = try {
      let runtime = @scheme.Runtime::new()
      @backend.install(runtime)
      @scheme.value_to_string(runtime.eval(@backend.emit_expression(value)))
    } catch {
      e => @scheme.error_message(e)
    }
    (direct, emitted)
  }
  let and_call = @ir.Value::Apply(
    a,
    @ir.Value::Apply(
      a,
      @ir.Value::Reference(a, @ir.FQName::parse("morphir/SDK:basics#and")),
      @ir.Value::Literal(a, @ir.Literal::IntegerLiteral("1")),
    ),
    @ir.Value::Literal(a, @ir.Literal::BoolLiteral(true)),
  )
  assert_eq(
    both(and_call),
    ("Expected Morphir Bool", "Morphir condition must be boolean"),
  )
  let decimal = @ir.Value::Literal(a, @ir.Literal::DecimalLiteral("abc"))
  assert_eq(
    both(decimal),
    ("#<decimal \"abc\">", "finos/morphir-ir/wire.CodecError.Invalid"),
  )
  let integer = @ir.Value::Literal(a, @ir.Literal::IntegerLiteral("+5"))
  assert_eq(both(integer), ("5", "finos/morphir-ir/wire.CodecError.Invalid"))
  let float = @ir.Value::Literal(a, @ir.Literal::FloatLiteral(1.0 / 0.0))
  assert_eq(
    both(float),
    ("Infinity.0", "finos/morphir-ir/wire.CodecError.Invalid"),
  )
}
```

The first case comes from what each way needs.
A direct call needs only the accelerator.
The emitted text needs a definition of every value it refers to.
So a call to a value outside the IR runs with `evaluate` when an accelerator exists, and fails as text.

```mbt check
///|
test "a direct call reaches an accelerator without the definition" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(
    runtime,
    @ir.FQName::parse("user:util#inc"),
    1,
    fn(_runtime, _arguments) raise { @scheme.integer("42") },
  )
  let value = @frontend.compile_expression("(user:util#inc 41)")
  inspect(
    @scheme.value_to_string(@backend.evaluate_in(runtime, value)),
    content="42",
  )
  let message = try {
    ignore(runtime.eval(@backend.emit_expression(value)))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Unbound identifier: r:user:util#inc")
}
```

`evaluate_in(runtime, value)` and `run_file_in(runtime, file, entry, arguments)` take a runtime you own.
An embedding host uses them to register bindings first.
The runtime keeps its definitions between calls.

```mbt check
///|
test "a caller-owned runtime keeps its bindings" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let util = @frontend.compile_file(
    "(define (inc x) (+ x 1))",
    module_name="util",
  )
  ignore(runtime.eval(@backend.emit_file(util)))
  let first = @frontend.compile_expression("(user:util#inc 41)")
  inspect(
    @scheme.value_to_string(@backend.evaluate_in(runtime, first)),
    content="42",
  )
  let second = @frontend.compile_expression("(user:util#inc (user:util#inc 0))")
  inspect(
    @scheme.value_to_string(@backend.evaluate_in(runtime, second)),
    content="2",
  )
}
```

One evaluation has one step budget and one cancellation check.
Host procedures and the Scheme callbacks they make share them.
`evaluate` and `run_file` take the runtime limits as `limits~`, with the defaults described in
[Limits](../README.mbt.md#limits).

```mbt check
///|
test "evaluate takes runtime limits" {
  let value = @frontend.compile_expression(
    "(letrec ((count (lambda (n) (count (+ n 1))))) (count 0))",
  )
  let message = try {
    ignore(
      @backend.evaluate(value, limits={
        steps: 1000,
        depth: 256,
        frames: 100000,
      }),
    )
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="Limit exceeded: evaluation steps")
}
```

## Emitting Scheme text

The backend runs every form of IR value except a hole.
That covers literals, functions, records, tuples, lists, constructors, patterns, `let` definitions and recursion.
It runs library and application distributions.

| Function | Input | Output |
| --- | --- | --- |
| `emit_expression(value)` | One `@ir.Value` | One Scheme expression |
| `emit_file(file)` | An `@ir.IRFile` | One `define` per value, one form per line, and no comments |
| `emit_unit(unit, source_path~)` | A `backend.Input` | A `backend.Output`: the `emit_file` text with source comments, and the symbols sidecar |

Evaluate emitted text in a runtime prepared with `install`.
The text uses these names.

| Name | Meaning | Example |
| --- | --- | --- |
| `v:<name>` | A local variable | `v:x` |
| `r:<fqname>` | A top-level value: a procedure of no arguments that computes the value | `r:user:main#inc` |
| `%morphir-temp-<n>` | A temporary that the emitter introduces | `%morphir-temp-1` |
| `constructor:<fqname>` | A constructor registered in the runtime | `constructor:morphir/SDK:maybe#just` |
| `external:<name>` | An external or native binding | `external:answer` |
| `accelerator:<fqname>` | An accelerator binding | `accelerator:user:main#inc` |

Each top-level value is a procedure of no arguments, so the order of the definitions does not matter.
A constant is computed again each time it is referred to.
A function takes its arguments one at a time.

`emit_file` writes the values of each module in the order of the IR.
For an application, it writes the dependency packages first and the application's own package last.
After the values of a module, it writes one `(%morphir-register-constructor "<fqname>" <arity>)` form for each
constructor of the module's custom types.

| Definition | What `emit_file` writes in the `define` |
| --- | --- |
| `ExpressionBody` | The body, wrapped in a check for `accelerator:<fqname>` that calls the accelerator when one is registered |
| `ExternalBody` | A check for each runtime binding in declaration order, then the fallback, or `(%morphir-require-native "external binding")` without one |
| `NativeBody` | A check for `external:<fqname>`, then `(%morphir-require-native "external binding")` |
| `IncompleteBody` | Nothing: emitting fails |

```mbt check
///|
test "emit_file writes one define per value" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let lines = @backend.emit_file(file).split("\n").collect()
  inspect(lines.length(), content="2")
  inspect(
    lines[1],
    content=(
      #|(define r:user:main#main (lambda () (if (%morphir-has-native "accelerator:user:main#main") (%morphir-call-native "accelerator:user:main#main") ((r:user:main#inc) 41))))
    ),
  )
}
```

| Error | Message |
| --- | --- |
| A hole | `Unsupported: Cannot execute a hole` |
| An `IncompleteBody` | `Unsupported: Cannot execute incomplete definition` |
| A `NativeBody` inside a `let` | `Unsupported: Native bodies require a registered runtime implementation` |
| A `Specs` distribution | `Unsupported: A Specs distribution has no executable bodies` |
| An IR value nested more than 256 deep | `Limit exceeded: IR backend depth` |
| A pattern nested more than 256 deep | `Limit exceeded: Pattern depth` |
| A pattern that binds one name twice | `Duplicate pattern binding` |
| A literal that the IR codec refuses | `finos/morphir-ir/wire.CodecError.Invalid` |

A hole, an incomplete definition and a `Specs` distribution therefore cannot run.
A local native body has no binding name, so it cannot run either.

The emitter checks literals with the IR codec.
It refuses an integer literal whose text is not a JSON integer, such as `abc`, `1.5`, `+5` or `007`.
It refuses a float literal that is NaN or an infinity.
It refuses a decimal literal whose text is not a decimal, such as `abc`.
The `error_message` of the codec's error is the error's name, `finos/morphir-ir/wire.CodecError.Invalid`, which does
not name the literal.

## install and its options

`install(runtime, accelerators~, model_errors~)` defines the procedures that emitted text calls.
It grants no file or network access.

| Option | Default | Effect |
| --- | --- | --- |
| `accelerators` | `true` | Register an accelerator for each of the 248 SDK values, so `evaluate` calls the SDK without emitting text |
| `model_errors` | `false` | Raise an SDK failure as a `Domain` error that carries its error code, instead of an `Invalid` error |

Install support once per runtime.
With accelerators, a second `install` raises `Duplicate native binding: accelerator:morphir/SDK:basics#add`.
Without accelerators, the host can register its own accelerators for SDK values.
Only `evaluate` uses them, as described in [Externals, natives and accelerators](#externals-natives-and-accelerators).

An SDK failure has the same message with either value of `model_errors`.
Only the error kind differs.
The codes are listed in [The SDK bridge](#the-sdk-bridge).

```mbt check
///|
test "model_errors keeps the SDK error code" {
  let value = @frontend.compile_expression(
    "(morphir/SDK:basics#integer-divide 1 0)",
  )
  let kind = fn(runtime : @scheme.Runtime) -> String {
    try {
      ignore(@backend.evaluate_in(runtime, value))
      "no error"
    } catch {
      @scheme.Invalid(message) => "Invalid: " + message
      @scheme.Domain(code, message) => "Domain " + code + ": " + message
      e => @scheme.error_message(e)
    }
  }
  let plain = @scheme.Runtime::new()
  @backend.install(plain)
  inspect(
    kind(plain),
    content="Invalid: morphir/SDK:basics#integer-divide: division by zero",
  )
  let modelled = @scheme.Runtime::new()
  @backend.install(modelled, model_errors=true)
  inspect(
    kind(modelled),
    content="Domain sdk.division_by_zero: morphir/SDK:basics#integer-divide: division by zero",
  )
}
```

`install` defines these procedures.
Emitted text calls them.
A host rarely needs to.

| Procedure | Purpose | Errors |
| --- | --- | --- |
| `(%morphir-tag name value ...)` | A tagged value | `Tag requires a name` |
| `(%morphir-constructor fqname)` | The registered constructor | `Unbound identifier: constructor:<fqname>` |
| `(%morphir-register-constructor fqname arity)` | Register a constructor that takes `arity` arguments, from 0 to 256 | `Expected bounded constructor arity` |
| `(%morphir-match pattern value)` | Match an IR pattern, given as IR JSON text; a record of the bindings, or `#f` | `Duplicate pattern binding`, `Limit exceeded: Pattern depth` |
| `(%morphir-boolean value)` | The value, if it is a boolean | `Morphir condition must be boolean` |
| `(%morphir-update record field value)` | A copy of the record with one field changed | `Update requires an existing record field`, `Expected record` |
| `(%morphir-has-native name)` | Whether the runtime has a host procedure of that name | None |
| `(%morphir-call-native name argument ...)` | Call a host procedure with all its arguments at once | `Native call requires a binding name`, `Unbound identifier: <name>` |
| `(%morphir-external name argument ...)` | Call the binding `external:<name>` | `External call requires a registered name`, `Unbound identifier: external:<name>` |
| `(%morphir-require-native description)` | Fail, for an external with no binding and no fallback | `Unbound identifier: <description>` |
| `(%morphir-sdk fqname argument ...)` | Call an SDK value with all its arguments at once | `Morphir SDK call requires a value name`, `Unbound identifier: <fqname>`, `<fqname>: expected <n> arguments`, and the failures in [The SDK bridge](#the-sdk-bridge) |

A procedure with a fixed number of arguments also checks that number.
A wrong count raises `<purpose>: expected <n> arguments`, such as `boolean condition: expected 1 arguments`.

```scheme
(%morphir-boolean)
;; error: boolean condition: expected 1 arguments
```

It also defines `r:<fqname>` for each SDK value, and the constructors `Just`, `Nothing`, `Ok` and `Err` of the SDK's
`Maybe` and `Result`.

An IR condition must be a boolean.
This differs from Scheme, where every value but `#f` counts as true.

```scheme
(if (%morphir-boolean 1) 'yes 'no)
;; error: Morphir condition must be boolean
```

A record update changes a field that exists and adds no field.

```scheme
(%morphir-update (record (cons "a" 1)) "a" 2)
;; => #<record a=2>
```

```scheme
(%morphir-update (record (cons "a" 1)) "b" 2)
;; error: Update requires an existing record field
```

A constructor takes its arguments one at a time.

```scheme
(%morphir-register-constructor "user:main#pair" 2)
(((%morphir-constructor "user:main#pair") 1) 2)
;; => #<user:main#pair 1 2>
```

```scheme
(%morphir-constructor "user:main#circle")
;; error: Unbound identifier: constructor:user:main#circle
```

## call_entry, run_file and run_file_in

| Function | What it does |
| --- | --- |
| `call_entry(runtime, entry, arguments)` | Look up `r:<entry>`, call it, then apply the arguments one at a time |
| `run_file(file, entry, arguments, limits~)` | Make a runtime, `install` support, then `run_file_in` |
| `run_file_in(runtime, file, entry, arguments)` | Check the file's bindings, then call the entry |

`call_entry` runs text that the runtime has already evaluated.
It raises `Unbound identifier: r:<entry>` when the runtime has no such value.

```mbt check
///|
test "emit Scheme text, install support, call an entry point" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let text = @backend.emit_file(file)
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  ignore(runtime.eval(text))
  let answer = @backend.call_entry(
    runtime,
    @ir.FQName::parse("user:main#main"),
    [],
  )
  inspect(@scheme.value_to_string(answer), content="42")
}
```

`run_file_in` works in these steps.

1. It finds the entry among the file's values, or raises `Unbound identifier: <entry>`.
2. It checks every value of the file, as `link_file` does.
3. If the entry has a host binding and `arguments` holds all of its inputs, it calls the binding with them at once.
4. Otherwise it evaluates the text of `emit_file` and calls the entry with `call_entry`.

The arguments are Scheme values.
Fewer arguments than the entry's inputs give a procedure that takes the rest.

```mbt check
///|
test "run a file's value with arguments" {
  let file = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let entry = @ir.FQName::parse("user:main#inc")
  let answer = @backend.run_file(file, entry, [@scheme.integer("1")])
  inspect(@scheme.value_to_string(answer), content="2")
  let partial = @backend.run_file(file, entry, [])
  inspect(@scheme.value_to_string(partial), content="#<procedure>")
  let missing = try {
    ignore(@backend.run_file(file, @ir.FQName::parse("user:main#dec"), []))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(missing, content="Unbound identifier: user:main#dec")
}
```

## How values map

| IR | Scheme value | Printed form |
| --- | --- | --- |
| Bool literal | Boolean | `#t` |
| Char literal | Character | `#\a` |
| String literal | String | `"abc"` |
| Integer literal | Exact integer | `42` |
| Float literal | Inexact real | `2.5` |
| Decimal literal | Value tagged `decimal`, holding the literal's text | `#<decimal "1.50">` |
| Document literal | Value tagged `document`, holding the document as JSON text | `#<document "{\"a\":1}">` |
| Unit | Unit | `#<unit>` |
| Tuple | Vector | `#(1 "a")` |
| List | Proper list | `(1 2 3)` |
| Record | Record, with each field under its canonical name | `#<record first-name="Ada">` |
| Constructor applied to its arguments | Value tagged with the constructor's canonical fqname | `#<morphir/SDK:maybe#just 1>` |
| Function | Procedure of one argument | `#<procedure>` |

```mbt check
///|
test "IR values become Scheme values" {
  let a = @ir.ValueAttributes::default()
  let show = fn(value : @ir.Value) -> String raise {
    @scheme.value_to_string(@backend.evaluate(value))
  }
  let one = @ir.Value::Literal(a, @ir.Literal::IntegerLiteral("1"))
  let text = @ir.Value::Literal(a, @ir.Literal::StringLiteral("a"))
  inspect(show(@ir.Value::Tuple(a, [one, text])), content="#(1 \"a\")")
  let record = @ir.Value::Record(
    a,
    Map::from_array([
      (
        @ir.Name::parse("first-name"),
        @ir.Value::Literal(a, @ir.Literal::StringLiteral("Ada")),
      ),
    ]),
  )
  inspect(show(record), content="#<record first-name=\"Ada\">")
  let decimal = @ir.Value::Literal(a, @ir.Literal::DecimalLiteral("1.50"))
  inspect(show(decimal), content="#<decimal \"1.50\">")
  let document = @ir.Value::Literal(
    a,
    @ir.Literal::DocumentLiteral(
      @ir.Data::Object(Map::from_array([("a", @ir.Data::Number("1"))])),
    ),
  )
  inspect(show(document), content="#<document \"{\\\"a\\\":1}\">")
  let just = @ir.Value::Apply(
    a,
    @ir.Value::Constructor(a, @ir.FQName::parse("morphir/SDK:maybe#just")),
    one,
  )
  inspect(show(just), content="#<morphir/SDK:maybe#just 1>")
  inspect(show(@ir.Value::Unit(a)), content="#<unit>")
}
```

A constructor with no arguments prints with a space before the closing `>`, such as
`#<morphir/SDK:maybe#nothing >`.
One would expect `#<morphir/SDK:maybe#nothing>`.
The space is current behaviour, tracked by `morphir-ukvn.5.50`.

```scheme
(list (%morphir-constructor "morphir/SDK:maybe#nothing"))
;; => (#<morphir/SDK:maybe#nothing >)
```

A pattern matches a tagged value when the tag and the number of arguments agree.
A literal pattern compares with the runtime's equality.
When no case of a `PatternMatch` matches, the run fails with the message `"No matching pattern"`, quotes included.
A lambda or a destructuring whose pattern does not match fails with `"Lambda pattern mismatch"` or
`"Destructure pattern mismatch"`, also quoted.
The emitted text raises these errors with Scheme's `error` procedure, which prints its string argument with quotes.
One would expect the message without quotes.
The quotes are current behaviour, tracked by `morphir-ukvn.5.50`.

```mbt check
///|
test "a failed pattern match has a quoted message" {
  let a = @ir.ValueAttributes::default()
  let value = @ir.Value::PatternMatch(
    a,
    @ir.Value::Literal(a, @ir.Literal::IntegerLiteral("1")),
    [],
  )
  let message = try {
    ignore(@backend.evaluate(value))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(message, content="\"No matching pattern\"")
}
```

A custom type's constructors are registered by the `emit_file` text of the module that declares the type.
An expression that uses a constructor of a type the runtime has not registered fails with
`Unbound identifier: constructor:<fqname>`.

A decimal keeps the text of its literal.
Scheme's `equal?` compares that text, so `1.5` and `1.50` differ.
The SDK's comparisons compare the numbers.

```scheme
(list (equal? (%morphir-tag "decimal" "1.5") (%morphir-tag "decimal" "1.50"))
      (((r:morphir/SDK:basics#equal) (%morphir-tag "decimal" "1.5"))
       (%morphir-tag "decimal" "1.50")))
;; => (#f #t)
```

A document keeps its JSON text.
The SDK has no document operations.

## The SDK bridge

The bridge implements the 248 values of the Morphir SDK modules below.
They come from `finos/morphir-elm` commit `bc99af69a8b24d391311fae3822a87eafef3c334`.
The [SDK conformance corpus](../../morphir-sdk/conformance/README.md) checks them against that Elm code.

| Module | Values |
| --- | ---: |
| `morphir/SDK:basics` | 53 |
| `morphir/SDK:string` | 44 |
| `morphir/SDK:list` | 39 |
| `morphir/SDK:decimal` | 34 |
| `morphir/SDK:dict` | 22 |
| `morphir/SDK:set` | 17 |
| `morphir/SDK:char` | 13 |
| `morphir/SDK:result` | 10 |
| `morphir/SDK:maybe` | 8 |
| `morphir/SDK:int` | 8 |

Each value is `r:<fqname>`, a procedure of no arguments that returns the curried function.
A value that takes no arguments, such as `pi`, returns the value itself.

```scheme
(list (((r:morphir/SDK:basics#max) 3) 4) (r:morphir/SDK:basics#pi))
;; => (4 3.141592653589793)
```

`%morphir-sdk` calls an SDK value with all its arguments at once.
It checks the number of arguments.

```scheme
(%morphir-sdk "morphir/SDK:basics#add" 40)
;; error: morphir/SDK:basics#add: expected 2 arguments
```

Other SDK modules, such as `Tuple`, `Regex` and `LocalDate`, have no bridge.
A reference to one of their values is unbound.

```scheme
((r:morphir/SDK:tuple#first) (vector 1 2))
;; error: Unbound identifier: r:morphir/SDK:tuple#first
```

Some SDK types have a Scheme shape of their own.

| SDK type | Scheme value | Printed form |
| --- | --- | --- |
| `Maybe`, `Result` | Value tagged with the constructor's fqname | `#<morphir/SDK:maybe#just 42>` |
| `Order` | Value tagged `morphir/SDK:basics#l-t`, `#e-q` or `#g-t` | `#<morphir/SDK:basics#l-t >` |
| `Dict` | Value tagged `sdk-dict`, holding a sorted list of key and value vectors | `#<sdk-dict (#(1 10) #(2 20))>` |
| `Set` | Value tagged `sdk-set`, holding a sorted list | `#<sdk-set (1 2)>` |
| `Int8`, `Int16`, `Int32`, `Int64` | Value tagged `morphir/SDK:int#int8` and so on | `#<morphir/SDK:int#int8 5>` |
| `Decimal` | Value tagged `decimal`, holding the number's text | `#<decimal "3.75">` |
| `String` holding an isolated surrogate | Value tagged `sdk-text`, holding a vector of UTF-16 code units | `#<sdk-text #(55357)>` |
| `Char` that is an isolated surrogate | Value tagged `sdk-character`, holding a vector of UTF-16 code units | `#<sdk-character #(55357)>` |

```scheme
(list (%morphir-sdk "morphir/SDK:basics#compare" 1 2)
      (%morphir-sdk "morphir/SDK:dict#from-list" (list (vector 2 20) (vector 1 10)))
      (%morphir-sdk "morphir/SDK:set#from-list" (list 2 1 2)))
;; => (#<morphir/SDK:basics#l-t > #<sdk-dict (#(1 10) #(2 20))> #<sdk-set (1 2)>)
```

```scheme
(%morphir-sdk "morphir/SDK:decimal#add" (%morphir-tag "decimal" "1.5") (%morphir-tag "decimal" "2.25"))
;; => #<decimal "3.75">
```

A Scheme string is a MoonBit `String`, which cannot hold an isolated surrogate.
An SDK `String` result that holds one is an `sdk-text` value instead.
The SDK functions accept it, so it survives a chain of SDK calls.
The core string procedures, and `Value::as_text` in the host, refuse it with `Expected string`.

```scheme
(%morphir-sdk "morphir/SDK:string#slice" 0 1 "😀")
;; => #<sdk-text #(55357)>
```

```scheme
(string-append (%morphir-sdk "morphir/SDK:string#slice" 0 1 "😀") "x")
;; error: Expected string
```

An SDK failure's message is the value's fqname, a colon and the detail.

| Failure | Detail | Code with `model_errors=true` |
| --- | --- | --- |
| Division by zero | `division by zero` | `sdk.division_by_zero` |
| A number that is not valid | `invalid number: <message>` | `sdk.invalid_number` |
| A number out of range | `out of range: <message>` | `sdk.out_of_range` |
| Values that cannot be compared | `invalid comparison: <message>` | `sdk.invalid_comparison` |
| Text that cannot be represented | `unrepresentable text: <message>` | `sdk.unrepresentable_text` |

```scheme
(((r:morphir/SDK:basics#integer-divide) 1) 0)
;; error: morphir/SDK:basics#integer-divide: division by zero
```

`Basics.never` has no value to take, and calling it raises `Cannot construct a Morphir Never value`.
An argument of the wrong shape raises an error.
Some of these messages name the SDK value, and some do not.

| Message | Names the value |
| --- | --- |
| `<fqname>: incompatible numeric operands` | Yes |
| `<fqname>: incompatible SDK operand` | Yes |
| `<fqname>: unsupported Integer SDK operation`, `<fqname>: unsupported Float SDK operation` | Yes |
| `Expected Morphir Integer`, `Expected Morphir Float`, `Expected Morphir Maybe` and the other `Expected Morphir <type>` messages | No |

```scheme
((r:morphir/SDK:basics#negate) "a")
;; error: morphir/SDK:basics#negate: incompatible SDK operand
```

```scheme
(((r:morphir/SDK:maybe#with-default) 0) 1)
;; error: Expected Morphir Maybe
```

## Externals, natives and accelerators

A host gives the runtime its own procedures in three ways.

| Kind | IR definition | Binding name | Used when |
| --- | --- | --- | --- |
| External | `ExternalBody` | `external:<external name>` | A binding is registered; otherwise the portable fallback runs |
| Native | `NativeBody` | `external:<fqname>` | Always; the value has no portable body |
| Accelerator | `ExpressionBody` | `accelerator:<fqname>` | A binding is registered; otherwise the body runs |

An external body lists bindings by target platform.
The backend uses the bindings whose platform is `morphir-runtime`, `morphir-scheme` or `scheme`, in declaration order.
The first one that is registered runs.
If none is registered, the portable fallback runs.
An external with no fallback and no registered binding cannot run.
`run_file_in` and `link_file` then raise `Unbound identifier: No runtime binding or fallback for <fqname>`.
The emitted text, evaluated directly, raises `Unbound identifier: external binding`.
An error from a binding that runs propagates, and the fallback does not run.

A native body exists only at the top level of a module.
A host procedure receives all of the value's inputs at once, as the IR signature declares them.
The emitted text collects the curried arguments first.
`run_file_in` passes its arguments at once when it has all of them.

| Function | Binds | Arity | Error |
| --- | --- | --- | --- |
| `register_external(runtime, name, arity, procedure)` | `external:<name>` | Recorded | `Duplicate native binding: external:<name>` |
| `replace_external(runtime, name, arity, procedure)` | `external:<name>` | Recorded | `No native binding to replace: external:<name>` |
| `register_native(runtime, fqname, procedure)` | `external:<fqname>` | Not recorded | `Duplicate native binding: external:<fqname>` |
| `replace_native(runtime, fqname, procedure)` | `external:<fqname>` | Not recorded | `No native binding to replace: external:<fqname>` |
| `register_accelerator(runtime, fqname, arity, procedure)` | `accelerator:<fqname>` | Recorded | `Duplicate native binding: accelerator:<fqname>` |
| `replace_accelerator(runtime, fqname, arity, procedure)` | `accelerator:<fqname>` | Recorded | `No native binding to replace: accelerator:<fqname>` |

A procedure has the type `(@scheme.Runtime, Array[@scheme.Value]) -> @scheme.Value raise`.
A registration fails when the name already has a binding.
A replacement fails when it has none.
A registration with a negative arity raises `Native binding arity must be nonnegative`.
A replacement with a negative arity raises `No native binding to replace: <binding>`, even when the binding exists.

A recorded arity is checked twice.
`link_file` and `run_file_in` compare it with the value's inputs, as described in [Linking](#linking).
Each call compares it with the number of arguments, and a wrong count raises `<binding> expects <n> arguments`.

```scheme
(%morphir-call-native "accelerator:morphir/SDK:basics#add" 1)
;; error: accelerator:morphir/SDK:basics#add expects 2 arguments
```

```mbt check
///|
fn doc_file(definition : @ir.ValueDefinition) -> @ir.IRFile raise {
  let values : Map[
    @ir.Name,
    @ir.AccessControlled[@ir.Documented[@ir.ValueDefinition]],
  ] = Map::from_array([
    (
      @ir.Name::parse("main"),
      { access: @ir.Access::Public, value: { doc: None, value: definition, }, },
    ),
  ])
  @ir.IRFile::new(
    @ir.Distribution::Library(@ir.Path::parse("test"), Map([]), {
      modules: Map::from_array([
        (
          @ir.Path::parse("main"),
          {
            access: @ir.Access::Public,
            value: { types: Map([]), values, doc: None, },
          },
        ),
      ]),
    }),
  )
}

///|
test "an external body uses a registered binding, else its fallback" {
  let entry = @ir.FQName::parse("test:main#main")
  let fallback = @ir.Value::Literal(
    @ir.ValueAttributes::default(),
    @ir.Literal::IntegerLiteral("44"),
  )
  let definition = @ir.ValueDefinition::ExternalBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    [{ target_platform: "morphir-scheme", external_name: "answer", }],
    Some(fallback),
  )
  let portable = @backend.run_file(doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(portable), content="44")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_external(runtime, "answer", 0, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("42")
  })
  let hosted = @backend.run_file_in(runtime, doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(hosted), content="42")
  let duplicate = try {
    @backend.register_external(runtime, "answer", 0, fn(
      _runtime,
      _arguments,
    ) raise {
      @scheme.integer("1")
    })
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(duplicate, content="Duplicate native binding: external:answer")
  @backend.replace_external(runtime, "answer", 0, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("43")
  })
  let replaced = @backend.run_file_in(runtime, doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(replaced), content="43")
}
```

```mbt check
///|
test "a native body needs a registered binding" {
  let entry = @ir.FQName::parse("test:main#main")
  let unit_type = @ir.Type::Unit(@ir.TypeAttributes::default())
  let definition = @ir.ValueDefinition::NativeBody(
    [(@ir.Name::parse("x"), unit_type), (@ir.Name::parse("y"), unit_type)],
    unit_type,
    { hint: @ir.NativeHint::Arithmetic, description: None, },
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  let missing = try {
    ignore(@backend.run_file_in(runtime, doc_file(definition), entry, []))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(missing, content="Unbound identifier: external:test:main#main")
  @backend.register_native(runtime, entry, fn(_runtime, arguments) raise {
    @scheme.integer(arguments.length().to_string())
  })
  let answer = @backend.run_file_in(runtime, doc_file(definition), entry, [
    @scheme.integer("1"),
    @scheme.integer("2"),
  ])
  inspect(@scheme.value_to_string(answer), content="2")
}
```

An accelerator replaces the body of a value that has a portable body.
Without an accelerator, the body runs.

```mbt check
///|
test "an accelerator replaces a portable body" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExpressionBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    @ir.Value::Literal(
      @ir.ValueAttributes::default(),
      @ir.Literal::IntegerLiteral("44"),
    ),
  )
  let portable = @backend.run_file(doc_file(definition), entry, [])
  inspect(@scheme.value_to_string(portable), content="44")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 0, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("45")
  })
  ignore(runtime.eval(@backend.emit_file(doc_file(definition))))
  inspect(
    @scheme.value_to_string(@backend.call_entry(runtime, entry, [])),
    content="45",
  )
}
```

The accelerators that `install` registers for SDK values are used only by `evaluate`'s direct calls.
Emitted text calls the SDK through `r:<fqname>`, which does not check for an accelerator.
So `replace_accelerator` on an SDK value changes the result of `evaluate`, and not the result of the emitted text.
One would expect both ways to use the host's accelerator, as they do for a value with an `ExpressionBody`.
This is current behaviour, tracked by `morphir-ukvn.5.50`.

```mbt check
///|
test "a replaced SDK accelerator changes only evaluate" {
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.replace_accelerator(
    runtime,
    @ir.FQName::parse("morphir/SDK:basics#add"),
    2,
    fn(_runtime, _arguments) raise { @scheme.integer("0") },
  )
  let value = @frontend.compile_expression("(+ 40 2)")
  inspect(
    @scheme.value_to_string(@backend.evaluate_in(runtime, value)),
    content="0",
  )
  inspect(
    @scheme.value_to_string(runtime.eval(@backend.emit_expression(value))),
    content="42",
  )
}
```

## Linking

`link_file(runtime, file)` checks, before anything runs, that the runtime can run every value of the file.
For an application, it checks the dependency packages too.
`run_file_in` makes the same checks before it calls the entry.

| Check | Message |
| --- | --- |
| A native body has a binding | `Unbound identifier: external:<fqname>` |
| An external body with no fallback has a binding | `Unbound identifier: No runtime binding or fallback for <fqname>` |
| A registered binding's arity equals the number of inputs | `Native binding arity mismatch: <binding> expects <inputs>, registered <arity>` |
| No value is an incomplete definition | `Unsupported: Cannot execute incomplete definition: <fqname>` |
| The distribution is not `Specs` | `Unsupported: A Specs distribution has no executable bodies` |

```mbt check
///|
test "linking rejects a mismatched accelerator arity" {
  let entry = @ir.FQName::parse("test:main#main")
  let definition = @ir.ValueDefinition::ExpressionBody(
    [],
    @ir.Type::Unit(@ir.TypeAttributes::default()),
    @ir.Value::Literal(
      @ir.ValueAttributes::default(),
      @ir.Literal::IntegerLiteral("44"),
    ),
  )
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.register_accelerator(runtime, entry, 1, fn(
    _runtime,
    _arguments,
  ) raise {
    @scheme.integer("42")
  })
  let message = try {
    @backend.link_file(runtime, doc_file(definition))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(
    message,
    content="Native binding arity mismatch: accelerator:test:main#main expects 0, registered 1",
  )
}
```

`link_file` checks bindings, not references.
A reference to a value in another file passes the check, and fails when it runs.
A native registered with `register_native` has no recorded arity, so its arity is not checked.

A library lists its dependencies as specifications only.
To run a library that uses another package or module, evaluate the other one's text in the same runtime first.
An application includes the implementations of its dependencies, and `emit_file` writes them before its own values.

```mbt check
///|
test "two files run in one runtime" {
  let util = @frontend.compile_file(
    "(define (inc x) (+ x 1))",
    module_name="util",
  )
  let main = @frontend.compile_file("(user:util#inc 41)")
  let entry = @ir.FQName::parse("user:main#main")
  let runtime = @scheme.Runtime::new()
  @backend.install(runtime)
  @backend.link_file(runtime, main)
  let alone = try {
    ignore(@backend.run_file_in(runtime, main, entry, []))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(alone, content="Unbound identifier: r:user:util#inc")
  ignore(runtime.eval(@backend.emit_file(util)))
  let answer = @backend.run_file_in(runtime, main, entry, [])
  inspect(@scheme.value_to_string(answer), content="42")
}
```

## Units, sidecar and source comments

`emit_unit(unit, source_path~)` emits a rich unit.
A rich unit carries the IR together with metadata about its nodes, in the contract that the MoonBit generator's
`Input` also follows.

| `backend.Input` field | Type | Content |
| --- | --- | --- |
| `unit_id` | `String` | The unit's id |
| `ir` | `@ir.IRFile` | The IR |
| `metadata` | `Array[backend.NodeMetadata]` | Node metadata in order: each entry has a `node_id` and Ion `data` |
| `annotations` | `Array[@ion.SymbolToken]` | Ordered annotation tokens |
| `provenance` | `Array[@ion.IonValue]` | Provenance records |

`Input::new(unit_id, ir)` makes an input with no metadata, annotations or provenance.
`emit_unit` returns a `backend.Output`.
Its `source` is the Scheme text, and its `symbols` is the binary Ion symbols sidecar.
`emit_unit(Input::new(id, ir)).source` equals `emit_file(ir)`.
`emit_file` never writes comments or a sidecar.

The engine writes the two as `<unit>.scm` and `<unit>.symbols.10n`, in the format `ion-binary`, for every rich
frontend.
For the plain `scheme` and `ir-json` frontends it writes only `<unit>.scm`.
`SYMBOLS_SUFFIX` is `.symbols.10n`.
The backend always returns a sidecar, even for a unit with no metadata, so that a consumer can rely on it.

```mbt check
///|
test "emit_unit returns the emit_file text and a sidecar" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  assert_eq(output.source, @backend.emit_file(ir))
  assert_true(output.symbols.length() > 0)
}
```

### The symbols sidecar

The sidecar is one Ion record annotated `morphir_scheme_symbols`.
Its profile is `morphir-scheme-symbols-v1`, the constant `SYMBOLS_PROFILE`.
Its naming policy is `scheme-canonical-identity-v1`.
Scheme binds each value to its canonical Morphir name, so the generated name of every symbol is its fqname.
The bytes are a pure function of the unit.

| Field | Content | Example |
| --- | --- | --- |
| `profile` | The profile | `"morphir-scheme-symbols-v1"` |
| `naming_policy` | The naming policy | `"scheme-canonical-identity-v1"` |
| `unit_id` | The unit's id | `"Main"` |
| `source_annotations` | The unit's annotation tokens, unchanged, as Ion symbols | `[morphir_pipeline]` |
| `source_provenance` | The unit's provenance, unchanged | `[]` |
| `source_nodes` | The ids of the nodes the unit owns | `["unit:Main", "unit:Main/ir", …, "module:user:main", "value:user:main#inc", …]` |
| `metadata` | Every metadata entry, unchanged, in the unit's order, as records of `node_id` and `data` | `[]` |
| `symbols` | One record per emitted `define`, in the order of the text | See below |

| Symbol field | Content | Example |
| --- | --- | --- |
| `fqname` | The value's canonical fqname | `"user:main#inc"` |
| `generated_name` | The same as `fqname` | `"user:main#inc"` |
| `scheme_symbol` | The `r:` symbol as the text writes it | `"r:user:main#inc"` |
| `public` | Whether the value and its module are both public | `true` |
| `source_node` | `value:<fqname>` | `"value:user:main#inc"` |
| `generated_node` | `scheme:define:<fqname>` | `"scheme:define:user:main#inc"` |
| `origins` | `source_node` and `<source_node>/body`, each only when the unit owns it | `["value:user:main#inc", "value:user:main#inc/body"]` |

A native or external value has no body node, so its origins list no body.
The unit owns identities only for a library, so an application's symbols list no origins.
The metadata is copied without checking which node owns it.
The engine checks rich units when a frontend returns them.

Unlike `morphir-moonbit-symbols-2026-10-17`, the sidecar has no `warnings`, `naming_allocations`, `consumed_naming_facts`,
`unvalidated_predicates` or `source_ir_json`.
Scheme recovers no names, and the checkpoint backend carries the IR.

```mbt check
///|
test "the sidecar names its profile and its symbols" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  let stored = @ion_binary.read_binary_value(output.symbols[:])
  assert_eq(stored.annotations().map(a => a.text()), [
    Some("morphir_scheme_symbols"),
  ])
  guard stored.kind() is @ion.Struct(fields) else { fail("Expected a record") }
  assert_eq(fields.map(field => field.name().text().unwrap()), [
    "profile", "naming_policy", "unit_id", "source_annotations", "source_provenance",
    "source_nodes", "metadata", "symbols",
  ])
  assert_eq(@backend.SYMBOLS_PROFILE, "morphir-scheme-symbols-v1")
}
```

```mbt check
///|
/// The text of a string field of an Ion record, or "" when the field is absent.
fn doc_ion_text(record : @ion.IonValue, name : String) -> String {
  guard record.kind() is @ion.Struct(fields) else { return "" }
  for field in fields {
    if field.name().text() == Some(name) &&
      field.value().kind() is @ion.String(text) {
      return text
    }
  }
  ""
}

///|
/// The value of a field of an Ion record.
fn doc_ion_field(record : @ion.IonValue, name : String) -> @ion.IonValue raise {
  guard record.kind() is @ion.Struct(fields) else { fail("Expected a record") }
  for field in fields {
    if field.name().text() == Some(name) {
      return field.value()
    }
  }
  fail("No field " + name)
}

///|
test "read the symbols of a sidecar" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let output = @backend.emit_unit(@backend.Input::new("Main", ir))
  let stored = @ion_binary.read_binary_value(output.symbols[:])
  guard doc_ion_field(stored, "symbols").kind() is @ion.List(symbols) else {
    fail("Expected a list of symbols")
  }
  let first = symbols[0]
  inspect(doc_ion_text(first, "fqname"), content="user:main#inc")
  inspect(doc_ion_text(first, "scheme_symbol"), content="r:user:main#inc")
  inspect(
    doc_ion_text(first, "generated_node"),
    content="scheme:define:user:main#inc",
  )
  guard doc_ion_field(first, "origins").kind() is @ion.List(origins) else {
    fail("Expected a list of origins")
  }
  let texts = origins.map(origin => {
    match origin.kind() {
      @ion.String(text) => text
      _ => ""
    }
  })
  assert_eq(texts, ["value:user:main#inc", "value:user:main#inc/body"])
  guard doc_ion_field(stored, "source_nodes").kind() is @ion.List(nodes) else {
    fail("Expected a list of nodes")
  }
  assert_true(
    nodes.any(node => node.kind() is @ion.String("value:user:main#inc/body")),
  )
}
```

The metadata reaches the sidecar unchanged, whatever its content.

```mbt check
///|
test "the sidecar keeps the unit's metadata" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let input = {
    ..@backend.Input::new("Main", ir),
    metadata: [
      { node_id: "value:user:main#inc", data: @ion.IonValue::string("kept"), },
    ],
  }
  let stored = @ion_binary.read_binary_value(
    @backend.emit_unit(input).symbols[:],
  )
  guard doc_ion_field(stored, "metadata").kind() is @ion.List(entries) else {
    fail("Expected a list of entries")
  }
  inspect(entries.length(), content="1")
  inspect(doc_ion_text(entries[0], "node_id"), content="value:user:main#inc")
  assert_true(doc_ion_field(entries[0], "data").kind() is @ion.String("kept"))
}
```

### Source comments

Unit metadata can name the source of a value.
`emit_unit` then writes a comment line directly above that value's `define`.
The comment has one of three forms.

```text
;; <name> (<path>:<line>:<column>)
;; <name> (<path>)
;; <name>
```

The comment comes from the metadata entry whose `node_id` is `value:<fqname>`.
Its `data` is a record with a `declaration` field, which is a record in turn.

| `declaration` field | Type | Use |
| --- | --- | --- |
| `name` | String | The name in the comment; required |
| `path` | String | The path in the comment |
| `start_line`, `start_column` | Integer | The position in the comment |
| `end_line`, `end_column` | Integer | Checked against the start; not written |

The path is the record's `path`, else the `source_path` argument, else the unit id.
The position is written when all four coordinates are non-negative integers of at most nine digits, and the end is not
before the start.
Otherwise the comment has the path form.
The comment has no path only when none of the three paths can be used.

A hint is a spelling for a comment, not a trusted fact.
A name or a path can be used only when it is non-empty and holds at most 256 UTF-16 code units.
It must also hold no character below U+0020, and none of U+007F, U+0085, U+2028 and U+2029.
The other C1 control characters, U+0080 to U+009F apart from U+0085, are accepted.
So no hint can end the comment early.
The backend ignores parts of the metadata that it cannot use.

| Metadata | Result |
| --- | --- |
| An entry whose `node_id` occurs more than once | No comment |
| A `declaration` or `name` field that occurs more than once | No comment |
| A `name` that cannot be used | No comment |
| A `path` that cannot be used, or occurs more than once | The next path in order |
| A coordinate that is missing, negative, longer than nine digits or repeated | The path form |
| An end before the start | The path form |
| An entry for a node other than a value itself, such as `value:<fqname>/body` or a type | No comment; the entry stays in the sidecar |

A comment changes no name and no behaviour.

```mbt check
///|
test "a declaration record becomes a source comment" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let declaration = @ion.IonValue::new(
    @ion.Struct([
      @ion.Field::new("name", @ion.IonValue::string("inc")),
      @ion.Field::new("path", @ion.IonValue::string("src/Main.elm")),
      @ion.Field::new("start_line", @ion.IonValue::int(3)),
      @ion.Field::new("start_column", @ion.IonValue::int(1)),
      @ion.Field::new("end_line", @ion.IonValue::int(3)),
      @ion.Field::new("end_column", @ion.IonValue::int(20)),
    ]),
  )
  let metadata = @ion.IonValue::new(
    @ion.Struct([@ion.Field::new("declaration", declaration)]),
  )
  let input = {
    ..@backend.Input::new("Main", ir),
    metadata: [{ node_id: "value:user:main#inc", data: metadata, }],
  }
  let output = @backend.emit_unit(input)
  assert_true(output.source.has_prefix(";; inc (src/Main.elm:3:1)\n"))
  assert_true(@backend.emit_file(ir) != output.source)
}
```

```mbt check
///|
test "a comment falls back to the source path" {
  let ir = @frontend.compile_file("(define (inc x) (+ x 1)) (inc 41)")
  let declaration = @ion.IonValue::new(
    @ion.Struct([@ion.Field::new("name", @ion.IonValue::string("inc"))]),
  )
  let input = {
    ..@backend.Input::new("Main", ir),
    metadata: [
      {
        node_id: "value:user:main#inc",
        data: @ion.IonValue::new(
          @ion.Struct([@ion.Field::new("declaration", declaration)]),
        ),
      },
    ],
  }
  let with_path = @backend.emit_unit(input, source_path=Some("src/main.scm"))
  assert_true(with_path.source.has_prefix(";; inc (src/main.scm)\n"))
  let without = @backend.emit_unit(input)
  assert_true(without.source.has_prefix(";; inc (Main)\n"))
}
```

> **Planned.** `morphir-ukvn.5.43` gives application distributions owned module and value identities, so their
> symbols can list origins.
> `morphir-ukvn.5.44` decides whether Elm projects carry declaration origins by default.
> Today an Elm project carries them only with `frontend.profile = "library-origins"`.
