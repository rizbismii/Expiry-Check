import Database from "better-sqlite3";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export interface ItemRow {
  id: number;
  name: string;
  category: string;
  expiry_date: string;
  notes: string | null;
  created_at: string;
}

export function createDb(file: string): Database.Database {
  if (file !== ":memory:") {
    mkdirSync(dirname(file), { recursive: true });
  }
  const db = new Database(file);
  db.pragma("journal_mode = WAL");
  db.exec(`
    CREATE TABLE IF NOT EXISTS items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'General',
      expiry_date TEXT NOT NULL,
      notes TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);
  return db;
}
