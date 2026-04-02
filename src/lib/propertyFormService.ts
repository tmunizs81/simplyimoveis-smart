import { adminDelete, adminInsert, adminStorageDelete, adminStorageUpload, adminUpdate, type CrudError } from "@/lib/adminCrud";
import type { Database } from "@/integrations/supabase/types";

type Property = Database["public"]["Tables"]["properties"]["Row"];
type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

export type PropertyFormValues = {
  title: string;
  address: string;
  neighborhood: string;
  city: string;
  price: number;
  bedrooms: number;
  suites: number;
  bathrooms: number;
  garage_spots: number;
  area: number;
  pool_size: number;
  nearby_points: string;
  type: Property["type"];
  status: Property["status"];
  description: string;
  featured: boolean;
  active: boolean;
};

const normalizeText = (value: string) => value.trim();

const nullableText = (value: string) => {
  const normalized = normalizeText(value);
  return normalized.length > 0 ? normalized : null;
};

const normalizeInteger = (value: number) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.trunc(parsed));
};

const normalizeDecimal = (value: number) => {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, parsed);
};

const getFileExtension = (file: File) => {
  const fileNameExtension = file.name.includes(".")
    ? file.name.split(".").pop()?.trim().toLowerCase()
    : "";

  if (fileNameExtension) return fileNameExtension;

  const mimeExtension = file.type.split("/").pop()?.trim().toLowerCase();
  return mimeExtension || "bin";
};

const getMediaFileType = (file: File) => (
  file.type.startsWith("video/") ? "video" : "image"
);

const formatCrudError = (prefix: string, error: CrudError | null | undefined) => {
  if (!error) return prefix;

  const details = error.details?.replace(/\s+/g, " ").trim();
  const meta = [
    error.stage ? `etapa: ${error.stage}` : null,
    error.debugId ? `ref: ${error.debugId}` : null,
    details ? `detalhe: ${details.slice(0, 220)}` : null,
  ].filter(Boolean).join(" | ");

  return meta ? `${prefix}: ${error.message} (${meta})` : `${prefix}: ${error.message}`;
};

function buildPropertyPayload(form: PropertyFormValues) {
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

export async function deletePropertyMediaItem(media: MediaRow) {
  const storageResult = await adminStorageDelete("property-media", [media.file_path]);
  if (storageResult.error) {
    throw new Error(storageResult.error.message);
  }

  const deleteResult = await adminDelete("property_media", { id: media.id });
  if (deleteResult.error) {
    throw new Error(deleteResult.error.message);
  }
}

type SavePropertyWithMediaParams = {
  editingProperty?: Property | null;
  userId: string;
  form: PropertyFormValues;
  mediaFiles: File[];
  existingMediaCount: number;
  onFileProgress?: (index: number, status: "uploading" | "registering" | "done" | "error", fileName: string) => void;
};

export async function savePropertyWithMedia({
  editingProperty,
  userId,
  form,
  mediaFiles,
  existingMediaCount,
  onFileProgress,
}: SavePropertyWithMediaParams): Promise<{ propertyId: string; uploadedCount: number }> {
  const payload = buildPropertyPayload(form);
  let propertyId = editingProperty?.id ?? null;
  let createdPropertyId: string | null = null;
  const createdMediaIds: string[] = [];
  const uploadedPaths: string[] = [];

  try {
    if (editingProperty) {
      const updateResult = await adminUpdate("properties", payload, { id: editingProperty.id });
      if (updateResult.error) throw new Error(updateResult.error.message);
    } else {
      const insertResult = await adminInsert("properties", { user_id: userId, ...payload });
      if (insertResult.error) throw new Error(insertResult.error.message);

      const insertedProperty = Array.isArray(insertResult.data)
        ? insertResult.data[0]
        : insertResult.data;

      propertyId = insertedProperty?.id ?? null;
      createdPropertyId = propertyId;

      if (!propertyId) {
        throw new Error("Não foi possível identificar o imóvel salvo.");
      }
    }

    for (let index = 0; index < mediaFiles.length; index += 1) {
      const file = mediaFiles[index];
      const storagePath = `${userId}/${propertyId}/${crypto.randomUUID()}.${getFileExtension(file)}`;

      onFileProgress?.(index, "uploading", file.name);
      const uploadResult = await adminStorageUpload("property-media", storagePath, file);
      if (uploadResult.error) {
        onFileProgress?.(index, "error", file.name);
        throw new Error(formatCrudError(`Falha ao enviar ${file.name}`, uploadResult.error));
      }

      uploadedPaths.push(storagePath);

      onFileProgress?.(index, "registering", file.name);
      const mediaResult = await adminInsert("property_media", {
        property_id: propertyId,
        file_path: storagePath,
        file_type: getMediaFileType(file),
        sort_order: existingMediaCount + index,
      });

      if (mediaResult.error) {
        await adminStorageDelete("property-media", [storagePath]);
        onFileProgress?.(index, "error", file.name);
        throw new Error(formatCrudError(`Falha ao registrar ${file.name}`, mediaResult.error));
      }

      const insertedMedia = Array.isArray(mediaResult.data)
        ? mediaResult.data[0]
        : mediaResult.data;

      if (insertedMedia?.id) {
        createdMediaIds.push(insertedMedia.id);
      }
      onFileProgress?.(index, "done", file.name);
    }

    if (!propertyId) {
      throw new Error("Não foi possível concluir o salvamento do imóvel.");
    }

    return { propertyId, uploadedCount: uploadedPaths.length };
  } catch (error) {
    if (createdMediaIds.length > 0) {
      await Promise.allSettled(
        createdMediaIds.map((mediaId) => adminDelete("property_media", { id: mediaId }))
      );
    }

    if (uploadedPaths.length > 0) {
      await adminStorageDelete("property-media", uploadedPaths);
    }

    if (createdPropertyId) {
      await adminDelete("properties", { id: createdPropertyId });
    }

    throw error;
  }
}