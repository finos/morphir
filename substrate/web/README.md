# substrate-web

React + TypeScript SPA served by `substrate dev`. Built with Vite.

## Layout

```
web/
  index.html              ← Vite entry
  public/                 ← static, copied verbatim into the build
  src/
    main.tsx              ← root render
    App.tsx, App.module.css
    types.ts              ← API shapes shared with src/commands/dev.ts
    api/client.ts         ← typed fetch wrappers
    hooks/                ← useTree, useDoc, useLiveReload
    components/
      TopBar/             ← <Component>.tsx + <Component>.module.css
      Tree/
      Viewer/
    styles/global.css     ← brand tokens + baseline
  vite.config.ts          ← build output → ../assets/web; dev proxy → :5173
  tsconfig*.json
```

Conventions:

- **One folder per component** under `components/`, each containing its
  `.tsx` and a co-located `.module.css`. Add a `__tests__/` sibling
  inside the folder when tests arrive.
- **CSS modules** for component styles; only `styles/global.css` is global.
- **Brand tokens** are imported via the global stylesheet
  (`@import "../../../branding/tokens.css"`) so colours, type scale,
  and spacing stay in lock-step with the rest of the project.
- **API shapes** (`types.ts`) mirror the JSON contract served by
  `src/commands/dev.ts`. Keep both ends in sync when a payload changes.

## Scripts

From the repo root (recommended):

| Command | What it does |
| --- | --- |
| `npm run build` | Build the CLI (`tsc`) and the web bundle (`vite build` → `assets/web/`). |
| `npm run build:web` | Build only the web bundle. |
| `npm run dev:web` | Start `substrate dev` on :5173 **and** the Vite dev server on :5174 with HMR; open <http://127.0.0.1:5174/>. |
| `npm run web:install` | Install `web/`'s dependencies. |

Or directly inside `web/`:

| Command | What it does |
| --- | --- |
| `npm run dev` | Vite dev server only — expects something on `VITE_BACKEND` (default `http://127.0.0.1:5173`) to serve `/api` and `/_ws`. |
| `npm run build` | Production build to `../assets/web/`. |
| `npm run typecheck` | Project-references type check, no emit. |

## Dev loop

1. Make sure the CLI is built once: `npm run build:cli`.
2. `npm run dev:web` (from the repo root) — starts substrate dev + Vite.
3. Open <http://127.0.0.1:5174/>. Edit anything in `web/src/`; HMR
   updates the page in place. Edit anything in the corpus the CLI is
   serving (`specs/` by default); the WebSocket pushes a notification
   and the viewer re-fetches the document.

## Production loop

`npm run build` produces a self-contained bundle in `assets/web/`.
`substrate dev` serves that bundle as static files (no Vite in the
loop) — this is what end users get from the npm package.
