# Expiry-Check

Track and get alerted about things that are about to expire — passports, SSL
certificates, warranties, groceries, subscriptions, anything with a date.

It's an npm-workspaces monorepo with two services:

| Package  | Path      | Stack                                  | Dev port |
| -------- | --------- | -------------------------------------- | -------- |
| `server` | `server/` | Express + TypeScript + SQLite (better-sqlite3) REST API | `4000` |
| `web`    | `web/`    | React + Vite + TypeScript UI           | `5173`   |

The web dev server proxies `/api/*` to the backend, so you only interact with
`http://localhost:5173`.

## Prerequisites

- Node.js 22+
- npm 10+

## Setup

```bash
npm install
```

## Run (development)

Start both services together from the repo root:

```bash
npm run dev
```

- Web UI: http://localhost:5173
- API: http://localhost:4000 (health check at `/api/health`)

Run a single service instead:

```bash
npm run dev -w server
npm run dev -w web
```

## Test / lint / build

```bash
npm test        # backend unit + API tests (vitest)
npm run lint    # eslint for both packages
npm run build   # type-check + production build for both packages
```

## API

| Method   | Endpoint          | Description                          |
| -------- | ----------------- | ------------------------------------ |
| `GET`    | `/api/health`     | Health check                         |
| `GET`    | `/api/items`      | List items (sorted by expiry date)   |
| `GET`    | `/api/summary`    | Counts by status                     |
| `POST`   | `/api/items`      | Create an item                       |
| `DELETE` | `/api/items/:id`  | Delete an item                       |

Each item is classified as `expired`, `expiring` (within 30 days), or `ok`.

## Data

The backend stores data in a SQLite file at `server/data/expiry-check.db`
(override with the `DB_FILE` env var). Tests use an in-memory database.
