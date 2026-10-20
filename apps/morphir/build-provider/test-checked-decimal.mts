import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkedDecimalRuntimeFiles,checkedDecimalSourceTree,verifyCheckedDecimalRuntime} from './checked-decimal.mjs';
const sdk=fileURLToPath(new URL('../../../pkgs/morphir-sdk/',import.meta.url));
const root=mkdtempSync(join(tmpdir(),'morphir-decimal-pin-'));
try {
  assert.equal(checkedDecimalSourceTree,'642fd13ea74bc46c3f5344844c9cca4ffbae368a');
  verifyCheckedDecimalRuntime(sdk);
  assert.throws(()=>verifyCheckedDecimalRuntime(root),/build.missing_checked_decimal_extension/);
  for(const [path] of checkedDecimalRuntimeFiles) {
    mkdirSync(dirname(join(root,path)),{recursive:true});
    writeFileSync(join(root,path),readFileSync(join(sdk,path),'utf8').replaceAll('\r\n','\n').replaceAll('\n','\r\n'));
  }
  verifyCheckedDecimalRuntime(root);
  const checked=join(root,'decimal/checked.mbt');
  writeFileSync(checked,readFileSync(checked,'utf8').replace('raise Underflow','raise DivisionByZero'));
  assert.throws(()=>verifyCheckedDecimalRuntime(root),/build.checked_decimal_source_identity/);
  rmSync(checked);
  assert.throws(()=>verifyCheckedDecimalRuntime(root),/build.missing_checked_decimal_extension/);
  console.log('Checked Decimal runtime source evidence rejects missing/modified APIs and accepts checkout line endings');
} finally {rmSync(root,{recursive:true,force:true});}
