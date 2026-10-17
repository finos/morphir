import { createHighlighter } from 'shiki';
import { readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative } from 'node:path';

const languages = ['moonbit', 'elm', 'scheme', 'json', 'shellscript', 'toml', 'yaml', 'javascript', 'rust'];
const aliases: Record<string, string> = { shell: 'shellscript', sh: 'shellscript', bash: 'shellscript', console: 'shellscript', js: 'javascript', mbt: 'moonbit' };
// Languages that mean "no highlighting": left as plain blocks, without a warning.
const plain = ['text', 'plaintext', 'txt'];
const themes = { light: 'github-light', dark: 'github-dark' };
const block = /<pre><code class="language-([^"]+)">([\s\S]*?)<\/code><\/pre>/g;

let highlighter: Awaited<ReturnType<typeof createHighlighter>> | undefined;
async function shiki() {
  highlighter ??= await createHighlighter({ themes: Object.values(themes), langs: languages });
  return highlighter;
}

function unescape(text: string) {
  return text.replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&amp;', '&');
}

/** Highlight every fenced code block in one HTML string. */
export async function highlightHtml(html: string) {
  const h = await shiki();
  const warnings: string[] = [];
  const out = html.replace(block, (whole: string, lang: string, code: string) => {
    if (plain.includes(lang)) return whole;
    const id = aliases[lang] ?? lang;
    if (!languages.includes(id)) {
      warnings.push(`unknown code language \`${lang}\``);
      return whole;
    }
    return h.codeToHtml(unescape(code), { lang: id, themes, defaultColor: false });
  });
  return { html: out, warnings };
}

function htmlFiles(dir: string, root = dir): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return relative(root, path) === 'try' ? [] : htmlFiles(path, root);
    return name.endsWith('.html') ? [path] : [];
  });
}

/** Highlight all HTML files below `dir`, except `dir/try/`. Returns warnings with file names. */
export async function highlightDir(dir: string) {
  const warnings: string[] = [];
  for (const file of htmlFiles(dir)) {
    const result = await highlightHtml(readFileSync(file, 'utf8'));
    writeFileSync(file, result.html);
    for (const w of result.warnings) warnings.push(`${relative(dir, file)}: ${w}`);
  }
  return warnings;
}
