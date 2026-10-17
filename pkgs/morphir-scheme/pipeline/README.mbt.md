# Transform scripts

The `finos/morphir-scheme/pipeline` package runs IR transforms written in Scheme.
This chapter covers a script as an `IRFile -> IRFile` procedure, the session that runs it, every procedure the
session adds, bottom-up rewriting, versioned reading, the JSON bridge and the use of scripts from
`morphir.config.scm`.
The Scheme language is described in [Morphir Scheme](../README.mbt.md), and running IR in
[Running Morphir IR](../backend/README.mbt.md).

Chapters: [index](../README.mbt.md) · previous: [Running Morphir IR](../backend/README.mbt.md) · next: [Specification notation](../spec/README.mbt.md)

## Scripts

A transform script is Scheme text that evaluates to a procedure.
The procedure takes one IR file and returns an IR file.
`transform_file(file, script, limits~)` evaluates the script in a new session, calls the procedure with `file` and
returns its result.
The input file is not changed.

| Function | Purpose |
| --- | --- |
| `new_runtime(limits~)` | A new `Runtime` with the procedures of this chapter |
| `install(runtime)` | Add the procedures of this chapter to a runtime you own |
| `transform_file(file, script, limits~)` | Run a script over one IR file in a new session |
| `rewrite_value(value, transform)` | The bottom-up rewrite of one IR value, for MoonBit callers |
| `rewrite_file(file, transform)` | The bottom-up rewrite of every value of an IR file, for MoonBit callers |

`transform_file` raises `Expected procedure` when the script does not evaluate to a procedure.
It raises `Expected Morphir IR file` when the procedure returns something other than a file.

```mbt check
///|
test "transform_file runs a script over a file" {
  let file = @frontend.compile_file("40")
  let transformed = @pipeline.transform_file(
    file, "(lambda (file) (ir-rewrite-file file (lambda (node) (if (ir-integer? node) (ir-with-integer node (+ (ir-integer node) 2)) node))))",
  )
  let entry = @ir.FQName::parse("user:main#main")
  inspect(
    @scheme.value_to_string(@backend.run_file(transformed, entry, [])),
    content="42",
  )
  inspect(
    @scheme.value_to_string(@backend.run_file(file, entry, [])),
    content="40",
  )
}
```

```mbt check
///|
test "transform_file needs a procedure that returns a file" {
  let file = @frontend.compile_file("40")
  let not_procedure = try {
    ignore(@pipeline.transform_file(file, "42"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(not_procedure, content="Expected procedure")
  let not_file = try {
    ignore(@pipeline.transform_file(file, "(lambda (file) 42)"))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(not_file, content="Expected Morphir IR file")
}
```

In the Scheme examples of this chapter, each block is evaluated in a runtime made by `new_runtime()`.
Its printed result is compared with the `;; =>` line, and the start of its error message with the `;; error:` line.
A script gets its file from the host, so the examples read one from IR JSON text with `ir-read`.
This example defines a script and applies it to a file with one value, `p:m#v`, whose body is the integer 40.

```scheme
(define add-two
  (lambda (file)
    (ir-rewrite-file file
      (lambda (node)
        (if (ir-integer? node)
            (ir-with-integer node (+ (ir-integer node) 2))
            node)))))
(ir-write (add-two (ir-read "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"p\",\"dependencies\":{},\"def\":{\"modules\":{\"m\":{\"Public\":{\"types\":{},\"values\":{\"v\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":40}}}}}}}}}}}}}")))
;; => "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"p\",\"dependencies\":{},\"def\":{\"modules\":{\"m\":{\"Public\":{\"types\":{},\"values\":{\"v\":{\"Public\":{\"ExpressionBody\":{\"inputTypes\":{},\"outputType\":\"morphir/SDK:basics#int\",\"body\":{\"Literal\":{\"IntegerLiteral\":42}}}}}}}}}}}}}"
```

## The session

