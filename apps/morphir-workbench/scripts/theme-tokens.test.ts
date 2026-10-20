import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

// Every Workbench color is an appearance token. Only the light :root block and the two dark blocks hold color values.
const read = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');
const stylesheets = { 'workbench.css': read('../workbench.css'), 'model-explorer.css': read('../browser/model-explorer/explorer.css') };
const editor = read('../browser/editor/code-editor.ts');
const LIGHT = ':root', SYSTEM_DARK = ':root:not([data-theme="light"])', DARK = ':root[data-theme="dark"]';
const SYSTEM_DARK_MEDIA = '@media (prefers-color-scheme: dark)';

// The foreground and background token pairs the Workbench draws together, with the WCAG 2.2 AA minimum for each:
// 4.5 for text, 3 for the focus indicator, icons and button boundaries. Disabled controls have no minimum, and the
// brand blue and orange bars mark a state together with the text color and weight, so they have none either.
type Pair = [foreground: string, background: string, minimum: number];
const all = (foregrounds: string[], backgrounds: string[], minimum: number): Pair[] =>
  foregrounds.flatMap(foreground => backgrounds.map(background => [foreground, background, minimum] as Pair));
const pairs: Pair[] = [
  ...all(['ink', 'muted', 'link', 'link-strong', 'warn-ink', 'danger-ink'], ['paper', 'surface', 'surface-alt', 'selection'], 4.5),
  ...all(['subtle'], ['paper', 'surface', 'surface-alt'], 4.5),
  ...all(['ink', 'muted'], ['section-header', 'track', 'raised', 'chip', 'hover', 'hover-soft', 'hover-row'], 4.5),
  ...all(['ink'], ['hover-strong'], 4.5),
  ...all(['ink', 'muted', 'warn-ink'], ['warn-bg'], 4.5),
  ...all(['ink', 'muted', 'danger-ink'], ['danger-bg'], 4.5),
  ...all(['on-primary'], ['brand-orange', 'primary-hover'], 4.5),
  ...all(['on-danger'], ['danger-solid', 'danger-hover'], 4.5),
  // Editor text on the editor, its active line and its gutter.
  ...all(['ink', 'code-keyword', 'code-function', 'code-string', 'code-number', 'code-comment', 'code-punctuation', 'code-property'], ['surface', 'selection'], 4.5),
  ...all(['muted'], ['surface-alt'], 4.5),
  ...all(['focus-ring'], ['paper', 'surface', 'surface-alt', 'selection', 'section-header', 'hover-row'], 3),
  ...all(['subtle', 'lang-elm', 'lang-moonbit'], ['paper', 'surface', 'selection', 'hover-row'], 3),
  ...all(['danger-solid'], ['surface'], 3),
];

interface Rule { selector: string; at: string; body: string }

