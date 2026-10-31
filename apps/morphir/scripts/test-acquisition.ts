import assert from "node:assert/strict";
import {spawnSync} from "node:child_process";
import {mkdtempSync,rmSync,mkdirSync,writeFileSync,readFileSync,statSync,existsSync} from "node:fs";
import {tmpdir} from "node:os";
import {join,delimiter} from "node:path";
import {fileURLToPath} from "node:url";

const directory=mkdtempSync(join(tmpdir(),"morphir-acquisition-"));
const executable=process.argv[2] ?? fileURLToPath(new URL('../../../_build/native/release/build/morphir/morphir/morphir.exe',import.meta.url));
const home=join(directory,'toolchain with spaces');
const env: NodeJS.ProcessEnv={...process.env,MORPHIR_HOME:join(directory,'morphir'),HOME:join(directory,'home')};
delete env.MOON_HOME;
delete env.MORPHIR_MOON_HOME;
env.PATH=(env.PATH||'').split(delimiter).filter(p=>!existsSync(join(p,process.platform==='win32'?'moonc.exe':'moonc'))).join(delimiter);
function run(args: string[],status=0) {
  const result=spawnSync(executable,args,{cwd:directory,env,encoding:'utf8',timeout:900000});
  assert.equal(result.status,status,`${result.stdout}\n${result.stderr}`);
  return result.stdout.trim().split(/\r?\n/).map(line => JSON.parse(line));
}
try {
  const denied=run(['toolchain','setup','--home',home,'--json-lines'],2);
  assert.match(denied[0].data.error,/requires --yes/);
  assert.equal(existsSync(home),false);
  const installed=run(['toolchain','setup','--home',home,'--yes','--timeout','600000','--json-lines']);
  assert.equal(installed[0].type,'toolchain');
  assert.equal(installed[0].data.validated,true);
  assert.equal(installed[0].data.compilerVersion,'0.10.18+6c83a7f62');
  const receipt=join(home,'morphir-toolchain.json');
  const stamp=statSync(receipt).mtimeMs;
  assert.equal(JSON.parse(readFileSync(receipt,'utf8')).archives.length,2);
  assert.equal(existsSync(home+'.lock'),false);
  run(['toolchain','setup','--home',home,'--json']);
  assert.equal(statSync(receipt).mtimeMs,stamp);
  mkdirSync(join(directory,'example'));
  writeFileSync(join(directory,'example/moon.mod'),'name="morphir/acquisition-test"\nversion="0.0.0"\n');
  writeFileSync(join(directory,'example/moon.pkg'),'pkgtype(kind: "executable")\n');
  writeFileSync(join(directory,'example/main.mbt'),'fn main { println(42) }\n');
  const result=run(['toolchain','run','example','--home',home,'--json'])[0];
  assert.equal(result.process.stdout.trim(),'42');
  console.log('Pinned toolchain acquisition, reuse and execution passed');
} finally {rmSync(directory,{recursive:true,force:true});}
