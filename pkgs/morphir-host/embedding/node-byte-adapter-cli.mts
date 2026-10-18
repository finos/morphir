import {runByteAdapter} from './node-byte-adapter.mjs';
try {
  const [directory,profile,logPath,...extra]=process.argv.slice(2);
  if(!directory || (profile !== 'bytes-v1' && profile !== 'bytes-diagnostics-v1') || extra.length || (logPath!==undefined && profile!=='bytes-diagnostics-v1'))
    throw new Error('Usage: node node-byte-adapter-cli.mjs ARTIFACT_DIRECTORY bytes-v1|bytes-diagnostics-v1 [DIAGNOSTICS_PATH]');
  await runByteAdapter(directory,profile,logPath);
} catch(error){process.stderr.write(`Byte adapter failed: ${error instanceof Error ? error.message : String(error)}\n`);process.exitCode=1;}