/** The style rules of a stylesheet, with the at-rule around each one; comments and strings never end a rule. */
function rules(css: string): Rule[] {
  const source = css.replace(/\/\*[\s\S]*?\*\//g, '');
  const found: Rule[] = [];
  const walk = (from: number, at: string): number => {
    let start = from, i = from;
    while (i < source.length) {
      const char = source[i];
      if (char === '"' || char === "'") { i = source.indexOf(char, i + 1) + 1; continue; }
      if (char === '}') return i + 1;
      if (char === ';' && source.slice(start, i).trim().startsWith('@')) { start = ++i; continue; }
      if (char === '{') {
        const prelude = source.slice(start, i).trim();
        if (prelude.startsWith('@')) { i = walk(i + 1, prelude); start = i; continue; }
        const end = source.indexOf('}', i);
        found.push({ selector: prelude, at, body: source.slice(i + 1, end) });
        start = i = end + 1;
        continue;
      }
      i++;
    }
    return i;
  };
  walk(0, '');
  return found;
}

function declarations(body: string): [string, string][] {
  return body.split(';').map(part => part.trim()).filter(Boolean).map(part => {
    const colon = part.indexOf(':');
    return [part.slice(0, colon).trim(), part.slice(colon + 1).trim()];
  });
}

const namedColors = new Set(('aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood ' +
  'cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey ' +
  'darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey ' +
  'darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite ' +
  'gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon ' +
  'lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue ' +
  'lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid ' +
  'mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin ' +
  'navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip ' +
  'peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna ' +
  'silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke ' +
  'yellow yellowgreen').split(' '));

/** The color literals in a CSS value; url() targets and quoted text are not colors. */
function colorLiterals(value: string): string[] {
  const plain = value.replace(/url\([^)]*\)/g, '').replace(/"[^"]*"|'[^']*'/g, '');
  return [
    ...plain.match(/#[0-9a-f]{3,8}\b/gi) ?? [],
    ...plain.match(/\b(?:rgba?|hsla?|hwb|lab|lch|oklab|oklch|color)\(/gi) ?? [],
    ...(plain.match(/[a-z]+(?:-[a-z]+)*/gi) ?? []).filter(word => namedColors.has(word.toLowerCase())),
  ];
}

const tokenBlock = (rule: Rule) => (rule.selector === LIGHT && rule.at === '') || rule.selector === DARK
  || (rule.selector === SYSTEM_DARK && rule.at === SYSTEM_DARK_MEDIA);

function tokens(selector: string, at: string): Map<string, string> {
  const [block, ...others] = rules(stylesheets['workbench.css']).filter(rule => rule.selector === selector && rule.at === at);
  assert.ok(block && others.length === 0, `one ${at} ${selector} block`);
  return new Map(declarations(block.body).filter(([name]) => name.startsWith('--')));
}
const isColor = (value: string) => colorLiterals(value).length > 0;
const colorTokens = (map: Map<string, string>) => new Map([...map].filter(([, value]) => isColor(value)));

function rgb(value: string): [number, number, number] {
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.exec(value)?.[1];
  assert.ok(hex, `${value} is an opaque hex color`);
  const full = hex.length === 3 ? [...hex].map(digit => digit + digit).join('') : hex;
  return [0, 2, 4].map(index => parseInt(full.slice(index, index + 2), 16)) as [number, number, number];
}
function luminance(value: string): number {
  const linear = (channel: number) => (c => c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)(channel / 255);
  const [r, g, b] = rgb(value);
  return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}
function contrast(foreground: string, background: string): number {
  const [first, second] = [luminance(foreground), luminance(background)];
  return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05);
}

test('Workbench stylesheets use tokens for every color outside the token blocks', () => {
  const found: string[] = [];
  for (const [name, css] of Object.entries(stylesheets)) {
    for (const rule of rules(css)) {
      for (const [property, value] of declarations(rule.body)) {
        if (tokenBlock(rule) && property.startsWith('--')) continue;
        for (const literal of colorLiterals(value)) found.push(`${name}: ${rule.selector} { ${property}: ${value} } has ${literal}`);
      }
    }
  }
  assert.deepEqual(found, []);
});

test('the editor theme and highlight style use tokens for every color', () => {
  const strings = editor.match(/'(?:[^'\\\n]|\\.)*'/g) ?? [];
  const styleStart = editor.indexOf('HighlightStyle.define(');
  const themeEnd = editor.indexOf('});', editor.indexOf('EditorView.theme('));
  assert.ok(styleStart > 0 && themeEnd > styleStart, 'the highlight style and theme are found');
  const styles = editor.slice(styleStart, themeEnd).match(/'(?:[^'\\\n]|\\.)*'/g) ?? [];
  const found = [
    ...strings.flatMap(text => [...text.match(/#[0-9a-f]{3,8}\b/gi) ?? [], ...text.match(/\b(?:rgba?|hsla?)\(/gi) ?? []]),
    ...styles.flatMap(text => colorLiterals(text.slice(1, -1))),
  ];
  assert.deepEqual(found, []);
  assert.ok(styles.some(text => text.includes('var(--code-keyword)')), 'the highlight style reads code tokens');
});

test('the dark blocks match and define every light color token', () => {
  const light = colorTokens(tokens(LIGHT, '')), system = tokens(SYSTEM_DARK, SYSTEM_DARK_MEDIA), dark = tokens(DARK, '');
  assert.deepEqual(Object.fromEntries(system), Object.fromEntries(dark));
  assert.deepEqual([...light.keys()].sort(), [...colorTokens(dark).keys()].sort());
  const scheme = (selector: string, at: string) => declarations(rules(stylesheets['workbench.css'])
    .find(rule => rule.selector === selector && rule.at === at)!.body).find(([name]) => name === 'color-scheme')?.[1];
  assert.equal(scheme(LIGHT, ''), 'light');
  assert.equal(scheme(SYSTEM_DARK, SYSTEM_DARK_MEDIA), 'dark');
  assert.equal(scheme(DARK, ''), 'dark');
});

for (const [theme, selector] of [['light', LIGHT], ['dark', DARK]] as const) {
  test(`${theme} token pairs meet WCAG 2.2 AA contrast`, () => {
    const values = tokens(selector, '');
    const failures = pairs.flatMap(([fg, bg, minimum]) => {
      const [foreground, background] = [values.get('--' + fg), values.get('--' + bg)];
      assert.ok(foreground && background, `--${fg} and --${bg} are defined`);
      const ratio = contrast(foreground, background);
      return ratio < minimum ? [`--${fg} on --${bg}: ${ratio.toFixed(2)} < ${minimum}`] : [];
    });
    assert.deepEqual(failures, []);
  });
}

test('contrast follows the WCAG definition', () => {
  assert.equal(contrast('#000', '#fff'), 21);
  assert.equal(contrast('#777', '#777'), 1);
  assert.equal(contrast('#767676', '#fff').toFixed(2), '4.54');
});
