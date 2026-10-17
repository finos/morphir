// Explicit local pin creation. This command never downloads or installs tooling.
import {resolve,join} from 'node:path';
import {readFileSync} from 'node:fs';
import {compilerIdentity,run} from './capabilities.mjs';
import {treeIdentity} from './identity.mjs';
const home=resolve(process.argv[2]!), acquisition=JSON.parse(readFileSync(process.argv[3]!,'utf8'));
const compilerVersion=run(join(home,'bin','moonc'),['-v']).split(' ')[0]!.slice(1);
process.stdout.write(JSON.stringify({profile:'morphir-toolchain-pin-v1',compilerVersion,compilerIdentity:compilerIdentity(home),coreIdentity:treeIdentity(join(home,'lib/core'),{core:true}),platform:process.platform,arch:process.arch,targets:['llvm'],acquisition},null,2)+'\n');
