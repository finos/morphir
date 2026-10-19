import { execFileSync } from 'node:child_process';
import { cpSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
const desktop = fileURLToPath(new URL('../', import.meta.url));
execFileSync(process.execPath, [fileURLToPath(new URL('./build-icon.ts', import.meta.url)), '--check'], { stdio: 'inherit' });
rmSync(join(desktop, 'frontend/dist'), { recursive: true, force: true });
execFileSync(process.execPath, [fileURLToPath(new URL('../../morphir-workbench/scripts/build.ts', import.meta.url))], { stdio: 'inherit' });
cpSync(join(desktop, '../morphir-workbench/dist'), join(desktop, 'frontend/dist'), { recursive: true });
