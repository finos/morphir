import {createWorkerToolchain} from "./index.mjs";

export function createBrowserToolchain({workerURL = new URL("./dist/browser-worker.js", import.meta.url)}: { workerURL?: URL | string } = {}) {
  return createWorkerToolchain(new Worker(workerURL, {type: "module"}));
}
