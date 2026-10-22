// Fixed-effect unit controls: real Blob/URL, DOM stand-in and deliberately
// throwing browser methods. These are not browser-completion or encoder proofs.
import assert from 'node:assert/strict';
import {test} from 'node:test';
import {requestOriginalArchiveDownload} from './originals-archive-download.ts';

for (const scenario of ['click-remove-revoke', 'click-revoke', 'remove-revoke'] as const) {
  test(`fixed archive effect preserves its first failure: ${scenario}`, () => {
    const clickFailure = new Error('actual click method failure');
    const removeFailure = new Error('actual remove method failure');
    const revokeFailure = new Error('actual revoke method failure');
    const documentDescriptor = Object.getOwnPropertyDescriptor(globalThis, 'document');
    const create = URL.createObjectURL, revoke = URL.revokeObjectURL;
    const attempts: string[] = [];
    let actualUrl: string | undefined, actualBlob: Blob | undefined;
    const link = {
      href: '', download: '',
      click() {attempts.push('click'); if (scenario !== 'remove-revoke') throw clickFailure;},
      remove() {attempts.push('remove'); if (scenario !== 'click-revoke') throw removeFailure;},
    };
    Object.defineProperty(globalThis, 'document', {configurable: true, value: {
      createElement(name: string) {assert.equal(name, 'a'); return link;},
      body: {append(actual: unknown) {assert.equal(actual, link); attempts.push('append');}},
    }});
    URL.createObjectURL = object => {
      assert(object instanceof Blob); actualBlob = object;
      actualUrl = create(object); return actualUrl;
    };
    URL.revokeObjectURL = url => {
      attempts.push('revoke'); assert.equal(url, actualUrl);
      revoke(url); throw revokeFailure;
    };
    try {
      const expected = scenario === 'remove-revoke' ? removeFailure : clickFailure;
      assert.throws(() => requestOriginalArchiveDownload(new Uint8Array([0, 255, 13, 10])), failure => failure === expected);
      assert.deepEqual(attempts, ['append', 'click', 'remove', 'revoke']);
      assert(actualBlob instanceof Blob); assert.equal(actualBlob.size, 4);
      assert.equal(link.download, 'morphir-originals.zip'); assert.equal(link.href, actualUrl);
    } finally {
      URL.createObjectURL = create; URL.revokeObjectURL = revoke;
      if (actualUrl) revoke(actualUrl);
      if (documentDescriptor) Object.defineProperty(globalThis, 'document', documentDescriptor);
      else Reflect.deleteProperty(globalThis, 'document');
    }
  });
}
