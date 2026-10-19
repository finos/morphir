import {runMepExtension} from './node-mep-stdio.mjs';

try {
  const [directory,...extra]=process.argv.slice(2);
  if(!directory||extra.length)throw new Error('Usage: node node-mep-cli.mjs ARTIFACT_DIRECTORY');
  await runMepExtension(directory);
}catch(error){process.stderr.write(`morphir-moonbit: ${error instanceof Error?error.message:String(error)}\n`);process.exitCode=1;}
