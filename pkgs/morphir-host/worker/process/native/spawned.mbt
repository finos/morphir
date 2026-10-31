///|
/// How long a Unix launch tries again while the staged copy is busy. On
/// Linux, while the host stages one worker, another spawn's child can inherit
/// the copy's write descriptor and hold it until its own exec closes it; an
/// exec of the copy in that time fails with `ETXTBSY`.
pub const TEXT_BUSY_RETRY_MS : Int32 = 1000

///|
/// A started worker: its PID, its tree and the host's ends of its standard
/// streams.
priv struct Spawned {
  pid : Int32
  tree : &Tree
  stop_method : @worker.StopMethod
  input : &@io.Writer
  output : &@io.Reader
  errors : &@io.Reader
  close_streams : () -> Unit
  close_input : () -> Unit
}

///|
/// Makes streams of the host's three pipe ends with `wrap`, one at a time.
/// If a wrap raises, the streams already made are closed, `close_from(i)`
/// closes the ends from `i` that are not streams yet, and the error passes
/// on. The caller protects this from cancellation, so a cancellation takes
/// effect only after the streams are handed over.
async fn wrap_ends(
  ends : FixedArray[@types.Fd],
  wrap~ : async (@types.Fd) -> @raw_fd.RawFdStream,
  close_from~ : (Int32) -> Unit,
) -> (@raw_fd.RawFdStream, @raw_fd.RawFdStream, @raw_fd.RawFdStream) {
  let streams : Array[@raw_fd.RawFdStream] = []
  errdefer {
    streams.each(stream => stream.close())
    close_from(streams.length())
  }
  for end in ends {
    streams.push(wrap(end))
  }
  (streams[0], streams[1], streams[2])
}

///|
/// Makes a stream of one of the host's pipe ends.
async fn wrap_end(end : @types.Fd) -> @raw_fd.RawFdStream {
  @raw_fd.RawFdStream(end)
}

///|
/// Maps the problem code of `morphir_worker_read_artifact`. `detail` is the
/// operating system error, kept for diagnostics only.
fn artifact_problem(code : Int32, detail : Int32) -> @worker.ArtifactProblem {
  match code {
    1 => SymbolicLink
    2 => NotRegularFile
    3 => TooLarge
    _ =>
      Unreadable(
        detail=if detail == 0 { None } else { Some("os error \{detail}") },
      )
  }
}

///|
/// The command line that a Windows worker receives, quoted so that the
/// Microsoft C runtime (and `CommandLineToArgvW`) splits it back into exactly
/// `program` and `args`. The program is always quoted. An argument is quoted
/// only when it needs it: when it is empty or holds a space, a tab, a
/// newline, a vertical tab or a double quote, as Rust's `std::process` does.
/// So a program such as `cmd.exe`, which reads its switches from the raw
/// command line, sees `/c` and not `"/c"`. Inside quotes, backslashes are
/// doubled only before a quote, the closing one included.
pub fn windows_command_line(
  program : String,
  args : ArrayView[String],
) -> String {
  let line = StringBuilder()
  fn quote(argument : String) {
    line.write_char('"')
    let mut slashes = 0
    for c in argument {
      if c == '\\' {
        slashes += 1
        continue
      }
      let escaped = if c == '"' { slashes * 2 + 1 } else { slashes }
      for _ in 0..<escaped {
        line.write_char('\\')
      }
      line.write_char(c)
      slashes = 0
    }
    for _ in 0..<(slashes * 2) {
      line.write_char('\\')
    }
    line.write_char('"')
  }

  fn needs_quotes(argument : String) -> Bool {
    argument.is_empty() ||
    argument.iter().any(c => c is (' ' | '\t' | '\n' | '\u{0B}' | '"'))
  }

  quote(program)
  for argument in args {
    line.write_char(' ')
    if needs_quotes(argument) {
      quote(argument)
    } else {
      line.write_string(argument)
    }
  }
  line.to_string()
}

///|
extern "C" fn process_alive_ffi(pid : Int32) -> Bool = "morphir_worker_process_alive"

///|
/// Whether a process with this ID runs on the host. A process that has
/// exited but is not reaped yet does not run.
pub fn process_alive(pid : Int32) -> Bool {
  process_alive_ffi(pid)
}
