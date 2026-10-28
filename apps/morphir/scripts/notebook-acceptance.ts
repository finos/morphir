import assert from 'node:assert/strict';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import Ajv from 'ajv-draft-04';

type Run = (args: string[], expected?: number) => {stdout: string; stderr: string};
type JupyterNotebook = {
  metadata: {morphir?: {profile?: string}};
  cells: Array<{
    cell_type: string;
    metadata: {language?: string};
    outputs?: Array<{output_type: string; data?: Record<string, unknown>}>;
  }>;
};
const schemaPath = fileURLToPath(new URL('../../../tests/notebooks/nbformat.v4.5.schema.json', import.meta.url));
const validator = new Ajv({allErrors: true, strict: false}).compile<JupyterNotebook>(JSON.parse(readFileSync(schemaPath, 'utf8')));

export function validateJupyterNotebook(value: unknown): asserts value is JupyterNotebook {
  assert.ok(validator(value), JSON.stringify(validator.errors));
}

function document(run: Run, args: string[], expected = 0) {
  const output = run(args, expected);
  const value = JSON.parse(output.stdout);
  assert.equal(value.profile, 'morphir/command-result');
  assert.equal(value.contractVersion, '0.1.0');
  assert.equal(value.exitCode, expected);
  assert.equal(value.state, expected === 0 ? 'succeeded' : 'failed');
  assert.ok(Array.isArray(value.diagnostics));
  if (expected === 0) assert.ok(value.result);
  else {assert.ok(value.error.code); assert.equal(Object.hasOwn(value, 'result'), false)}
  return {value, ...output};
}

