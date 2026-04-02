export const normalizeText = (value: string) => value.trim();

export const nullableText = (value: string) => {
  const normalized = normalizeText(value);
  return normalized.length > 0 ? normalized : null;
};

export const normalizeInteger = (value: number) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.trunc(parsed));
};

export const normalizeDecimal = (value: number) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, parsed);
};