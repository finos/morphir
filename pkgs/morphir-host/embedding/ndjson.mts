/** Byte-preserving bounded NDJSON framing, shared by process and browser bridges. */
export class NdjsonFrames {
  #chunks:Uint8Array<ArrayBuffer>[]=[];
  #length=0;
  constructor(readonly limit:number) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError('Invalid NDJSON limit');
  }
  async push(chunk:Uint8Array<ArrayBuffer>, receive:(frame:Uint8Array<ArrayBuffer>)=>Promise<boolean>):Promise<boolean> {
    let start=0;
    for (let index=0;index<chunk.length;index++) if(chunk[index] === 10) {
      this.#append(chunk.subarray(start,index));
      const frame=new Uint8Array(this.#length);let offset=0;
      for(const bytes of this.#chunks){frame.set(bytes,offset);offset+=bytes.length;}
      this.clear();
      if (!await receive(frame)) return false;
      start=index+1;
    }
    this.#append(chunk.subarray(start));return true;
  }
  #append(bytes:Uint8Array<ArrayBuffer>) {
    if (this.#length+bytes.length > this.limit) {this.clear();throw new RangeError('NDJSON frame exceeds limit');}
    if(bytes.length){this.#chunks.push(bytes.slice());this.#length+=bytes.length;}
  }
  finish(){if(this.#length){this.clear();throw new Error('Incomplete NDJSON line');}}
  clear(){this.#chunks=[];this.#length=0;}
}
