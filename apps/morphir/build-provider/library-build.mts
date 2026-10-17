import { workbenchError } from '../../../types/data.ts';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {buildLibrary} from './project.mjs';
const path=resolve(process.argv[2]!);
try {process.stdout.write(JSON.stringify(await buildLibrary(JSON.parse(readFileSync(path,'utf8')),path)));}
catch(cause) {const error=workbenchError(cause);process.stderr.write(error.message+'\n');process.exitCode=1;}
