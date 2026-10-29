///|
/// Keep the caller's cooperative probe live while Node owns the asynchronous
/// child. Only this private bridge crosses the worker boundary; child argv and
/// the existing process result object retain their shapes.
#cfg(target="js")
extern "js" fn execute_js(
  spawn : (String, FixedArray[String], Process) -> Process,
  program : String,
  args : FixedArray[String],
  cwd : String,
  home : String,
  timeout : Int32,
  interrupted : () -> Bool,
  started : (String) -> Unit,
) -> String =
  #| (spawn,program,args,cwd,home,timeout,interrupted,started) => {
  #|   const failed=message=>JSON.stringify({exitCode:-1,stdout:'',stderr:message});
  #|   if(!Number.isInteger(timeout)||timeout<1||timeout>600000)return failed('Invalid process timeout');
  #|   const capacity=16777216,state=new Int32Array(new SharedArrayBuffer(24)),bytes=new Uint8Array(new SharedArrayBuffer(capacity*2));
  #|   const env={...process.env};if(home){env.MOON_HOME=home;env.PATH=home+'/bin'+(process.platform==='win32'?';':':')+(env.PATH||'');}
  #|   const script=String.raw`
  #|     const {workerData}=require('node:worker_threads'),{spawn,spawnSync}=require('node:child_process');
  #|     const state=new Int32Array(workerData.state),bytes=new Uint8Array(workerData.bytes),capacity=16777216;
  #|     let child,done=false,reason='',output=0,diagnostics=0,error='',poll,timer,grace,kill;
  #|     function append(data,isError){const offset=isError?capacity+diagnostics:output;const used=isError?diagnostics:output;if(data.length>capacity-used){error='Process output exceeds 16 MiB';stop('limit');return;}bytes.set(data,offset);if(isError)diagnostics+=data.length;else output+=data.length;}
  #|     function signal(value,group){if(!child?.pid)return;try{if(process.platform==='win32'){spawnSync((process.env.SystemRoot||'C:\\Windows')+'\\System32\\taskkill.exe',['/PID',String(child.pid),'/T','/F'],{timeout:5000,windowsHide:true,stdio:'ignore'});}else if(group){try{process.kill(-child.pid,value);}catch{}child.kill(value);}else child.kill(value);}catch{}}
  #|     function finish(code){if(done)return;done=true;clearInterval(poll);clearTimeout(timer);clearTimeout(grace);clearTimeout(kill);if(error)append(Buffer.from(error),true);Atomics.store(state,1,code);Atomics.store(state,2,output);Atomics.store(state,3,diagnostics);Atomics.store(state,0,1);Atomics.notify(state,0);}
  #|     function stop(value){if(reason||done)return;reason=value;if(value==='cancel'&&process.platform!=='win32'){signal('SIGINT',false);grace=setTimeout(()=>{signal('SIGTERM',true);kill=setTimeout(()=>signal('SIGKILL',true),500);},5000);}else{signal('SIGTERM',true);kill=setTimeout(()=>signal('SIGKILL',true),500);}}
  #|     try{
  #|       if(Atomics.load(state,5)){finish(-1);}else{
  #|         child=spawn(workerData.program,workerData.args,{cwd:workerData.cwd,env:workerData.env,detached:process.platform!=='win32',encoding:'buffer',stdio:['ignore','pipe','pipe'],windowsHide:true});
  #|         child.once('spawn',()=>{Atomics.store(state,4,child.pid);Atomics.notify(state,0);});
  #|         child.stdout.on('data',data=>append(data,false));child.stderr.on('data',data=>append(data,true));
  #|         child.once('error',cause=>{error=cause.message;});
  #|         child.once('close',code=>finish(reason==='timeout'?124:error?-1:code??-1));
  #|         timer=setTimeout(()=>stop('timeout'),workerData.timeout);
  #|         poll=setInterval(()=>{if(Atomics.load(state,5))stop('cancel');},10);
  #|       }
  #|     }catch(cause){error=String(cause.message||cause);finish(-1);}
  #|   `;
  #|   let worker,announced=false,stoppedAt=0;const start=performance.now();
  #|   try{
  #|     const {Worker}=process.getBuiltinModule('node:worker_threads');
  #|     worker=new Worker(script,{eval:true,workerData:{program,args,cwd,env,timeout,state:state.buffer,bytes:bytes.buffer}});worker.unref();worker.on('error',()=>{});
  #|     while(true){
  #|       if(!announced&&Atomics.load(state,4)>0){announced=true;started(program);}
  #|       if(Atomics.load(state,0)===1)break;
  #|       if(interrupted()){Atomics.store(state,5,1);stoppedAt ||= performance.now();}
  #|       if(performance.now()-start>timeout+12000||(stoppedAt&&performance.now()-stoppedAt>12000)){
  #|         const pid=Atomics.load(state,4);if(pid>0){try{if(process.platform==='win32')spawn((process.env.SystemRoot||'C:\\Windows')+'\\System32\\taskkill.exe',['/PID',String(pid),'/T','/F'],{timeout:5000,windowsHide:true,stdio:'ignore'});else{try{process.kill(-pid,'SIGKILL');}catch{}process.kill(pid,'SIGKILL');}}catch{}}
  #|         return failed('Process bridge did not confirm child cleanup');
  #|       }
  #|       Atomics.wait(state,0,0,10);
  #|     }
  #|     return JSON.stringify({exitCode:Atomics.load(state,1),stdout:Buffer.from(bytes.buffer,0,Atomics.load(state,2)).toString('utf8'),stderr:Buffer.from(bytes.buffer,capacity,Atomics.load(state,3)).toString('utf8')});
  #|   }catch(cause){return failed(String(cause.message||cause));}finally{if(worker)Promise.resolve(worker.terminate()).catch(()=>{});}
  #| }
