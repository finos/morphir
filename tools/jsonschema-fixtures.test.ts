import { expect, test } from "bun:test";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { runFixtureSuite } from "./jsonschema-fixtures.ts";

test("official schema validation preserves positive and negative fixture assertions", async () => {
 const root = await mkdtemp(path.join(tmpdir(),"morphir-schema-fixture-"));
 try {
  const directory=path.join(root,"fixtures");await mkdir(directory);
  const schema=path.join(root,"schema.json"), fixture=path.join(directory,"fixture.json");
  await writeFile(schema,JSON.stringify({$schema:"https://json-schema.org/draft/2020-12/schema",$id:"https://morphir.test/fixture",type:"string"}));
  await writeFile(fixture,JSON.stringify({target:"https://morphir.test/fixture",tests:[{description:"valid",data:"yes",valid:true},{description:"invalid",data:42,valid:false}]}));
  expect(await runFixtureSuite(directory,["-r",schema])).toBe(2);
  await writeFile(fixture,JSON.stringify({target:"https://morphir.test/fixture",tests:[{description:"incorrect expectation",data:42,valid:true}]}));
  expect(runFixtureSuite(directory,["-r",schema])).rejects.toThrow("incorrect expectation");
 }finally{await rm(root,{recursive:true,force:true});}
});

test("malformed fixture assertions cannot become a passing empty suite",async()=>{
 const root=await mkdtemp(path.join(tmpdir(),"morphir-schema-invalid-"));
 try{await writeFile(path.join(root,"empty.json"),JSON.stringify({target:"missing",tests:[]}));expect(runFixtureSuite(root,[])).rejects.toThrow("nonempty");}
 finally{await rm(root,{recursive:true,force:true});}
});

test("a missing schema is an infrastructure failure, not a negative assertion", async () => {
 const root=await mkdtemp(path.join(tmpdir(),"morphir-schema-missing-"));
 try {
  await writeFile(path.join(root,"missing.json"),JSON.stringify({target:"https://morphir.test/missing",tests:[{description:"missing schema",data:42,valid:false}]}));
  await expect(runFixtureSuite(root,[])).rejects.toThrow("validator failed");
 }finally{await rm(root,{recursive:true,force:true});}
});