export function exerciseNotebooks(run: Run, root: string, target: string) {
  const directory = join(root, 'notebooks');
  mkdirSync(directory, {recursive: true});
  const put = (name: string, text: string) => writeFileSync(join(directory, name), text);
  const path = (name: string) => 'notebooks/' + name;
  const disk = (name: string) => join(directory, name);
  let validated = 0;
  function validate(name: string) {
    const value = JSON.parse(readFileSync(disk(name), 'utf8'));
    validateJupyterNotebook(value);
    validated++;
    return value;
  }
  assert.equal(validator({nbformat: 4, nbformat_minor: 5, metadata: {}, cells: [{cell_type: 'code'}]}), false,
    'Independent nbformat validator must reject malformed cells');
  put('worksheet.scm', ";; # Totals\n(define prices '(3 4 5))\n(apply + prices)\n");
  const source = path('worksheet.scm');
  for (const args of [
    ['notebook', 'export', source, '-o', path('forms.ipynb'), '--json'],
    ['--json', 'notebook', 'export', source, '--format', 'ipynb', '--output', path('explicit.ipynb')],
    ['notebook', 'export', source, '--json'],
  ]) {
    const result = document(run, args).value;
    assert.equal(result.command, 'notebook.export');
    assert.equal(result.result.cellCount, 3);
    assert.equal(result.result.format, 'ipynb');
    assert.deepEqual(result.result.skippedCells, []);
    assert.equal(result.result.evaluated, false);
    const name = result.result.outputPath.split(/[\\/]/).pop()!;
    const notebook = validate(name);
    assert.equal(notebook.cells[0]?.cell_type, 'markdown');
    assert.equal(notebook.cells[1]?.metadata.language, 'scheme');
    assert.equal(notebook.metadata.morphir?.profile, 'morphir/worksheet-notebook');
  }
  const dib = document(run, ['notebook', 'export', source, '-o', path('forms.dib'), '--json']).value;
  assert.equal(dib.result.format, 'dib');
  assert.match(readFileSync(disk('forms.dib'), 'utf8'), /#!scheme/);
  for (const format of ['ipynb', 'dib']) {
    const result = document(run, ['notebook', 'import', path('forms.' + format), '-o', path('roundtrip-' + format + '.scm'), '--json']).value;
    assert.equal(result.command, 'notebook.import');
    assert.equal(result.result.cellCount, 3);
    const restored = readFileSync(disk('roundtrip-' + format + '.scm'), 'utf8');
    assert.match(restored, /;; # Totals/);
    assert.match(restored, /\(define prices '\(3 4 5\)\)/);
    assert.match(restored, /\(apply \+ prices\)/);
  }
  put('failed.scm', '(+ 1 2)\n(unknown-function)');
  if (target === 'wasm') {
    const failure = document(run, ['notebook', 'export', path('failed.scm'), '--evaluate', '-o', path('evaluated.ipynb'), '--json'], 2);
    assert.match(failure.stderr, /interruptible host/);
    assert.equal(existsSync(disk('evaluated.ipynb')), false);
  } else {
    const result = document(run, ['notebook', 'export', path('failed.scm'), '--evaluate', '-o', path('evaluated.ipynb'), '--json']).value;
    assert.equal(result.result.evaluated, true);
    const notebook = validate('evaluated.ipynb');
    assert.equal(notebook.cells[0]?.outputs?.[0]?.output_type, 'execute_result');
    assert.ok(notebook.cells[0]?.outputs?.[0]?.data?.['application/vnd.morphir.observation+json']);
    assert.equal(notebook.cells[1]?.outputs?.[0]?.output_type, 'error');
  }
  // A failed read proves the DIB/evaluate refusal precedes input capture and evaluation.
  const refusal = document(run, ['notebook', 'export', path('missing.scm'), '--evaluate', '-o', path('refused.dib'), '--json'], 2);
  assert.equal(refusal.value.error.code, 'notebook.outputs_require_jupyter');
  assert.match(refusal.stderr, /Saved outputs require Jupyter/);
  assert.equal(existsSync(disk('refused.dib')), false);
  document(run, ['notebook', 'export', source, '--format', 'ipynb', '-o', path('explicit.notebook'), '--json']);
  validate('explicit.notebook');
  const defaultImport = document(run, ['notebook', 'import', path('forms.dib'), '--json']).value;
  assert.equal(defaultImport.result.outputPath, path('forms.scm'));
  assert.match(readFileSync(disk('forms.scm'), 'utf8'), /\(apply \+ prices\)/);
  document(run, ['notebook', 'export', source, '-o', path('absent/output.ipynb'), '--json'], 1);
  put('malformed.scm', '42\n(');
  document(run, ['notebook', 'export', path('malformed.scm'), '-o', path('malformed.ipynb'), '--json'], 2);
  assert.equal(existsSync(disk('malformed.ipynb')), false);
  put('mixed.ipynb', JSON.stringify({nbformat: 4, nbformat_minor: 4, metadata: {language_info: {name: 'scheme'}}, cells: [
    {cell_type: 'code', metadata: {}, source: '42', outputs: [], execution_count: null},
    {cell_type: 'code', metadata: {language: 'python'}, source: 'print(1)', outputs: [], execution_count: null},
    {cell_type: 'raw', metadata: {}, source: 'raw'},
    {cell_type: 'markdown', metadata: {}, source: '# End'},
  ]}));
  const mixed = document(run, ['notebook', 'import', path('mixed.ipynb'), '-o', path('mixed.scm'), '--json']);
  assert.equal(mixed.value.result.skippedCells.length, 2);
  assert.equal(mixed.value.diagnostics.length, 2);
  assert.match(mixed.stderr, /cell-1/);
  assert.match(mixed.stderr, /cell-2/);
  assert.equal(readFileSync(disk('mixed.scm'), 'utf8'), '42\n\n;; # End\n');
  for (const [name, content] of [['broken.ipynb', '{'], ['broken.dib', '#!meta\n{bad}']]) {
    put(name!, content!);
    put('preserved.scm', 'keep existing output');
    const broken = document(run, ['notebook', 'import', path(name!), '-o', path('preserved.scm'), '--json'], 2);
    assert.match(broken.stderr, new RegExp(name!.replace('.', '\\.')));
    assert.equal(readFileSync(disk('preserved.scm'), 'utf8'), 'keep existing output');
  }
  for (const args of [
    ['notebook', 'export', '--unknown', '--json'],
    ['--json', 'notebook', 'export', source, '--format', 'unknown'],
    ['notebook', 'export', source, '-o', '', '--json'],
    ['notebook', 'import', '--json'],
    ['notebook', 'export', source, '-o', source, '--json'],
  ]) document(run, args, 2);
  put('loop.scm', '(let loop () (loop))');
  document(run, ['notebook', 'export', path('loop.scm'), '--evaluate', '-o', path('./loop.scm'), '--json'], 2);
  assert.equal(readFileSync(disk('loop.scm'), 'utf8'), '(let loop () (loop))');
  assert.equal(readFileSync(disk('worksheet.scm'), 'utf8'), ";; # Totals\n(define prices '(3 4 5))\n(apply + prices)\n");
  for (const operation of ['export', 'import']) {
    const before = readdirSync(directory).sort();
    const help = document(run, ['notebook', operation, '--help', '--json']);
    assert.match(help.value.result.help, /morphir\/command-result/);
    assert.deepEqual(readdirSync(directory).sort(), before);
  }
  console.log(`Notebook ${target}: shared cells, evaluated Jupyter, source-only DIB, round trips, ${validated} independent nbformat validations, skipped cells, invalid-input preservation, argv/JSON/help passed.`);
}
