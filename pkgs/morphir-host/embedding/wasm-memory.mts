/** Narrow core-Wasm memory policy. The MEP profile permits one unshared wasm32
 * defined memory, with a finite maximum. WebAssembly validates all other syntax.
 * Apply the bound before hashing/publication; verify it again before loading.
 */
function integer(bytes:Uint8Array, cursor:{at:number}):number {
  let value=0;
  for(let i=0;i<5;i++) {
    const byte=bytes[cursor.at++];
    if(byte===undefined || (i===4 && byte>15))throw new Error('Invalid Wasm u32');
    value+=(byte&127)*2**(i*7);
    if(!(byte&128))return value;
  }
  throw new Error('Invalid Wasm u32');
}
function encoded(value:number):number[] {
  const bytes:number[]=[];
  do {const byte=value%128;value=Math.floor(value/128);bytes.push(byte+(value?128:0));}while(value);
  return bytes;
}
function memorySection(wasm:Uint8Array):{start:number;end:number;minimum:number;maximum?:number} {
  if(![0,97,115,109,1,0,0,0].every((b,i)=>wasm[i]===b))throw new Error('Expected core Wasm version one');
  const cursor={at:8};let found:ReturnType<typeof memorySection>|undefined;
  while(cursor.at<wasm.length) {
    const start=cursor.at,section=wasm[cursor.at++],size=integer(wasm,cursor),end=cursor.at+size;
    if(end>wasm.length)throw new Error('Truncated Wasm section');
    if(section===5) {
      if(found || integer(wasm,cursor)!==1)throw new Error('MEP requires one defined memory');
      const flags=integer(wasm,cursor);
      if(flags!==0 && flags!==1)throw new Error('MEP requires unshared wasm32 memory');
      const minimum=integer(wasm,cursor),maximum=flags===1?integer(wasm,cursor):undefined;
      if(cursor.at!==end || minimum>65536 || (maximum!==undefined && (maximum<minimum || maximum>65536)))throw new Error('Invalid Wasm memory limits');
      found={start,end,minimum,...maximum===undefined?{}:{maximum}};
    }
    cursor.at=end;
  }
  if(!found)throw new Error('Missing defined MEP memory');
  return found;
}
export function boundWasmMemory(wasm:Uint8Array<ArrayBuffer>, pages:number):Uint8Array<ArrayBuffer> {
  if(!Number.isInteger(pages)||pages<=0||pages>65536)throw new Error('Invalid memory policy');
  const m=memorySection(wasm);
  if(m.minimum>pages)throw new Error('Initial memory exceeds policy');
  const body=[1,1,...encoded(m.minimum),...encoded(Math.min(m.maximum??pages,pages))];
  const section=new Uint8Array([5,...encoded(body.length),...body]);
  const output=new Uint8Array(m.start+section.length+wasm.length-m.end);
  output.set(wasm.subarray(0,m.start));output.set(section,m.start);output.set(wasm.subarray(m.end),m.start+section.length);
  return output;
}
export function verifyWasmMemory(wasm:Uint8Array, pages:number):void {
  const m=memorySection(wasm);
  if(m.maximum===undefined || m.maximum>pages || m.minimum>pages)throw new Error('MEP memory must have a finite maximum within policy');
}
