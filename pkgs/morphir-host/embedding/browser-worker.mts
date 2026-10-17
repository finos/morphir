import {createCompiler} from "morphir:compiler-factory";
import {createEmbeddedToolchain, serveToolchain} from "./index.mjs";

serveToolchain(createEmbeddedToolchain(createCompiler), listener => addEventListener("message", e => listener(e.data)),
  result => postMessage(result));
