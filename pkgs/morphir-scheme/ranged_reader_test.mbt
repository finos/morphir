///|
test "ranged forms retain original boundaries after comments and CRLF" {
  let source = " ;a\r\n#; (ignored)\r\n(+ 1 2) ;tail\r\n'foo"
  let forms = @scheme.parse_program_ranged(source)
  assert_eq(forms.map(form => (form.scalar_start(), form.scalar_end())), [
    (19, 26),
    (34, 38),
  ])
  assert_eq(forms.map(form => form.datum()), @scheme.parse_program(source))
}

///|
test "ranged reader explicitly reports scalar coordinates for astral text" {
  let forms = @scheme.parse_program_ranged("\"😀\" #(#t #\\space)")
  assert_eq(forms.map(form => (form.scalar_start(), form.scalar_end())), [
    (0, 3),
    (4, 17),
  ])
}

///|
test "nested block and datum comments are trivia outside form spans" {
  let source = "#| outer #| inner |# |# #;(discarded) '(a . b)#(1 2)"
  let chars = source.iter().collect()
  let forms = @scheme.parse_program_ranged(source)
  assert_eq(
    forms.map(form => {
      String::from_array(chars[form.scalar_start():form.scalar_end()])
    }),
    ["'(a . b)", "#(1 2)"],
  )
  assert_eq(forms.map(form => form.datum()), @scheme.parse_program(source))
  assert_eq(@scheme.parse_program_ranged(" ;only\r\n#|comment|#").length(), 0)
}

///|
test "ranged reader never returns a valid prefix on syntax failure" {
  let rejected = try {
    @scheme.parse_program_ranged("(define x 1) (") |> ignore
    false
  } catch {
    @scheme.Syntax(_, offset) => {
      assert_eq(offset, 14)
      true
    }
    _ => false
  }
  assert_true(rejected)
}
