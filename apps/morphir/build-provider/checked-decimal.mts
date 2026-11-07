import assert from 'node:assert/strict';
import {existsSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash} from 'node:crypto';

// Audited runtime implementation of morphir-sdk-decimal-checked-v1. Compare
// required source files, allowing checkout line endings and unrelated SDK files.
export const checkedDecimalSourceTree='642fd13ea74bc46c3f5344844c9cca4ffbae368a';
export const checkedDecimalRuntimeFiles: readonly (readonly [string,string])[]=[
  [
    "decimal/checked.mbt",
    "e9529b88708469991d3751d1fe60b63db32b308f12c5278468188197adaf0172"
  ],
  [
    "decimal/decimal.mbt",
    "10705d91bbc1e7b4bf895402c0d8bd051d09621aa37cc67e375b6a63a1c1bd90"
  ],
  [
    "sdk.mbt",
    "8f95eb1459047e4ebdce6084c9a8b0423d294962647e7ec072530c0754555ab8"
  ],
  [
    "text.mbt",
    "cceaeab6b6e344cb05ec8cf6f0e506d3f1b88bf7c7c1f089eee36367f55a8308"
  ],
  [
    "integer/integer.mbt",
    "a64200c51e63a82d730df5cd33c5e1f3a9ba41f0e6e0c13ec381f7e0a53db3d5"
  ],
  [
    "decimal/moon.pkg",
    "f03386d47143f77aeaffa5abbfcd5ffdc3f913e3453f9292705373f75bda23d9"
  ],
  [
    "integer/moon.pkg",
    "0365602bf4c7b3e49478ca2d2c2c3a2c40258d3a4c44c24823e1985bcc60746c"
  ],
  [
    "moon.pkg",
    "f55457e90e133b551bb83a9ac6b3f26b4d21e6678155f918c885105a723bf059"
  ]
];

export function verifyCheckedDecimalRuntime(root: string) {
  for(const [path,expected] of checkedDecimalRuntimeFiles) {
    const file=join(root,path);
    assert.ok(existsSync(file),'build.missing_checked_decimal_extension: '+path);
    const bytes=readFileSync(file,'utf8').replaceAll('\r\n','\n');
    assert.equal(createHash('sha256').update(bytes).digest('hex'),expected,'build.checked_decimal_source_identity: '+path);
  }
}
