// Windows tests. The command-line tests run everywhere; the job object tests
// are in windows_wbtest.mbt.

///|
/// Splits the arguments after the program name the way the Microsoft C
/// runtime and `CommandLineToArgvW` do: `2n` backslashes before a quote give
/// `n` backslashes and toggle quoting, `2n + 1` give `n` and a literal quote,
/// other backslashes are literal, and a space or tab ends an argument
/// outside quotes.
fn split_arguments(line : String) -> Array[String] {
  let chars = line.to_array()
  let mut i = 0
  // The program name is always quoted and holds no quote.
  guard chars is ['"', ..] else { abort("unquoted program name") }
  i = 1
  while chars[i] != '"' {
    i += 1
  }
  i += 1
  let args = []
  while true {
    while i < chars.length() && (chars[i] == ' ' || chars[i] == '\t') {
      i += 1
    }
    if i >= chars.length() {
      break
    }
    let arg = StringBuilder()
    let mut quoted = false
    while i < chars.length() {
      let c = chars[i]
      if c == '\\' {
        let mut slashes = 0
        while i < chars.length() && chars[i] == '\\' {
          slashes += 1
          i += 1
        }
        if i < chars.length() && chars[i] == '"' {
          for _ in 0..<(slashes / 2) {
            arg.write_char('\\')
          }
          if slashes % 2 == 1 {
            arg.write_char('"')
            i += 1
          }
        } else {
          for _ in 0..<slashes {
            arg.write_char('\\')
          }
        }
        continue
      }
      if c == '"' {
        quoted = !quoted
        i += 1
        continue
      }
      if !quoted && (c == ' ' || c == '\t') {
        break
      }
      arg.write_char(c)
      i += 1
    }
    args.push(arg.to_string())
  }
  args
}

///|
test "a Windows command line quotes an argument only when it needs it" {
  assert_eq(
    @native.windows_command_line("C:\\Windows\\System32\\cmd.exe", [
      "/d", "/c", "exit 3",
    ]),
    "\"C:\\Windows\\System32\\cmd.exe\" /d /c \"exit 3\"",
  )
  assert_eq(
    @native.windows_command_line("C:\\work\\bin\\worker.exe", [
      "", "a b", "say \"hi\"", "trailing\\", "C:\\dir\\", "--",
    ]),
    "\"C:\\work\\bin\\worker.exe\" \"\" \"a b\" \"say \\\"hi\\\"\" trailing\\ C:\\dir\\ --",
  )
  // Backslashes are doubled only before a quote, including the closing one.
  assert_eq(
    @native.windows_command_line("w.exe", ["a\\\\\"b", "a b\\", "a\\b"]),
    "\"w.exe\" \"a\\\\\\\\\\\"b\" \"a b\\\\\" a\\b",
  )
  // A tab, a newline and a vertical tab need quotes too.
  assert_eq(
    @native.windows_command_line("w.exe", ["a\tb", "a\nb", "a\u{0B}b"]),
    "\"w.exe\" \"a\tb\" \"a\nb\" \"a\u{0B}b\"",
  )
}

///|
test "a Windows command line splits back into the same arguments" {
  let cases : Array[Array[String]] = [
    [],
    [""],
    ["", ""],
    ["/d", "/c", "exit 3"],
    ["a b", "say \"hi\"", "trailing\\", "C:\\dir\\", "--", ""],
    ["a\\\\\"b", "a b\\", "a\\b", "\\\\", "\\\"", "\"", "\"\""],
    ["a\tb", "a\nb", "a\u{0B}b", " ", "\t", "λ 😀"],
  ]
  for args in cases {
    let line = @native.windows_command_line("C:\\w\\worker.exe", args[:])
    assert_eq(split_arguments(line), args, msg=line)
  }
}
