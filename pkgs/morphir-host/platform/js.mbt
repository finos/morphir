///|
#external
priv type Stats

///|
#module("node:fs")
extern "js" fn lstat(path : String) -> Stats = "lstatSync"

///|
#module("node:fs")
extern "js" fn rename_sync(a : String, b : String) -> Unit = "renameSync"

///|
extern "js" fn kind_js(stat : (String) -> Stats, path : String) -> Int32 =
  #| (stat,path) => { try { const s = stat(path); return s.isSymbolicLink() ? 3 : s.isDirectory() ? 2 : s.isFile() ? 1 : 4; } catch(e) { return e.code === 'ENOENT' || e.code === 'ENOTDIR' ? 0 : -1; } }

///|
extern "js" fn rename_js(
  rename : (String, String) -> Unit,
  a : String,
  b : String,
) -> Int32 =
  #| (rename,a,b) => { try { rename(a,b); return 0; } catch { return -1; } }

///|
pub fn kind(path : String) -> Int32 raise {
  let result = kind_js(lstat, path)
  if result < 0 {
    raise IOError("Cannot inspect " + path)
  }
  result
}

///|
extern "js" fn rename_directory_new_js(a : String, b : String) -> Int32 =
  #| (a,b)=>{
  #|   const fs=process.getBuiltinModule('node:fs'); let owned;
  #|   if(process.platform==='win32'){
  #|     // Windows never renames a directory onto an existing directory, so a
  #|     // reservation would block the rename. Node has no no-replace rename:
  #|     // check, then rename, then classify a failure by what is at b.
  #|     try { if(!fs.lstatSync(a).isDirectory()) return 2; } catch { return 2; }
  #|     try { fs.lstatSync(b); return 1; } catch(e) { if(e.code!=='ENOENT') return 1; }
  #|     try { fs.renameSync(a,b); return 0; }
  #|     catch {
  #|       try { fs.lstatSync(b); return 1; } catch(e) { if(e.code!=='ENOENT') return 1; }
  #|       // As with mkdir on POSIX, a missing parent of b is an unavailable destination.
  #|       try { return fs.statSync(process.getBuiltinModule('node:path').dirname(b)).isDirectory() ? 2 : 1; }
  #|       catch { return 1; }
  #|     }
  #|   }
  #|   try { fs.mkdirSync(b,{mode:0o700}); } catch { return 1; }
  #|   try { owned=fs.lstatSync(b,{bigint:true}); fs.renameSync(a,b); return 0; }
  #|   catch {
  #|     try { const current=fs.lstatSync(b,{bigint:true});
  #|       if(!owned||current.dev!==owned.dev||current.ino!==owned.ino||!current.isDirectory()) return 3;
  #|       fs.rmdirSync(b); return 2;
  #|     } catch { return 3; }
  #|   }
  #| }

///|
/// Publish the complete tree at a previously absent destination; never
/// replace one. On POSIX, reserve the destination with an exclusive mkdir,
/// then rename onto the reservation; a populated reservation is never replaced
/// or recursively removed. Windows refuses to rename a directory onto an
/// existing directory, so there the adapter checks that the destination is
/// absent and renames without a reservation. Node exposes no no-replace
/// rename, so a residual race remains on Windows: an entry created at the
/// destination between the check and the rename. A directory there makes the
/// rename fail, reported as `destination_unavailable`. A file there meets
/// libuv's replacing MoveFileExW, which Windows documents as unusable when the
/// source is a directory, so that rename is expected to fail as well. The
/// native Windows host refuses an existing destination in the rename call
/// itself and has no such window.
pub fn rename_directory_new(a : String, b : String) -> Unit raise {
  match rename_directory_new_js(a, b) {
    0 => ()
    1 => raise IOError("publication.destination_unavailable: " + b)
    2 => raise IOError("publication.create_failed: " + b)
    _ => raise IOError("publication.reservation_cleanup_failed: " + b)
  }
}

///|
extern "js" fn list_bounded_js(
  path : String,
  limit : Int32,
  stopped : () -> Bool,
) -> String =
  #| (path,limit,stopped) => {
  #|   try {
  #|     const fs=process.getBuiltinModule('node:fs');
  #|     if (!fs.lstatSync(path).isDirectory()) throw new Error('directory.open_failed');
  #|     const dir=fs.opendirSync(path,{encoding:'buffer',bufferSize:1});
  #|     const names=[]; let units=0;
  #|     try {
  #|       for (;;) {
  #|         if (stopped()) return JSON.stringify({cancelled:true});
  #|         const entry=dir.readSync(); if (!entry) break;
  #|         if (names.length>=limit) throw new Error('directory.entry_limit');
  #|         const name=new TextDecoder('utf-8',{fatal:true,ignoreBOM:true}).decode(entry.name);
  #|         if (name.length>4096 || name.length>1048576-units) throw new Error('directory.name_limit');
  #|         units+=name.length; names.push(name);
  #|       }
  #|     } finally { dir.closeSync(); }
  #|     return JSON.stringify({value:names});
  #|   } catch(error) { return JSON.stringify({error:String(error.message||error)}); }
  #| }

