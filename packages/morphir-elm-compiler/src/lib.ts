import CLI from "./elm/Morphir/Elm/CLI.elm";

const app = CLI.init({ flags: { a: "Alpha", b: "Beta" } });
console.log(app);
