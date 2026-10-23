// Fixed controlled-host document entry. No configurable module, evaluator,
// global event publisher, reconnect or unobserved fallback.
import {prepareDocumentChannel} from './product-document-channel.ts';
import {startObservedWorkbench} from './observed-bootstrap.ts';

const endpoint = new URL('/_mck/document', location.origin);
const response = await fetch(endpoint, {method: 'POST', credentials: 'same-origin', cache: 'no-store', redirect: 'error'});
if (response.status !== 200) throw new Error('Workbench document transport preparation refused');
// Fetch/JSON engine allocation is outside the adapter's typed-backing mirror.
// The authenticated native host owns the canonical, bounded bootstrap body.
const prepared = prepareDocumentChannel(await response.json());
if (prepared.kind !== 'prepared') throw new Error(`Workbench document transport refused: ${prepared.first}`);
endpoint.protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:';
const channel = prepared.channel, socket = new WebSocket(endpoint, [...channel.protocols]);
addEventListener('pagehide', channel.revoke, {once: true});
void channel.whenClosed().then(() => removeEventListener('pagehide', channel.revoke));
// Module completion is the real start-returned boundary. Native STOP must wait
// for this fixed entry to finish, never infer readiness from101 or the firstFACT.
await channel.attach(socket, startObservedWorkbench);