///|
fn directory_list(path : String, limit : Int32) -> Array[String] raise {
  match @json.parse(list_bounded_js(path, limit, interruption_requested)) {
    { "value": Array(items), .. } if items.length() <= limit => {
      let mut units = 0
      items.map(fn(item) raise {
        match item {
          String(name) => {
            units = directory_name(name, units)
            name
          }
          _ => raise IOError("directory.invalid_response")
        }
      })
    }
    { "cancelled": true, .. } => raise Interrupted
    { "error": String(message), .. } => raise IOError(message)
    _ => raise IOError("directory.invalid_response")
  }
}

///|
pub fn rename(a : String, b : String) -> Unit raise {
  check(rename_js(rename_sync, a, b), "rename")
}

///|
#module("node:fs")
extern "js" fn link_sync(a : String, b : String) -> Unit = "linkSync"

///|
pub fn link_file_new(a : String, b : String) -> Unit raise {
  check(rename_js(link_sync, a, b), "link file without replacement")
}

///|
pub extern "js" fn stderr(text : String) -> Unit =
  #| text => process.stderr.write(text)

///|
pub extern "js" fn exit(code : Int32) -> Unit =
  #| code => { process.exitCode = code; }

///|
pub fn arguments() -> Array[String] {
  args()[2:].to_owned()
}

///|
pub extern "js" fn system_type() -> String =
  #| () => process.platform === 'darwin' ? 'macos' : process.platform === 'win32' ? 'windows' : 'linux'

///|
extern "js" fn size_js(stat : (String) -> Stats, path : String) -> Int32 =
  #| (stat,path) => { try { return Math.min(stat(path).size,16777217); } catch { return -1; } }

///|
fn size(path : String) -> Int32 {
  size_js(lstat, path)
}

///|
#module("node:fs")
extern "js" fn mkdir_sync(path : String) -> Unit = "mkdirSync"

///|
extern "js" fn mkdir_js(create : (String) -> Unit, path : String) -> Int32 =
  #| (create,path) => { try { create(path); return 0; } catch { return -1; } }

///|
pub fn mkdir(path : String) -> Unit raise {
  check(mkdir_js(mkdir_sync, path), "exclusive mkdir " + path)
}

///|
pub extern "js" fn architecture() -> String =
  #| () => process.arch

///|
pub fn process_supported() -> Bool {
  true
}

///|
#module("node:fs")
extern "js" fn mkdtemp(prefix : String) -> String = "mkdtempSync"

///|
#module("node:os")
extern "js" fn tmpdir() -> String = "tmpdir"

///|
/// Keep the fallible signature shared by all target adapters at this FFI boundary.
#warnings("-unused_error_type")
pub fn temporary() -> String raise {
  mkdtemp(tmpdir() + "/morphir-toolchain-")
}

///|
#external
priv type Process

///|
#module("node:child_process")
extern "js" fn spawn(
  program : String,
  args : FixedArray[String],
  options : Process,
) -> Process = "spawnSync"

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> Json raise {
  @json.parse(
    execute_js(
      spawn,
      program,
      FixedArray::from_array(args),
      cwd,
      home,
      timeout,
      process_stop_code,
      process_started,
    ),
  )
}

///|
pub extern "js" fn monotonic_seconds() -> Double = "() => Number(process.hrtime.bigint()) / 1e9"

///|
pub extern "js" fn wall_seconds() -> Double = "() => Date.now() / 1000"

///|
#module("node:crypto")
pub extern "js" fn observation_id() -> String = "randomUUID"

