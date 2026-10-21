///|
// Node owns the bounded line stream; the shared MoonBit component owns decoding.
extern "js" fn serve(handler : (String) -> String) -> Unit =
  #| (handler) => {
  #|   const limit = 2 * 1024 * 1024;
  #|   let pending = Buffer.alloc(0);
  #|   const decoder = new TextDecoder('utf-8', { fatal: true });
  #|   function fail() { process.stderr.write('workspace-files: invalid NDJSON framing\n'); process.exit(1); }
  #|   process.stdin.on('data', chunk => {
  #|     pending = Buffer.concat([pending, chunk]);
  #|     let end;
  #|     while ((end = pending.indexOf(10)) !== -1) {
  #|       if (end > limit) return fail();
  #|       try {
  #|         const line = decoder.decode(pending.subarray(0, end));
  #|         pending = pending.subarray(end + 1);
  #|         const response = handler(line);
  #|         if (response === '') { process.stdin.destroy(); return; }
  #|         process.stdout.write(response + '\n');
  #|       } catch { return fail(); }
  #|     }
  #|     if (pending.length > limit) fail();
  #|   });
  #|   process.stdin.on('end', () => { if (pending.length !== 0) fail(); });
  #|   process.stdin.on('error', fail);
  #|   process.stdout.on('error', fail);
  #| }

///|
fn main {
  serve(line => {
    let response = @mck.handle_line(line)
    match response {
      None => ""
      Some(value) => value.stringify()
    }
  })
}