`new_runtime()` makes a persistent session, and calls `install` on it.
Definitions made by one `eval` of the session stay for the next.
`install` first calls `backend.install` with its default options.
So the session also has the procedures that emitted Scheme text calls, as
[Running Morphir IR](../backend/README.mbt.md#install-and-its-options) describes.
Then `install` adds the procedures below.

| Procedure | Arguments | Result |
| --- | --- | --- |
| `ir-read` | IR JSON text of any supported format version | An IR file in the current model |
| `ir-write` | An IR file | Its JSON text in the current format |
| `ir-value-read` | The JSON text of one IR value | An IR value |
| `ir-value-write` | An IR value | Its JSON text |
| `ir->datum` | An IR value | Its JSON as Scheme data |
| `datum->ir` | Scheme data in the JSON shape of an IR value | An IR value |
| `json-read` | JSON text | Scheme data |
| `json-write` | Scheme data | JSON text |
| `scheme->ir` | Scheme source text of one expression | An IR value |
| `ir->scheme` | An IR value | Its emitted Scheme text |
| `ir-eval` | An IR value | Its Scheme value |
| `ir-kind` | An IR value | The name of its constructor |
| `ir-integer?` | An IR value | Whether it is an integer literal |
| `ir-integer` | An IR integer literal | Its exact integer |
| `ir-with-integer` | An IR integer literal and an exact integer | The literal with the new integer |
| `ir-rewrite` | An IR value and a procedure | The rewritten value |
| `ir-rewrite-file` | An IR file and a procedure | The rewritten file |

An IR value prints as `#<morphir-value>`, and an IR file prints as `#<morphir-file>`.

Every procedure first checks how many arguments it has.
Then each argument that must be a string, an IR value or an IR file is checked when the procedure uses it.
These checks give the same messages in every procedure.

| Problem | Error message |
| --- | --- |
| The wrong number of arguments | `<procedure>: expected <count> arguments` |
| A string was expected | `Expected string` |
| An IR value was expected | `Expected Morphir IR value` |
| An IR file was expected | `Expected Morphir IR file` |

```scheme
(ir-kind (scheme->ir "1") (scheme->ir "2"))
;; error: ir-kind: expected 1 arguments
```

```scheme
(ir-kind 42)
;; error: Expected Morphir IR value
```

## Procedures

### ir-read

`(ir-read text)` reads IR JSON text and returns an IR file in the current model.
It accepts every supported format version, as described in [Versioned reading](#versioned-reading).

```scheme
(ir-read "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"test\"]],[],{\"modules\":[]}]}")
;; => #<morphir-file>
```

Text that is not IR JSON raises an error.
Today the message names only the error, not its details.
That is current behaviour, tracked by bead `morphir-ukvn.5.52`.

```scheme
(ir-read "{}")
;; error: finos/morphir-ir/wire.CodecError.Invalid
```

A format version that is not supported raises an error of its own.

```scheme
(ir-read "{\"formatVersion\":9}")
;; error: finos/morphir-ir/version.VersionError.UnsupportedMajor
```

### ir-write

`(ir-write file)` returns the JSON text of an IR file in the current format.

```scheme
(ir-write (ir-read "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"test\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"))
;; => "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"test\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"
```

```scheme
(ir-write (scheme->ir "1"))
;; error: Expected Morphir IR file
```

### ir-value-read

`(ir-value-read text)` reads the JSON text of one IR value in the current model.

```scheme
(ir-eval (ir-value-read "{\"Literal\":{\"IntegerLiteral\":40}}"))
;; => 40
```

```scheme
(ir-value-read 40)
;; error: Expected string
```

Text that is not the JSON of an IR value raises an error.
As with `ir-read`, the message names only the error, which bead `morphir-ukvn.5.52` tracks.

```scheme
(ir-value-read "{}")
;; error: finos/morphir-ir/wire.CodecError.Invalid
```

### ir-value-write

`(ir-value-write value)` returns the JSON text of one IR value.
A value made by `scheme->ir` carries the type that the frontend gave it.

```scheme
(ir-value-write (scheme->ir "42"))
;; => "{\"Literal\":{\"attributes\":{\"inferredType\":\"morphir/SDK:basics#int\"},\"literal\":{\"IntegerLiteral\":42}}}"
```

### ir->datum

`(ir->datum value)` returns the JSON of an IR value as Scheme data.
The data follows the rules of [The JSON bridge](#the-json-bridge): an object becomes a record.

```scheme
(ir->datum (ir-value-read "{\"Variable\":\"x\"}"))
;; => #<record Variable="x">
```

### datum->ir

`(datum->ir datum)` reads Scheme data in the JSON shape of an IR value.
It is the inverse of `ir->datum`.

```scheme
(ir-eval (datum->ir (record (cons "Literal" (record (cons "IntegerLiteral" 42))))))
;; => 42
```

Data that has no JSON form is refused.

```scheme
(datum->ir (lambda (x) x))
;; error: Value has no JSON representation
```

### json-read

`(json-read text)` reads JSON text as Scheme data.
[The JSON bridge](#the-json-bridge) lists how each JSON value maps.

```scheme
(json-read "{\"a\": [1, 2.5, true], \"b\": null}")
;; => #<record a=(1 2.5 #t) b=#<unit>>
```

Text that is not JSON raises an error.
As with `ir-read`, the message names only the error, which bead `morphir-ukvn.5.52` tracks.

```scheme
(json-read "[1,")
;; error: finos/morphir-ir/wire.CodecError.Invalid
```

### json-write

`(json-write datum)` returns Scheme data as JSON text.

```scheme
(json-write (record (cons "a" 1) (cons "b" (list #t "x"))))
;; => "{\"a\":1,\"b\":[true,\"x\"]}"
```

```scheme
(json-write 'a)
;; error: Value has no JSON representation
```

### scheme->ir

`(scheme->ir text)` compiles one Scheme expression to IR with the frontend's `compile_expression`.
[Writing models](../frontend/README.mbt.md) describes the Scheme it accepts.

```scheme
(ir-kind (scheme->ir "(lambda (x) x)"))
;; => "Lambda"
```

The frontend's errors pass through.

```scheme
(scheme->ir "(define x 1)")
;; error: Unsupported: Cannot lower define to functional Morphir IR
```

### ir->scheme

`(ir->scheme value)` returns the Scheme text that the backend's `emit_expression` writes for an IR value.
[Running Morphir IR](../backend/README.mbt.md#emitting-scheme-text) describes that text.

```scheme
(ir->scheme (scheme->ir "(+ 40 2)"))
;; => "(((r:morphir/SDK:basics#add) 40) 2)"
```

### ir-eval

`(ir-eval value)` runs an IR value with the backend's `evaluate_in`, in the session that calls it.
The value can use every binding of the session, including the host procedures registered in it.

```scheme
(ir-eval (scheme->ir "(+ 40 2)"))
;; => 42
```

```scheme
(ir-eval (scheme->ir "(+ 40 2)") 1)
;; error: ir-eval: expected 1 arguments
```

### ir-kind

`(ir-kind value)` returns the name of the value's IR constructor, as its JSON spells it.

```scheme
(list (ir-kind (scheme->ir "42"))
      (ir-kind (scheme->ir "x"))
      (ir-kind (scheme->ir "(+ 1 2)"))
      (ir-kind (scheme->ir "(if #t 1 2)"))
      (ir-kind (scheme->ir "(let ((x 1)) x)"))
      (ir-kind (scheme->ir "'(1 2)")))
;; => ("Literal" "Variable" "Apply" "IfThenElse" "LetDefinition" "List")
```

### ir-integer?

`(ir-integer? value)` is `#t` when the value is an integer literal, and `#f` otherwise.

```scheme
(list (ir-integer? (scheme->ir "42")) (ir-integer? (scheme->ir "\"42\"")) (ir-integer? (scheme->ir "1.5")))
;; => (#t #f #f)
```

### ir-integer

`(ir-integer value)` returns the exact integer of an integer literal.
The integer has no size limit.

```scheme
(ir-integer (scheme->ir "12345678901234567890"))
;; => 12345678901234567890
```

```scheme
(ir-integer (scheme->ir "1.5"))
;; error: Expected IR integer literal
```

### ir-with-integer

`(ir-with-integer value n)` returns the integer literal `value` with the exact integer `n` in place of its own.
The literal keeps its attributes, including its source location and its type.

```scheme
(ir-value-write (ir-with-integer (scheme->ir "40") 42))
;; => "{\"Literal\":{\"attributes\":{\"inferredType\":\"morphir/SDK:basics#int\"},\"literal\":{\"IntegerLiteral\":42}}}"
```

The value must be an integer literal, and `n` must be an exact integer.

```scheme
(ir-with-integer (scheme->ir "40") 1.5)
;; error: Expected IR integer and exact integer replacement
```

### ir-rewrite

`(ir-rewrite value procedure)` rewrites an IR value bottom-up, as described in [Bottom-up rewriting](#bottom-up-rewriting).
The procedure takes one IR value and returns its replacement.

```scheme
(ir-eval
  (ir-rewrite (scheme->ir "(+ 20 20)")
    (lambda (node)
      (if (ir-integer? node)
          (ir-with-integer node (+ (ir-integer node) 1))
          node))))
;; => 42
```

The procedure must return an IR value.

```scheme
(ir-rewrite (scheme->ir "1") (lambda (node) 5))
;; error: Expected Morphir IR value
```

The second argument must be a procedure.

```scheme
(ir-rewrite (scheme->ir "1") 5)
;; error: Expected procedure
```

### ir-rewrite-file

`(ir-rewrite-file file procedure)` rewrites every value of an IR file bottom-up and returns the new file.
The example in [Scripts](#scripts) uses it.
A file with no values comes back unchanged, and the procedure is not called.
In this example the procedure would raise an error if it were called.

```scheme
(define file (ir-read "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"test\"]],[],{\"modules\":[]}]}"))
(equal? (ir-write (ir-rewrite-file file (lambda (node) (error "called"))))
        (ir-write file))
;; => #t
```

```scheme
(ir-rewrite-file (scheme->ir "1") (lambda (node) node))
;; error: Expected Morphir IR file
```

## Bottom-up rewriting

`ir-rewrite` and `ir-rewrite-file` follow the same rules.

- The children of an expression are rewritten before the expression itself.
- The procedure then receives the expression with its rewritten children.
- What the procedure returns is not visited again.
- Patterns, types, attributes, documentation and access are kept as they are.
- The input is not changed.
- A value more than 256 levels below the root raises `Limit exceeded: IR rewrite depth`.
  The root is at level 0, so a value at level 256 is still rewritten.

This example records the kind of each value that the procedure receives.
The reference to `add` and the literal 1 come before the inner application, which comes before the literal 2 and the
outer application.

```scheme
(define seen '())
(ir-rewrite (scheme->ir "(+ 1 2)")
  (lambda (node)
    (set! seen (cons (ir-kind node) seen))
    node))
(reverse seen)
;; => ("Reference" "Literal" "Apply" "Literal" "Apply")
```

A replacement is not visited again.
Here each integer becomes `(+ 1 1)`, whose own integers are not replaced, so `(* 3 4)` becomes `(* (+ 1 1) (+ 1 1))`.

```scheme
(ir-eval
  (ir-rewrite (scheme->ir "(* 3 4)")
    (lambda (node)
      (if (ir-integer? node) (scheme->ir "(+ 1 1)") node))))
;; => 4
```

The input is not changed.

```scheme
(define before (scheme->ir "40"))
(define after (ir-rewrite before (lambda (node) (ir-with-integer node 42))))
(list (ir-integer before) (ir-integer after))
;; => (40 42)
```

The examples cannot reach this limit from Scheme, because `scheme->ir` and `ir-value-read` refuse input that deep first.
This MoonBit test calls `rewrite_value`, which `ir-rewrite` uses, on lists nested 256 and 257 levels deep.

```mbt check
///|
test "the rewrite depth limit is 256 levels below the root" {
  fn nest(levels : Int32) -> @ir.Value {
    let mut value = @ir.Value::Unit(@ir.ValueAttributes::default())
    for _ in 0..<levels {
      value = @ir.Value::List(@ir.ValueAttributes::default(), [value])
    }
    value
  }
  let deepest = nest(256)
  inspect(@pipeline.rewrite_value(deepest, v => v) == deepest, content="true")
  let too_deep = try {
    ignore(@pipeline.rewrite_value(nest(257), v => v))
    ""
  } catch {
    e => @scheme.error_message(e)
  }
  inspect(too_deep, content="Limit exceeded: IR rewrite depth")
}
```

The table lists the children that are rewritten for each kind of expression.

| Expression | Children rewritten |
| --- | --- |
| `Tuple`, `List` | Every item |
| `Record` | Every field value |
| `Apply` | The function and the argument |
| `Field` | The record |
| `Lambda` | The body, not the pattern |
| `LetDefinition` | The definition's body and the rest |
| `LetRecursion` | Every definition's body and the rest |
| `Destructure` | The value and the body, not the pattern |
| `IfThenElse` | The condition and both branches |
| `PatternMatch` | The value and every case body, not the patterns |
| `UpdateRecord` | The record and every new field value |
| `Literal`, `Constructor`, `Variable`, `Reference`, `FieldFunction`, `Unit`, `Hole` | None |

A definition's body is rewritten as follows.

| Definition | What is rewritten |
| --- | --- |
| An expression body | The body |
| An external body | The fallback body, when there is one |
| An incomplete body | The partial body, when there is one |
| A native body | Nothing |

`ir-rewrite-file` rewrites the definition of every value in every module.

| Distribution | What is rewritten |
| --- | --- |
| A library | The values of its package |
| An application | The values of its package and of every dependency package it carries; its entry points are kept |
| A specification set | Nothing, because it has no definitions |

## Versioned reading

`ir-read` reads IR JSON in format versions 1 to 4, including the canonical Elm encodings of versions 1 to 3.
It reads the file with the codec of its `formatVersion`, then migrates it to the current model.
Migration gives the classic let placeholders of versions 1 to 3 the unknown-type marker.
The current model follows the latest supported IR, and `ir-write` writes it as format version 4.
So reading and then writing a file converts it to the current format.

```scheme
(ir-write (ir-read "{\"formatVersion\":3,\"distribution\":[\"Library\",[[\"test\"]],[],{\"modules\":[]}]}"))
;; => "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"test\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"
```

A version 1 file uses the classic lower-case tags.

```scheme
(ir-write (ir-read "{\"formatVersion\":1,\"distribution\":[\"library\",[[\"test\"]],[],{\"modules\":[]}]}"))
;; => "{\"formatVersion\":4,\"distribution\":{\"Library\":{\"packageName\":\"test\",\"dependencies\":{},\"def\":{\"modules\":{}}}}}"
```

`ir-value-read`, `ir-value-write`, `ir->datum` and `datum->ir` use the current model only.

## The JSON bridge

`json-read`, `json-write`, `ir->datum` and `datum->ir` share one mapping between JSON and Scheme data.

| JSON | Scheme |
| --- | --- |
| `null` | The unit value, printed `#<unit>` |
| `true`, `false` | `#t`, `#f` |
| A string | A string |
| A number written as an integer | An exact integer, of any size |
| A number with a fraction or an exponent | An inexact real |
| An array | A list |
| An object | A record, with its fields in their JSON order |

A number with a fraction or an exponent is read as an inexact real, even when its value is whole.

```scheme
(list (json-read "1") (json-read "1.0") (json-read "1e3") (json-read "2.5"))
;; => (1 1.0 1000.0 2.5)
```

Writing goes the other way, with two additions: a vector also becomes an array, and an inexact real with no fraction
is written as an integer.

```scheme
(json-write (list (json-read "1.0") (vector 1 2) (unit)))
;; => "[1,[1,2],null]"
```

A record keeps the order of its fields.

```scheme
(json-write (json-read "{\"b\": 1, \"a\": 2}"))
;; => "{\"b\":1,\"a\":2}"
```

Any other value has no JSON form: a symbol, a character, a procedure, a rational such as `1/2`, a tagged value, or an
IR value, type or file.
Converting one to JSON raises `Value has no JSON representation`.

```scheme
(json-write 1/2)
;; error: Value has no JSON representation
```

A list must be a proper list.

```scheme
(json-write (cons 1 2))
;; error: Expected proper list
```

A JSON number too large for a real is refused.

```scheme
(json-read "1e400")
;; error: Nonfinite number
```

Converting data to JSON raises `Limit exceeded: JSON conversion depth` for a value more than 256 levels below the
root, which is at level 0.
Here `nest` wraps the number 1 in lists, so the number ends up that many levels below the root.

```scheme
(define (nest levels)
  (let loop ((n levels) (value 1))
    (if (= n 0) value (loop (- n 1) (list value)))))
(define deepest (nest 256))
(equal? (json-read (json-write deepest)) deepest)
;; => #t
```

```scheme
(define (nest levels)
  (let loop ((n levels) (value 1))
    (if (= n 0) value (loop (- n 1) (list value)))))
(json-write (nest 257))
;; error: Limit exceeded: JSON conversion depth
```

## Scripts in morphir.config.scm

The Morphir engine runs transforms from a `morphir.config.scm` file.
Its script is evaluated in a session made by `new_runtime()`, so it can use every procedure of this chapter.
The engine adds the option procedures `frontend`, `frontend-provider`, `frontend-profile`, `backend`, `output`,
`source`, `package-name`, `inference`, `transform` and `pipeline`.
The script returns a `pipeline` of options.
Each `transform` takes a procedure from IR file to IR file.
The transforms run in order, on every file, after the frontend and before the backend.
While they run, `source-path` and `project-root` are strings in the session.

The example below is not checked, because it needs the engine.
[Script configuration](../../morphir-engine/README.md#script-configuration) in the engine README describes the
options, their defaults and their precedence.

```scheme notest
;; morphir.config.scm
(define (rewrite-integers f)
  (lambda (file)
    (ir-rewrite-file file
      (lambda (node)
        (if (ir-integer? node)
            (ir-with-integer node (f (ir-integer node)))
            node)))))

(pipeline
  (frontend "scheme")
  (backend "ir-json")
  (source "src")
  (output "generated")
  (package-name "acme/pricing")
  (transform (rewrite-integers (lambda (n) (* n 100))))
  (transform (rewrite-integers (lambda (n) (+ n 1)))))
```