///|
extern "js" fn flush_file_js(
  spawn : (String, FixedArray[String], Process) -> Process,
  path : String,
  data : Bytes,
  timeout : Int32,
  root : String,
) -> Bool =
  #| (spawn,path,data,timeout,root) => {
  #|   const script=`const fs=require('fs'),path=process.argv[1],root=process.argv[2];
  #|     if(path==='@stderr'){fs.writeFileSync(2,fs.readFileSync(0));process.exit(0);}
  #|     if(root){
  #|       const prefix=root+'/.morphir/logs/';if(!path.startsWith(prefix))throw Error('log path outside root');
  #|       let current=root;if(!fs.lstatSync(current).isDirectory())throw Error('log root requires directory');
  #|       for(const part of path.slice(root.length+1).split('/').slice(0,-1)){
  #|         if(!part||part==='.'||part==='..'||part.includes('\\\\')||part.includes(':'))throw Error('invalid log path');
  #|         current+='/'+part;try{fs.mkdirSync(current,{mode:0o700});}catch(e){if(e.code!=='EEXIST')throw e;}
  #|         if(!fs.lstatSync(current).isDirectory())throw Error('log parent requires directory');
  #|       }
  #|     }
  #|     function exists(p){try{const s=fs.lstatSync(p);if(!s.isFile())throw Error('regular file required');return true;}catch(e){if(e.code==='ENOENT')return false;throw e;}}
  #|     for(let i=3;i>=1;i--){const old=i===1?path:path+'.'+(i-1),dest=path+'.'+i;if(exists(old)){if(exists(dest))fs.unlinkSync(dest);fs.renameSync(old,dest);}}
  #|     const fd=fs.openSync(path,fs.constants.O_WRONLY|fs.constants.O_CREAT|fs.constants.O_EXCL|fs.constants.O_NONBLOCK,0o600);
  #|     try{fs.writeFileSync(fd,fs.readFileSync(0));}finally{fs.closeSync(fd);}`;
  #|   if(data.length>4194304||timeout<1||timeout>5000)return false;
  #|   try{const r=spawn(process.execPath,['-e',script,path,root],{input:data,timeout,killSignal:'SIGKILL',maxBuffer:1024,windowsHide:true,...(path==='@stderr'?{stdio:['pipe','ignore','inherit']}:{})});return !r.error&&r.status===0;}catch{return false;}
  #| }

///|
pub fn flush_file(
  path : String,
  data : Bytes,
  timeout : Int32,
  root~ : String = "",
) -> Bool {
  flush_file_js(spawn, path, data, timeout, root)
}

///|
#module("node:fs")
extern "js" fn read_sync(
  fd : Int32,
  buffer : FixedArray[Byte],
  offset : Int32,
  length : Int32,
) -> Int32 = "readSync"

///|
#module("node:fs")
extern "js" fn close_sync(fd : Int32) -> Unit = "closeSync"

///|
#module("node:fs")
extern "js" fn fstat(fd : Int32) -> Stats = "fstatSync"

///|
extern "js" fn file_open_js(
  stat : (Int32) -> Stats,
  close : (Int32) -> Unit,
  path : String,
  limit : Int32,
) -> Int32 =
  #| (stat,close,path,limit) => {let fd=-1;try{const fs=process.getBuiltinModule('node:fs');fd=fs.openSync(path,fs.constants.O_RDONLY|(fs.constants.O_NONBLOCK||0)|(fs.constants.O_NOFOLLOW||0));const s=stat(fd);if(!s.isFile()||s.size<0||s.size>limit)throw Error();return fd;}catch{if(fd>=0)close(fd);return -1;}}

///|
fn file_open(path : String, limit : Int32) -> Int32 {
  file_open_js(fstat, close_sync, path, limit)
}

///|
extern "js" fn file_read_js(
  read : (Int32, FixedArray[Byte], Int32, Int32) -> Int32,
  fd : Int32,
  buffer : FixedArray[Byte],
  length : Int32,
) -> Int32 =
  #| (read,fd,buffer,length) => {try{return read(fd,buffer,0,length);}catch{return -1;}}

///|
fn file_read(fd : Int32, buffer : FixedArray[Byte], length : Int32) -> Int32 {
  file_read_js(read_sync, fd, buffer, length)
}

///|
extern "js" fn file_close_js(close : (Int32) -> Unit, fd : Int32) -> Int32 =
  #| (close,fd) => {try{close(fd);return 0;}catch{return -1;}}

///|
fn file_close(fd : Int32) -> Int32 {
  file_close_js(close_sync, fd)
}

///|
/// Probe the host API used by bounded pin reads before acquiring a session.
pub extern "js" fn file_chunks_supported() -> Bool =
  #| () => {try {const fs=process.getBuiltinModule?.('node:fs');return !!fs&&['openSync','readSync','fstatSync','closeSync'].every(name=>typeof fs[name]==='function');}catch{return false;}}

///|
extern "js" fn shared_stdin_read(
  buffer : FixedArray[Byte],
  length : Int32,
  interrupted : () -> Bool,
) -> Int32 =
  #| (buffer, length, interrupted) => typeof globalThis.__morphirStdinRead === 'function' ? globalThis.__morphirStdinRead(buffer, length, interrupted) : -2

///|
fn stdin_read(buffer : FixedArray[Byte], length : Int32) -> Int32 {
  let count = shared_stdin_read(buffer, length, interruption_requested)
  if count == -2 {
    file_read(0, buffer, length)
  } else {
    count
  }
}

///|
pub extern "js" fn interruption_start() -> Unit =
  #| () => {}

///|
pub extern "js" fn interruption_stop() -> Unit =
  #| () => {}

///|
/// The installed launcher owns SIGINT and sets this shared flag while the
/// synchronous evaluator runs in its owned worker thread.
extern "js" fn raw_interruption_requested() -> Bool =
  #| () => !!globalThis.__morphirInterrupt && Atomics.load(globalThis.__morphirInterrupt, 0) !== 0
