export interface Packet {
  label: string;
  payload: Uint8Array;
  encoding: 'ion-binary' | 'morphir-json';
}

export interface Probe {
  exchange(input: Packet): Packet;
  calls(): number;
  close(): void;
  trap(): void;
  spin(): void;
}

function check(condition: boolean, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function refused(action: () => unknown, tag: string): void {
  try {
    action();
  } catch (error) {
    check(typeof error === 'object' && error !== null && 'payload' in error,
      'Expected a typed component result error');
    const payload = error.payload;
    check(typeof payload === 'object' && payload !== null && 'tag' in payload && payload.tag === tag,
      `Expected result error ${tag}`);
    if (tag === 'refused') {
      check('val' in payload && payload.val === 'payload exceeds 65536 bytes', 'Refusal detail changed');
    }
    return;
  }
  throw new Error(`Expected ${tag} to be refused`);
}

/** Exercise canonical ABI ownership as well as values. No Node/browser dependencies. */
export function qualify(api: Probe) {
  check(api.calls() === 0, 'New instance retained another instance\'s state');
  // Ion binary IVM followed by integer 42. This fixture transports bytes, not Morphir IR.
  const ion = new Uint8Array([0xe0, 1, 0, 0xea, 0x21, 42]);
  const label = 'Morphir 😀 𝄞 e\u0301 雪\u0000';
  const first = api.exchange({label, payload: ion, encoding: 'ion-binary'});
  check(first.label === label && first.encoding === 'ion-binary', 'Unicode/enum changed');
  check(first.payload.length === ion.length && first.payload.every((b, i) => b === ion[i]), 'Ion bytes changed');
  const saved = [...first.payload];
  const maximum = Uint8Array.from({length: 65536}, (_, i) => i & 255);
  const large = api.exchange({label: '', payload: maximum, encoding: 'ion-binary'});
  check(large.label === '' && large.payload.length === maximum.length && large.payload.every((b, i) => b === maximum[i]),
    'Maximum-size binary payload changed');
  const json = new TextEncoder().encode('{"formatVersion":3,"distribution":[]}');
  const exported = api.exchange({label: 'JSON remains supported', payload: json, encoding: 'morphir-json'});
  check(exported.encoding === 'morphir-json' && new TextDecoder().decode(exported.payload) === new TextDecoder().decode(json),
    'Explicit JSON bytes changed');
  const empty = api.exchange({label: '', payload: new Uint8Array(), encoding: 'ion-binary'});
  check(empty.payload.length === 0, 'Empty list changed');
  for (let i = 0; i < 100; ++i) {
    const result = api.exchange({label: `${label}${i}`, payload: new Uint8Array([0, i, 255]), encoding: 'ion-binary'});
    check(result.label === `${label}${i}` && result.payload[1] === i, 'Repeated call corrupted a value');
  }
  check(first.payload.length === saved.length && first.payload.every((b, i) => b === saved[i]),
    'Later calls/post-return invalidated a retained host result');
  refused(() => api.exchange({label, payload: new Uint8Array(65537), encoding: 'ion-binary'}), 'refused');
  check(api.calls() === 104, 'Rejected request changed accepted-call state');
  // A typed refusal leaves the instance usable.
  api.exchange({label: 'after refusal', payload: ion, encoding: 'ion-binary'});
  check(api.calls() === 105, 'Instance did not recover after a typed failure');
  api.close();
  api.close();
  refused(() => api.exchange({label, payload: ion, encoding: 'ion-binary'}), 'closed');
  check(api.calls() === 105, 'Closed instance accepted a request');
  return {acceptedCalls: 105, unicode: true, binary: true, explicitJson: true, retainedOutput: true,
    typedFailure: true, closed: true};
}
