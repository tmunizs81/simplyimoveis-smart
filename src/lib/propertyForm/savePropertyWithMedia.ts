import { adminDelete, adminInsert, adminStorageDelete, adminStorageUpload, adminUpdate } from "@/lib/adminCrud";
import { formatCrudError } from "@/lib/propertyForm/errors";
import { getFileExtension, getMediaFileType } from "@/lib/propertyForm/media";
import { buildPropertyPayload } from "@/lib/propertyForm/propertyPayload";
import type { SavePropertyWithMediaParams, SavePropertyWithMediaResult } from "@/lib/propertyForm/types";

type SaveRuntimeState = {
  propertyId: string | null;
  createdPropertyId: string | null;
  createdMediaIds: string[];
  uploadedPaths: string[];
};

async function persistProperty(
  params: Pick<SavePropertyWithMediaParams, "editingProperty" | "form" | "userId">,
  state: SaveRuntimeState,
) {
  const payload = buildPropertyPayload(params.form);

  if (params.editingProperty) {
    const updateResult = await adminUpdate("properties", payload, { id: params.editingProperty.id });
    if (updateResult.error) {
      throw new Error(formatCrudError("Falha ao salvar o imóvel", updateResult.error));
    }

    state.propertyId = params.editingProperty.id;
    return;
  }

  const insertResult = await adminInsert("properties", { user_id: params.userId, ...payload });
  if (insertResult.error) {
    throw new Error(formatCrudError("Falha ao criar o imóvel", insertResult.error));
  }

  const insertedProperty = Array.isArray(insertResult.data)
    ? insertResult.data[0]
    : insertResult.data;

  state.propertyId = insertedProperty?.id ?? null;
  state.createdPropertyId = state.propertyId;

  if (!state.propertyId) {
    throw new Error("Não foi possível identificar o imóvel salvo.");
  }
}

async function uploadMediaFiles(
  params: Pick<SavePropertyWithMediaParams, "mediaFiles" | "existingMediaCount" | "onFileProgress" | "userId">,
  state: SaveRuntimeState,
) {
  if (!state.propertyId) {
    throw new Error("Não foi possível concluir o salvamento do imóvel.");
  }

  for (let index = 0; index < params.mediaFiles.length; index += 1) {
    const file = params.mediaFiles[index];
    const storagePath = `${params.userId}/${state.propertyId}/${crypto.randomUUID()}.${getFileExtension(file)}`;

    params.onFileProgress?.(index, "uploading", file.name);
    const uploadResult = await adminStorageUpload("property-media", storagePath, file);
    if (uploadResult.error) {
      params.onFileProgress?.(index, "error", file.name);
      throw new Error(formatCrudError(`Falha ao enviar ${file.name}`, uploadResult.error));
    }

    state.uploadedPaths.push(storagePath);

    params.onFileProgress?.(index, "registering", file.name);
    const mediaResult = await adminInsert("property_media", {
      property_id: state.propertyId,
      file_path: storagePath,
      file_type: getMediaFileType(file),
      sort_order: params.existingMediaCount + index,
    });

    if (mediaResult.error) {
      await adminStorageDelete("property-media", [storagePath]);
      params.onFileProgress?.(index, "error", file.name);
      throw new Error(formatCrudError(`Falha ao registrar ${file.name}`, mediaResult.error));
    }

    const insertedMedia = Array.isArray(mediaResult.data)
      ? mediaResult.data[0]
      : mediaResult.data;

    if (insertedMedia?.id) {
      state.createdMediaIds.push(insertedMedia.id);
    }

    params.onFileProgress?.(index, "done", file.name);
  }
}

async function rollbackFailedSave(state: SaveRuntimeState) {
  if (state.createdMediaIds.length > 0) {
    await Promise.allSettled(
      state.createdMediaIds.map((mediaId) => adminDelete("property_media", { id: mediaId })),
    );
  }

  if (state.uploadedPaths.length > 0) {
    await adminStorageDelete("property-media", state.uploadedPaths);
  }

  if (state.createdPropertyId) {
    await adminDelete("properties", { id: state.createdPropertyId });
  }
}

export async function savePropertyWithMedia(
  params: SavePropertyWithMediaParams,
): Promise<SavePropertyWithMediaResult> {
  const state: SaveRuntimeState = {
    propertyId: params.editingProperty?.id ?? null,
    createdPropertyId: null,
    createdMediaIds: [],
    uploadedPaths: [],
  };

  try {
    await persistProperty(params, state);
    await uploadMediaFiles(params, state);

    if (!state.propertyId) {
      throw new Error("Não foi possível concluir o salvamento do imóvel.");
    }

    return {
      propertyId: state.propertyId,
      uploadedCount: state.uploadedPaths.length,
    };
  } catch (error) {
    await rollbackFailedSave(state);
    throw error;
  }
}