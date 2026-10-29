// Run the exported loader against real ReadableStreams interrupted midway.
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const file=process.argv[2]||'dist/纸间网页版-20261025-flow/site/index.js';
const text=await readFile(file,'utf8');
const source=text.slice(text.indexOf('const Preloader ='),text.indexOf('const EngineConfig ='))+'\nglobalThis.Loader=Preloader;';
let unhandled=0;process.on('unhandledRejection',()=>unhandled++);
async function scenario(permanent){
 let calls=0;
 const context=vm.createContext({Response,ReadableStream,ArrayBuffer,Uint8Array,setTimeout:(f)=>setTimeout(f,1),fetch:async()=>{
  calls++;
  if(!permanent&&calls>1)return new Response(new Uint8Array([1,2,3]));
  return new Response(new ReadableStream({start(controller){controller.enqueue(new Uint8Array([1]));queueMicrotask(()=>controller.error(new Error('fixture stream interrupted')));}}));
 }});
 vm.runInContext(source,context);
 let timer;
 const result=await Promise.race([new context.Loader().loadPromise('fixture.pck',3).then(b=>({bytes:[...new Uint8Array(b)]}),error=>({error:String(error)})),new Promise(resolve=>timer=setTimeout(()=>resolve({timeout:true}),250))]);
 clearTimeout(timer);
 assert(!result.timeout,`${permanent?'persistent':'transient'} interrupted stream must settle, not hang`);
 if(permanent){assert.equal(calls,4);assert.match(result.error,/fixture stream interrupted/);}
 else{assert.equal(calls,2);assert.deepEqual(result.bytes,[1,2,3]);}
}
let failed=0;
for(const permanent of [false,true]){try{await scenario(permanent);console.log('PASS',permanent?'persistent failure rejects after 4 attempts':'interrupted download retries successfully');}catch(error){failed++;console.error('FAIL',error.message);}}
if(unhandled){failed++;console.error('FAIL unhandled stream rejections:',unhandled);}
process.exitCode=failed?1:0;
