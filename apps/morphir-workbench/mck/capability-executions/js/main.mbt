///|
// Node owns the bounded line stream; the shared MoonBit component owns decoding.
extern "js" fn serve(handler : (String) -> String, events : Bool) -> Unit =
  #| (handler, events) => {
  #|   if (typeof process === 'undefined') {
  #|     // Private transport alias shared by independently loaded MCK pages.
  #|     globalThis.morphirCapabilityMck = handler;
  #|     return;
  #|   }
  #|   let sequence = 1;
  #|   const emit = (event, fields = {}) => process.stderr.write(JSON.stringify({profile:'morphir/command-event',contractVersion:'0.1.0',command:'workbench.mck.capability-executions.js',event,sequence:++sequence,...fields}) + '\n');
  #|   if (events) process.once('exit', code => emit('exit', {exitCode:code}));
  #|   const limit = 2 * 1024 * 1024;
  #|   let pending = Buffer.alloc(0);
  #|   const decoder = new TextDecoder('utf-8', { fatal: true });
  #|   function fail() { if (events) emit('failure', {error:{code:'transport_error',message:'invalid NDJSON framing or request'},exitCode:1}); else process.stderr.write('workbench: invalid NDJSON framing\n'); process.exit(1); }
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
  #|   if (events) emit('ready');
  #| }

///|
fn main {
  let mode = presentation_mode(presentation_args()[:]) catch {
    error => {
      presentation_write(
        presentation_event(1, "failure", {
          "error": {
            "code": "argument_error",
            "message": Json(error.to_string()),
          },
          "exitCode": 2,
        }),
      )
      presentation_exit(2)
      return
    }
  }
  let events = match mode {
    Human => false
    Events => true
    Help(text) => {
      presentation_write(presentation_help(text))
      return
    }
  }
  if events {
    presentation_write(presentation_event(1, "startup", {}))
  }
  serve(
    line => {
      let response = @mck.handle_line(line)
      match response {
        None => ""
        Some(value) => value.stringify()
      }
    },
    events,
  )
}
