import { describe, it, expect } from "vitest";
import { daysUntil, statusFor } from "../src/status.js";

const NOW = new Date("2026-01-15T12:00:00Z");

describe("daysUntil", () => {
  it("returns 0 for the same day", () => {
    expect(daysUntil("2026-01-15", NOW)).toBe(0);
  });

  it("returns a positive count for future dates", () => {
    expect(daysUntil("2026-01-25", NOW)).toBe(10);
  });

  it("returns a negative count for past dates", () => {
    expect(daysUntil("2026-01-05", NOW)).toBe(-10);
  });
});

describe("statusFor", () => {
  it("flags past dates as expired", () => {
    expect(statusFor("2026-01-14", NOW)).toBe("expired");
  });

  it("flags dates within the soon window as expiring", () => {
    expect(statusFor("2026-01-20", NOW)).toBe("expiring");
    expect(statusFor("2026-02-14", NOW)).toBe("expiring");
  });

  it("flags far-out dates as ok", () => {
    expect(statusFor("2026-03-01", NOW)).toBe("ok");
  });
});
