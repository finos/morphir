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
    "8ead8650551067ec16f3fac1632dc0c6890c1b329c835e9205c895ed793b8fba"
  ],
  [
    "decimal/decimal.mbt",
    "a6b3d1a5bf031f6a2e2cd48e210f791e4f066586d40c58efffce1c34ad350269"
  ],
  [
    "sdk.mbt",
    "c91df29d89db2c277ed8ab860e6723780d1700838b3f9e2557410a99065aeaac"
  ],
  [
    "text.mbt",
    "35323ba617c8213af1f902e88df55952aea1d47cc1128efae8d20ebecc692236"
  ],
  [
    "integer/integer.mbt",
    "43bea6f88b7c32192f9c92489e82bf84ddecd8c2822190d388a84aeba8f94f58"
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
