import {terminalWorker} from '../../../../../pkgs/morphir-host/runners/terminal-worker.mts';
if (!terminalWorker(new URL(import.meta.url), process.argv.slice(2))) {
  const host=globalThis as typeof globalThis & {__morphirStdinRead:(bytes:Uint8Array,length:number)=>number;__morphirInterrupt:Int32Array};
  const read=host.__morphirStdinRead(new Uint8Array(16),16);
  const kind=Atomics.load(host.__morphirInterrupt,0);
  process.stdout.write(JSON.stringify({read,kind})+'\n');
  process.exitCode=kind===1?130:kind===2?143:1;
}
