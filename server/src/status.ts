export type ExpiryStatus = "expired" | "expiring" | "ok";

export const EXPIRING_SOON_DAYS = 30;

const MS_PER_DAY = 1000 * 60 * 60 * 24;

/**
 * Whole days from `now` until `expiryDate`. Negative when already expired.
 * Both dates are normalized to UTC midnight so partial days never skew the
 * count (an item expiring "today" reads as 0 days, not -0.4).
 */
export function daysUntil(expiryDate: string, now: Date = new Date()): number {
  const expiry = Date.parse(expiryDate);
  const today = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const target = new Date(expiry);
  const targetUtc = Date.UTC(
    target.getUTCFullYear(),
    target.getUTCMonth(),
    target.getUTCDate(),
  );
  return Math.round((targetUtc - today) / MS_PER_DAY);
}

export function statusFor(
  expiryDate: string,
  now: Date = new Date(),
  expiringSoonDays: number = EXPIRING_SOON_DAYS,
): ExpiryStatus {
  const days = daysUntil(expiryDate, now);
  if (days < 0) return "expired";
  if (days <= expiringSoonDays) return "expiring";
  return "ok";
}
