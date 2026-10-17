import {parentPort} from "node:worker_threads";
import {createCompiler} from "./node.mjs";
import {createEmbeddedToolchain, serveToolchain} from "./index.mjs";

const port = parentPort;
if (!port) throw new Error("An owned worker port is required");
serveToolchain(createEmbeddedToolchain(createCompiler), listener => port.on("message", listener),
  result => port.postMessage(result));
