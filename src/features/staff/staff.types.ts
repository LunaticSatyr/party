export type StaffSort = "recommended" | "rating" | "most-booked" | "newest";

export interface StaffPhoto {
  id: string;
  url: string;
  order: number;
}

export interface StaffReview {
  id: string;
  rating: number;
  comment: string;
  reviewerName: string;
  createdAt: string;
}

export interface StaffProfile {
  id: string;
  slug: string;
  displayName: string;
  age?: number;
  countryCode: string;
  avatar: string;
  photos: StaffPhoto[];
  shortBio: string;
  longBio: string;
  location: string;
  roles: string[];
  languages: string[];
  averageRating: number;
  reviewCount: number;
  reviews: StaffReview[];
  totalJobsWorked: number;
  isAvailable: boolean;
  joinedAt: string;
}

export interface StaffListQuery {
  query?: string;
  location?: string;
  role?: string;
  available?: boolean;
  sort?: StaffSort;
  limit?: number;
  offset?: number;
}

export interface StaffListResponse {
  data: StaffProfile[];
  meta: {
    total: number;
    limit: number;
    offset: number;
  };
}

export interface StaffFacets {
  locations: string[];
  roles: string[];
}

export interface StaffRepository {
  list(query?: StaffListQuery): Promise<StaffListResponse>;
  getBySlug(slug: string): Promise<StaffProfile | null>;
  getFacets(): Promise<StaffFacets>;
}
