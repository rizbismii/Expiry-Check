import { createApp } from "./app.js";
import { createDb } from "./db.js";

const PORT = Number(process.env.PORT ?? 4000);
const DB_FILE = process.env.DB_FILE ?? "data/expiry-check.db";

const db = createDb(DB_FILE);
const app = createApp(db);

app.listen(PORT, () => {
  console.log(`Expiry-Check API listening on http://localhost:${PORT}`);
  console.log(`Using database: ${DB_FILE}`);
});
