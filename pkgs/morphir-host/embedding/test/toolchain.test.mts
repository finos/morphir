import type { CompileRequest, Compiler, CompilerFactory, Toolchain } from '../api.mjs';
import { malformed, deferred } from '../../../../tests/helpers.ts';
import assert from "node:assert/strict";
import {test} from "node:test";
import {createInProcessToolchain, createNodeToolchain} from "../node.mts";
import {createEmbeddedToolchain} from "../index.mts";

const source = (value: number): CompileRequest => ({operation: "compile", files: [["main.mbt", `pub fn answer() -> Int32 { ${value} }`]], exports: ["answer"]});

test("capability inspection cannot change embedded target validation", async () => {
  let called=false;
  const tools=createEmbeddedToolchain(()=>malformed<Compiler>({buildPackage(){called=true;}}));
  try {
    const info=await tools.request({operation:"info"});
    for (const descriptor of [tools.capabilities,info]) {
      assert.throws(()=>Reflect.apply(Array.prototype.push,descriptor.targets,["native"]),TypeError);
      assert.throws(()=>Reflect.apply(Array.prototype.push,descriptor.operations,["setup"]),TypeError);
    }
    await assert.rejects(tools.request(malformed<CompileRequest>({...source(42),target:"native"})),/Unsupported embedded target/);
    assert.equal(called,false);
  } finally {tools.dispose();}
});

test("disposal stops compilation while host compiler assets are loading", async () => {
  const loading=deferred<Compiler>();let called=false;
  const tools=createEmbeddedToolchain(()=>loading.promise);
  const pending=tools.request(source(42));
  await new Promise(resolve=>setImmediate(resolve));
  tools.dispose();
  loading.resolve(malformed<Compiler>({buildPackage(){called=true;}}));
  await assert.rejects(pending,/disposed/);
  assert.equal(called,false);
});

for (const [name, create] of [["in-process", createInProcessToolchain], ["Node worker", createNodeToolchain]] as [string, () => Toolchain][]) {
  test(`${name}: compile and execute without installed CLI`, async () => {
    const tools = create!();
    try {
      const info = await tools.request({operation: "info"});
      assert.equal(info.mode, "embedded");
      assert.equal(info.compilerVersion, "0.10.16+b1a0e846e");
      for (const target of ["wasm", "wasm-gc"] as const) {
        const result = await tools.request({...source(42), target});
        assert.equal(result.successful, true);
        assert.equal((await tools.request({operation: "run", artifact: result.artifact!, export: "answer"})).value, 42);
      }
      // Mutable compiler state must not leak between queued package builds.
      const results = await Promise.all([11, 22, 33].map(n => tools.request(source(n))));
      const evaluated = await Promise.all(results.map(r => tools.request({operation: "run", artifact:r.artifact!, export:"answer"})));
      assert.deepEqual(evaluated.map(r => r.value), [11,22,33]);
      const invalid = await tools.request({operation:"compile",files:[["bad.mbt",'pub fn answer() -> Int { "wrong" }']],exports:["answer"]});
      assert.equal(invalid.successful, false);
      assert.ok(invalid.diagnostics.length);
      assert.equal(invalid.artifact, null);
      await assert.rejects(tools.request(malformed<CompileRequest>({operation:"compile",files:source(1).files,target:"native"})), /Unsupported embedded target/);
      const good = await tools.request(source(7));
      await assert.rejects(tools.request({operation:"run",artifact:good.artifact!,export:"missing"}), /Missing runtime export/);
      assert.equal((await tools.request({operation:"run",artifact:good.artifact!,export:"answer"})).value,7);
    } finally { tools.dispose(); }
    await assert.rejects(tools.request({operation:"info"}), /disposed/);
  });
}

test("host runtime imports are injected for in-process embedding", async () => {
  const tools = createInProcessToolchain({imports: {host:{double:(n: number)=>n*2}}});
  try {
    const result = await tools.request({operation:"compile",files:[["main.mbt", 'fn double(n : Int) -> Int = "host" "double"\npub fn answer() -> Int { double(21) }']],exports:["answer"]});
    assert.equal(result.successful,true);
    assert.equal((await tools.request({operation:"run",artifact:result.artifact!,export:"answer"})).value,42);
  } finally { tools.dispose(); }
});

test("hosts can supply compiled interfaces and linked core dependencies", async () => {
  const tools=createInProcessToolchain();
  try {
    const dependency=await tools.request({operation:"compile",package:"morphir/dependency",files:[["dep.mbt","pub fn double(x : Int) -> Int { x * 2 }"]],exports:["double"]});
    const main=await tools.request({operation:"compile",package:"morphir/main",files:[["main.mbt","pub fn answer() -> Int { @dependency.double(21) }"]],
      interfaces:[["dependency",dependency.interface!]],cores:[dependency.core!],exports:["answer"]});
    assert.equal(main.successful,true);
    assert.equal((await tools.request({operation:"run",artifact:main.artifact!,export:"answer"})).value,42);
  } finally {tools.dispose();}
});

test("fresh compiler instances preserve host process exception handlers", async () => {
  const before=process.listeners('uncaughtException');
  const tools=createInProcessToolchain();
  try {
    for(let i=0;i<12;i++) assert.equal((await tools.request(source(i))).successful,true);
    assert.deepEqual(process.listeners('uncaughtException'),before);
  } finally {tools.dispose();}
});

test("worker cancellation terminates running evaluation and rejects queued requests", async () => {
  const tools = createNodeToolchain();
  const result = await tools.request({operation:"compile",files:[["main.mbt", 'pub fn spin() -> Int { while true {}\n0 }']],exports:["spin"]});
  assert.equal(result.successful,true);
  const controller = new AbortController();
  const running = tools.request({operation:"run",artifact:result.artifact!,export:"spin"},{signal:controller.signal});
  const queued = tools.request({operation:"info"});
  const checks = Promise.all([assert.rejects(running,{name:"AbortError"}),assert.rejects(queued,{name:"AbortError"})]);
  setTimeout(()=>controller.abort(),50);
  await checks;
  await assert.rejects(tools.request({operation:"info"}),/disposed/);
});
