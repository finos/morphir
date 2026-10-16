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
pub fn rename(a : String, b : String) -> Unit raise {
  check(rename_js(rename_sync, a, b), "rename")
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
extern "js" fn execute_js(
  spawn : (String, FixedArray[String], Process) -> Process,
  program : String,
  args : FixedArray[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> String =
  #| (spawn,program,args,cwd,home,timeout) => { const env={...process.env}; if(home) { env.MOON_HOME=home; env.PATH=home+'/bin'+(process.platform==='win32'?';':':')+(env.PATH||''); } const r=spawn(program,args,{cwd,env,encoding:'utf8',timeout,maxBuffer:16777216,windowsHide:true}); return JSON.stringify({exitCode:r.error ? (r.error.code==='ETIMEDOUT'?124:-1) : (r.status??-1),stdout:r.stdout||'',stderr:(r.stderr||'')+(r.error ? r.error.message : '')}); }

///|
pub fn process(
  program : String,
  args : Array[String],
  cwd : String,
  home : String,
  timeout : Int32,
) -> Json raise {
  @json.parse(
    execute_js(spawn, program, FixedArray::from_array(args), cwd, home, timeout),
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
