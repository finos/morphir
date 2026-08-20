import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";

// Default backend the dev server proxies API + WS requests to.
// Override with VITE_BACKEND=http://127.0.0.1:5173.
const BACKEND = process.env["VITE_BACKEND"] ?? "http://127.0.0.1:5173";

export default defineConfig({
    plugins: [react()],
    // Build the SPA into ../assets/web so `substrate dev` can serve it as
    // a static bundle in production.
    build: {
        outDir: resolve(__dirname, "../assets/web"),
        emptyOutDir: true,
        sourcemap: true,
    },
    server: {
        port: 5174,
        strictPort: true,
        proxy: {
            "/api": { target: BACKEND, changeOrigin: true },
            "/_ws": { target: BACKEND, ws: true, changeOrigin: true },
        },
    },
});
