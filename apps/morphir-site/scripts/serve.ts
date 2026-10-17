import { createServer } from 'node:http';
import { createReadStream, existsSync, readFileSync, statSync, watch } from 'node:fs';
import { execFile } from 'node:child_process';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const types: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.json': 'application/json', '.xml': 'application/atom+xml', '.svg': 'image/svg+xml', '.png': 'image/png',
  '.wasm': 'application/wasm',
};

/** The base path from `site/site.json` at the repository root. */
export function siteBase(root: string) {
  return JSON.parse(readFileSync(`${root}site/site.json`, 'utf8')).base_path;
}

/** Serve `dir` below `base`, as GitHub Pages does: `/x/` serves `/x/index.html`. */
export function createSiteServer({ dir, base }: { dir: string; base: string }) {
  return createServer((req, res) => {
    const url = new URL(req.url ?? '/', 'http://localhost');
    if (!url.pathname.startsWith(base)) {
      res.writeHead(302, { location: base }).end();
      return;
    }
    let path = normalize(join(dir, decodeURIComponent(url.pathname.slice(base.length))));
    if (!path.startsWith(normalize(dir))) {
      res.writeHead(403).end();
      return;
    }
    if (existsSync(path) && statSync(path).isDirectory()) path = join(path, 'index.html');
    if (!existsSync(path)) {
      res.writeHead(404, { 'content-type': 'text/plain' }).end('Not found');
      return;
    }
    res.writeHead(200, { 'content-type': types[extname(path)] ?? 'application/octet-stream' });
    createReadStream(path).pipe(res);
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  const dir = `${root}_site`;
  const base = siteBase(root);
  const port = Number(process.env.SITE_PORT ?? 4173);
  createSiteServer({ dir, base }).listen(port, '127.0.0.1', () => {
    console.log(`Morphir site: http://127.0.0.1:${port}${base}`);
  });
  if (process.argv.includes('--watch')) {
    let timer: ReturnType<typeof setTimeout> | undefined;
    const rebuild = () => {
      clearTimeout(timer);
      timer = setTimeout(() => execFile('bun', [fileURLToPath(new URL('./build.ts', import.meta.url))],
        (error, stdout, stderr) => console.log(error ? stderr : 'site: rebuilt')), 300);
    };
    for (const sub of ['docs', 'site']) watch(join(root, sub), { recursive: true }, rebuild);
  }
}
