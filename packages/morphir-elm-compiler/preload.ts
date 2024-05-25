import { plugin } from "bun";
import { ElmPlugin } from "bun-elm-plugin";

console.log("Preload is running...");

console.log("Registering Elm plugin...");
plugin(ElmPlugin());

console.log("Preload is done.");
