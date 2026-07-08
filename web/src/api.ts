export type ExpiryStatus = "expired" | "expiring" | "ok";

export interface Item {
  id: number;
  name: string;
  category: string;
  expiryDate: string;
  notes: string | null;
  createdAt: string;
  status: ExpiryStatus;
  daysUntil: number;
}

export interface Summary {
  total: number;
  expired: number;
  expiring: number;
  ok: number;
}

export interface NewItem {
  name: string;
  category: string;
  expiryDate: string;
  notes?: string;
}

async function json<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ? JSON.stringify(body.error) : `Request failed (${res.status})`);
  }
  return res.json() as Promise<T>;
}

export const api = {
  listItems: () => fetch("/api/items").then((r) => json<Item[]>(r)),
  summary: () => fetch("/api/summary").then((r) => json<Summary>(r)),
  createItem: (item: NewItem) =>
    fetch("/api/items", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(item),
    }).then((r) => json<Item>(r)),
  deleteItem: (id: number) =>
    fetch(`/api/items/${id}`, { method: "DELETE" }).then((r) => {
      if (!r.ok && r.status !== 204) throw new Error(`Delete failed (${r.status})`);
    }),
};
