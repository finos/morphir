import { resolve } from "path";
import { defineConfig } from "vite";
//import elmPlugin from 'vite-plugin-elm'
import elm from "vite-plugin-elm-watch";

export default defineConfig(
  async ({ command, mode, isSsrBuild, isPreview }) => {
    let isServe = command === "serve";
    return {
      plugins: [elm({ mode: "debug" })],
      build: {
        rollupOptions: {
          input: {
            morphir: resolve(__dirname, "src/morphir.ts"),
            lib: resolve(__dirname, "src/lib.ts"),
            "compiler-api": resolve(__dirname, "src/compiler-api.ts"),
          },
        },
      },
    };
  }
);
