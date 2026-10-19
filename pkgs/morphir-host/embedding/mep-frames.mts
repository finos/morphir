import {mepLimits} from './mep-adapter.mjs';

/** Byte framing only. The guest remains the JSON-RPC authority. Incremental
 * bounded buffers avoid repeated concatenation on fragmented large requests.
 */
export class MepFrames {
  private header:number[]=[];
  private body:Uint8Array<ArrayBuffer>|undefined;
  private at=0;
  private closed=false;
  async push(chunk:Uint8Array,accept:(body:Uint8Array<ArrayBuffer>)=>Promise<boolean>):Promise<boolean> {
    if(this.closed)throw new Error('MEP frames closed');
    let offset=0;
    while(offset<chunk.length) {
      if(!this.body) {
        this.header.push(chunk[offset++]!);
        if(this.header.length>mepLimits.header)throw new Error('MEP header exceeds 8 KiB');
        const n=this.header.length;
        if(n<4||this.header[n-4]!==13||this.header[n-3]!==10||this.header[n-2]!==13||this.header[n-1]!==10)continue;
        const header=new TextDecoder('utf-8',{fatal:true}).decode(new Uint8Array(this.header));
        let length:number|undefined;
        for(const line of header.split('\r\n').filter(Boolean)) {
          const colon=line.indexOf(':');if(colon<0)throw new Error('Invalid MEP header');
          if(line.slice(0,colon).toLowerCase()!=='content-length')continue;
          const text=line.slice(colon+1).trim();
          if(length!==undefined||!/^\d+$/.test(text))throw new Error('Invalid or repeated Content-Length');
          length=Number(text);if(!Number.isSafeInteger(length)||length>mepLimits.request)throw new Error('MEP payload exceeds 16 MiB');
        }
        if(length===undefined)throw new Error('Missing Content-Length');
        this.header=[];this.body=new Uint8Array(length);this.at=0;
      }
      const size=Math.min(chunk.length-offset,this.body.length-this.at);
      this.body.set(chunk.subarray(offset,offset+size),this.at);offset+=size;this.at+=size;
      if(this.at===this.body.length) {
        const body=this.body;this.body=undefined;this.at=0;
        if(!await accept(body)){this.clear();return false;}
      }
    }
    return true;
  }
  finish():void {if(this.header.length||this.body)throw new Error('Truncated MEP frame');}
  clear():void {this.header=[];this.body=undefined;this.at=0;this.closed=true;}
}
