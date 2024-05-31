import CLI from "./elm/Morphir/Elm/CLI.elm";
const worker = CLI.init();

export function compileSource(source: string) {
  console.log("Compiling source: ", source);
  console.log("Worker: ", worker);
}
