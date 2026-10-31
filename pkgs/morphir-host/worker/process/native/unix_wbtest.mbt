// White-box tests of the Unix stub: the artifact read limit and the clean-up
// when the host's pipe ends cannot become streams.

///|
#cfg(not(platform="windows"))
extern "C" fn is_end_ffi(fd : Int32, device : Int64, inode : Int64) -> Bool = "morphir_worker_is_end"

///|
#cfg(not(platform="windows"))
async fn fixture_staged() -> @shared.StagedArtifact {
  let path = @fs.realpath("worker/process/native/fixtures/worker.sh")
  stage(
    @worker.ArtifactRef::new(
      File(@worker.ArtifactPath::parse(path, Posix)),
      @worker.Sha256::of(@fs.read_file(path).binary()),
    ),
  )
}

///|
/// Starts the fixture through the stub alone and returns the host's ends and
/// the PID, so that a test can make the streams itself.
#cfg(not(platform="windows"))
fn start_ends(staged : @shared.StagedArtifact) -> (HostEnds, Int32) raise {
  let ends = HostEnds::{ fds: [-1, -1, -1], identity: FixedArray::make(6, 0L), }
  let pid : FixedArray[Int32] = [0]
  let executable = os_text(staged.executable())
  let error = spawn_ffi(
    executable,
    [executable, os_text("echo")],
    2,
    os_text(staged.working_directory()),
    ends.fds,
    ends.identity,
    pid,
  )
  assert_eq(error, 0)
  (ends, pid[0])
}

///|
#cfg(not(platform="windows"))
suberror WrapRefused

///|
#cfg(not(platform="windows"))
async test "a failed wrap closes the streams made and every pipe end left" {
  for failing in 0..<3 {
    for closes_first in [false, true] {
      let staged = fixture_staged()
      let (ends, pid) = start_ends(staged)
      // A file that may take the number of an end that the wrap closed.
      let mut other : @fs.File? = None
      let wrapped = try {
        ignore(
          ends.streams(wrap=end => {
            guard end == ends.fds[failing] else { wrap_end(end) }
            if closes_first {
              // As `RawFdStream` does when the event loop refuses the end.
              close_end_ffi(
                end,
                ends.identity[2 * failing],
                ends.identity[2 * failing + 1],
              )
              other = Some(
                @fs.open("worker/process/native/README.mbt.md", mode=ReadOnly),
              )
            }
            raise WrapRefused
          }),
        )
        true
      } catch {
        WrapRefused => false
        error => fail("unexpected error \{error}")
      }
      assert_false(wrapped)
      for i in 0..<3 {
        assert_false(
          is_end_ffi(
            ends.fds[i],
            ends.identity[2 * i],
            ends.identity[2 * i + 1],
          ),
          msg="end \{i} is open after wrap \{failing} failed",
        )
      }
      // The clean-up did not close a file that took a closed end's number.
      if other is Some(file) {
        assert_true(file.size() > 0L)
        file.close()
      }
      Tree::kill(ProcessGroup::{ pgid: pid, })
      assert_true(Leader::new(pid).wait_for(@shared.STOP_CONFIRM_MS) is Some(_))
      unstage(staged)
    }
  }
}

///|
#cfg(not(platform="windows"))
async test "an artifact read refuses a file above the largest byte array" {
  let directory = @fs.tmpdir(prefix="morphir-worker-test-")
  defer (@fs.rmdir(directory, recursive=true) catch { _ => () })
  let path = directory + "/large"
  // A sparse file of 2 GiB, one byte more than the largest MoonBit byte
  // array, takes no disk space.
  ignore(
    @process.run("/bin/dd", [
      "if=/dev/zero",
      "of=\{path}",
      "bs=1",
      "count=0",
      "seek=2147483648",
    ]),
  )
  let problem : FixedArray[Int32] = [0, 0]
  let bytes = read_artifact_ffi(os_text(path), 0x7FFFFFFFFFFFFFFFL, problem)
  assert_eq(problem[0], 3)
  assert_eq(bytes.length(), 0)
}

///|
#cfg(not(platform="windows"))
async test "a launch waits while another process briefly holds the copy open for writing" {
  // On Linux an exec of a file that is open for writing fails with
  // ETXTBSY. Another spawn's child can hold a staged copy open in this way
  // for a short time, until its own exec closes the copy.
  let staged = fixture_staged()
  let writer = @fs.open(staged.executable(), mode=WriteOnly)
  let stop = @async.with_task_group(group => {
    group.spawn_bg(() => {
      @async.sleep(100)
      writer.close()
    })
    let spawned = spawn(staged, ["echo"])
    let channel = ProcessChannel::new(
      spawned,
      staged,
      @worker.Limits::host(),
      grace_ms=@shared.EXIT_GRACE_MS,
      confirm_ms=@shared.STOP_CONFIRM_MS,
    )
    channel.close()
  })
  assert_eq(stop.status, Exited(code=0))
}
