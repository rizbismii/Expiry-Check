# AGENTS.md

Expiry-Check is an npm-workspaces monorepo with a `server` (Express + SQLite
REST API) and a `web` (React + Vite) frontend. See `README.md` for the full
command list, ports, and API reference.

## Cursor Cloud specific instructions

- Dependencies install from the repo root with a single `npm install` (npm
  workspaces hoists both `server` and `web`).
- Start both services with `npm run dev` from the repo root; it runs the API on
  port `4000` and the Vite dev server on port `5173`. Do all UI testing through
  `http://localhost:5173` — Vite proxies `/api/*` to the backend, so the web app
  does not need `VITE_*` config to reach the API.
- The backend persists to a SQLite file at `server/data/expiry-check.db` (created
  on first run, git-ignored). To reset local state, stop the server and delete
  that file, or `DELETE /api/items/:id`. Tests use an in-memory DB and never
  touch this file.
- `better-sqlite3` is a native module; it installs via a prebuilt binary during
  `npm install`. If it ever fails to load after a Node version change, rerun
  `npm install` (or `npm rebuild better-sqlite3 -w server`) to refetch/rebuild it.
- Lint/test/build: `npm run lint`, `npm test` (vitest, backend only), and
  `npm run build` (type-checks + builds both packages).
