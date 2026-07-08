import { describe, it, expect, beforeEach } from "vitest";
import request from "supertest";
import { createApp } from "../src/app.js";
import { createDb } from "../src/db.js";

function makeApp() {
  const db = createDb(":memory:");
  return createApp(db);
}

describe("Expiry-Check API", () => {
  let app: ReturnType<typeof makeApp>;

  beforeEach(() => {
    app = makeApp();
  });

  it("reports health", async () => {
    const res = await request(app).get("/api/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
  });

  it("starts with no items", async () => {
    const res = await request(app).get("/api/items");
    expect(res.status).toBe(200);
    expect(res.body).toEqual([]);
  });

  it("creates and lists an item with a computed status", async () => {
    const create = await request(app)
      .post("/api/items")
      .send({ name: "Passport", category: "Documents", expiryDate: "2000-01-01" });
    expect(create.status).toBe(201);
    expect(create.body.id).toBeGreaterThan(0);
    expect(create.body.status).toBe("expired");

    const list = await request(app).get("/api/items");
    expect(list.body).toHaveLength(1);
    expect(list.body[0].name).toBe("Passport");
  });

  it("rejects invalid input", async () => {
    const res = await request(app).post("/api/items").send({ name: "" });
    expect(res.status).toBe(400);
    expect(res.body.error).toBeDefined();
  });

  it("summarizes counts by status", async () => {
    await request(app)
      .post("/api/items")
      .send({ name: "Old milk", expiryDate: "2000-01-01" });
    await request(app)
      .post("/api/items")
      .send({ name: "Future thing", expiryDate: "2999-01-01" });
    const res = await request(app).get("/api/summary");
    expect(res.body.total).toBe(2);
    expect(res.body.expired).toBe(1);
    expect(res.body.ok).toBe(1);
  });

  it("deletes an item", async () => {
    const create = await request(app)
      .post("/api/items")
      .send({ name: "Temp", expiryDate: "2999-01-01" });
    const id = create.body.id;
    const del = await request(app).delete(`/api/items/${id}`);
    expect(del.status).toBe(204);
    const list = await request(app).get("/api/items");
    expect(list.body).toHaveLength(0);
  });
});
