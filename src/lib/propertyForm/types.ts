import type { Database } from "@/integrations/supabase/types";

export type Property = Database["public"]["Tables"]["properties"]["Row"];
export type MediaRow = Database["public"]["Tables"]["property_media"]["Row"];

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

export type PropertyFileProgressStatus = "uploading" | "registering" | "done" | "error";

export type PropertyFileProgressHandler = (
  index: number,
  status: PropertyFileProgressStatus,
  fileName: string,
) => void;

export type SavePropertyWithMediaParams = {
  editingProperty?: Property | null;
  userId: string;
  form: PropertyFormValues;
  mediaFiles: File[];
  existingMediaCount: number;
  onFileProgress?: PropertyFileProgressHandler;
};

export type SavePropertyWithMediaResult = {
  propertyId: string;
  uploadedCount: number;
};