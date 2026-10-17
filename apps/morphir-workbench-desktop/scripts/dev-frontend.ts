import { execFileSync, spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const script = (name: string) => fileURLToPath(new URL(`../../morphir-workbench/scripts/${name}.ts`, import.meta.url));
execFileSync(process.execPath, [script('build')], { stdio: 'inherit' });
const server = spawn(process.execPath, [script('serve')], { stdio: 'inherit' });
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => server.kill(signal));
server.on('exit', code => process.exit(code ?? 1));
