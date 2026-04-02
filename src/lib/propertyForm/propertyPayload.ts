import type { PropertyFormValues } from "@/lib/propertyForm/types";
import { normalizeDecimal, normalizeInteger, normalizeText, nullableText } from "@/lib/propertyForm/normalizers";

export function buildPropertyPayload(form: PropertyFormValues) {
  const title = normalizeText(form.title);
  const address = normalizeText(form.address);

  if (!title) throw new Error("Informe o título do imóvel.");
  if (!address) throw new Error("Informe o endereço do imóvel.");

  return {
    title,
    address,
    neighborhood: nullableText(form.neighborhood),
    city: nullableText(form.city) ?? "Fortaleza",
    price: normalizeDecimal(form.price),
    bedrooms: normalizeInteger(form.bedrooms),
    suites: normalizeInteger(form.suites),
    bathrooms: normalizeInteger(form.bathrooms),
    garage_spots: normalizeInteger(form.garage_spots),
    area: normalizeDecimal(form.area),
    pool_size: normalizeDecimal(form.pool_size),
    nearby_points: nullableText(form.nearby_points),
    type: form.type,
    status: form.status,
    description: nullableText(form.description),
    featured: Boolean(form.featured),
    active: Boolean(form.active),
  };
}