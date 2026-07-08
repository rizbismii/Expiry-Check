import express, { type Express } from "express";
import cors from "cors";
import { z } from "zod";
import type Database from "better-sqlite3";
import type { ItemRow } from "./db.js";
import { statusFor, daysUntil } from "./status.js";

const itemInput = z.object({
  name: z.string().trim().min(1, "name is required").max(200),
  category: z.string().trim().min(1).max(80).default("General"),
  expiryDate: z
    .string()
    .refine((v) => !Number.isNaN(Date.parse(v)), "expiryDate must be a valid date"),
  notes: z.string().trim().max(1000).optional().nullable(),
});

function serialize(row: ItemRow, now: Date) {
  return {
    id: row.id,
    name: row.name,
    category: row.category,
    expiryDate: row.expiry_date,
    notes: row.notes,
    createdAt: row.created_at,
    status: statusFor(row.expiry_date, now),
    daysUntil: daysUntil(row.expiry_date, now),
  };
}

export function createApp(db: Database.Database): Express {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get("/api/health", (_req, res) => {
    res.json({ status: "ok", time: new Date().toISOString() });
  });

  app.get("/api/items", (_req, res) => {
    const rows = db
      .prepare("SELECT * FROM items ORDER BY expiry_date ASC")
      .all() as ItemRow[];
    const now = new Date();
    res.json(rows.map((r) => serialize(r, now)));
  });

  app.get("/api/summary", (_req, res) => {
    const rows = db.prepare("SELECT * FROM items").all() as ItemRow[];
    const now = new Date();
    const summary = { total: rows.length, expired: 0, expiring: 0, ok: 0 };
    for (const row of rows) summary[statusFor(row.expiry_date, now)] += 1;
    res.json(summary);
  });

  app.post("/api/items", (req, res) => {
    const parsed = itemInput.safeParse(req.body);
    if (!parsed.success) {
      return res.status(400).json({ error: parsed.error.flatten() });
    }
    const { name, category, expiryDate, notes } = parsed.data;
    const info = db
      .prepare(
        "INSERT INTO items (name, category, expiry_date, notes) VALUES (?, ?, ?, ?)",
      )
      .run(name, category, expiryDate, notes ?? null);
    const row = db
      .prepare("SELECT * FROM items WHERE id = ?")
      .get(info.lastInsertRowid) as ItemRow;
    res.status(201).json(serialize(row, new Date()));
  });

  app.delete("/api/items/:id", (req, res) => {
    const id = Number(req.params.id);
    if (!Number.isInteger(id)) return res.status(400).json({ error: "invalid id" });
    const info = db.prepare("DELETE FROM items WHERE id = ?").run(id);
    if (info.changes === 0) return res.status(404).json({ error: "not found" });
    res.status(204).end();
  });

  return app;
}
