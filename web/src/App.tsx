import { useEffect, useMemo, useState } from "react";
import { api, type Item, type NewItem, type Summary } from "./api.js";

const STATUS_LABEL: Record<Item["status"], string> = {
  expired: "Expired",
  expiring: "Expiring soon",
  ok: "Healthy",
};

function statusText(item: Item): string {
  if (item.status === "expired") {
    const d = Math.abs(item.daysUntil);
    return `Expired ${d} day${d === 1 ? "" : "s"} ago`;
  }
  if (item.daysUntil === 0) return "Expires today";
  return `${item.daysUntil} day${item.daysUntil === 1 ? "" : "s"} left`;
}

const EMPTY_FORM: NewItem = { name: "", category: "General", expiryDate: "", notes: "" };

export default function App() {
  const [items, setItems] = useState<Item[]>([]);
  const [summary, setSummary] = useState<Summary | null>(null);
  const [form, setForm] = useState<NewItem>(EMPTY_FORM);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function refresh() {
    const [list, sum] = await Promise.all([api.listItems(), api.summary()]);
    setItems(list);
    setSummary(sum);
    setLoading(false);
  }

  useEffect(() => {
    refresh().catch((e) => {
      setError(String(e));
      setLoading(false);
    });
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    try {
      await api.createItem({ ...form, notes: form.notes || undefined });
      setForm(EMPTY_FORM);
      await refresh();
    } catch (err) {
      setError(String(err));
    }
  }

  async function handleDelete(id: number) {
    setError(null);
    try {
      await api.deleteItem(id);
      await refresh();
    } catch (err) {
      setError(String(err));
    }
  }

  const cards = useMemo(
    () => [
      { key: "total", label: "Tracked", value: summary?.total ?? 0, tone: "neutral" },
      { key: "expired", label: "Expired", value: summary?.expired ?? 0, tone: "expired" },
      { key: "expiring", label: "Expiring soon", value: summary?.expiring ?? 0, tone: "expiring" },
      { key: "ok", label: "Healthy", value: summary?.ok ?? 0, tone: "ok" },
    ],
    [summary],
  );

  return (
    <div className="page">
      <header className="header">
        <h1>Expiry-Check</h1>
        <p>Never get caught off guard by an expiry date again.</p>
      </header>

      <section className="cards">
        {cards.map((c) => (
          <div key={c.key} className={`card card--${c.tone}`}>
            <span className="card__value">{c.value}</span>
            <span className="card__label">{c.label}</span>
          </div>
        ))}
      </section>

      <section className="panel">
        <h2>Add an item</h2>
        <form className="form" onSubmit={handleSubmit}>
          <label>
            Name
            <input
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              placeholder="Passport, Milk, SSL cert…"
              required
            />
          </label>
          <label>
            Category
            <input
              value={form.category}
              onChange={(e) => setForm({ ...form, category: e.target.value })}
              placeholder="Documents"
            />
          </label>
          <label>
            Expiry date
            <input
              type="date"
              value={form.expiryDate}
              onChange={(e) => setForm({ ...form, expiryDate: e.target.value })}
              required
            />
          </label>
          <label className="form__wide">
            Notes
            <input
              value={form.notes ?? ""}
              onChange={(e) => setForm({ ...form, notes: e.target.value })}
              placeholder="Optional"
            />
          </label>
          <button type="submit">Add item</button>
        </form>
        {error && <p className="error">{error}</p>}
      </section>

      <section className="panel">
        <h2>Items</h2>
        {loading ? (
          <p className="muted">Loading…</p>
        ) : items.length === 0 ? (
          <p className="muted">Nothing tracked yet. Add your first item above.</p>
        ) : (
          <ul className="list">
            {items.map((item) => (
              <li key={item.id} className={`row row--${item.status}`}>
                <div className="row__main">
                  <span className="row__name">{item.name}</span>
                  <span className="row__meta">
                    {item.category} · expires {item.expiryDate}
                  </span>
                  {item.notes && <span className="row__notes">{item.notes}</span>}
                </div>
                <div className="row__side">
                  <span className={`badge badge--${item.status}`}>
                    {STATUS_LABEL[item.status]}
                  </span>
                  <span className="row__days">{statusText(item)}</span>
                </div>
                <button
                  className="row__delete"
                  aria-label={`Delete ${item.name}`}
                  onClick={() => handleDelete(item.id)}
                >
                  ×
                </button>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
