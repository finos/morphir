// Fixed trusted-driver entry. No arbitrary module URL, program or expression.
import {productObservation, type ObservationLimits, type ProductFact} from './product-observer.ts';

export async function startObservedWorkbench(limits: ObservationLimits, receive: (actual: ProductFact) => void) {
  const attached = productObservation.attach(document, limits, receive);
  if (attached !== 'attached') throw new Error(`Workbench observation attachment refused: ${attached}`);
  const close = () => {removeEventListener('pagehide', close); productObservation.close();};
  addEventListener('pagehide', close, {once: true});
  try {await import(new URL('./bootstrap.js', import.meta.url).href);}
  catch (error) {close(); throw error;}
  return Object.freeze({state: productObservation.state, close});
}
