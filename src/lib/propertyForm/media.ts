import { adminDelete, adminStorageDelete } from "@/lib/adminCrud";
import type { MediaRow } from "@/lib/propertyForm/types";

export const getFileExtension = (file: File) => {
  const fileNameExtension = file.name.includes(".")
    ? file.name.split(".").pop()?.trim().toLowerCase()
    : "";

  if (fileNameExtension) return fileNameExtension;

  const mimeExtension = file.type.split("/").pop()?.trim().toLowerCase();
  return mimeExtension || "bin";
};

export const getMediaFileType = (file: File) => (
  file.type.startsWith("video/") ? "video" : "image"
);

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