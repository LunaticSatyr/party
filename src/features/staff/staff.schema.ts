import { z } from "astro/zod";

export const staffPhotoSchema = z.object({
  id: z.string().min(1),
  url: z.string().min(1),
  order: z.number().int().nonnegative(),
});

export const staffReviewSchema = z.object({
  id: z.string().min(1),
  rating: z.number().min(1).max(5),
  comment: z.string().min(1),
  reviewerName: z.string().min(1),
  createdAt: z.string().min(1),
});

export const staffProfileSchema = z.object({
  id: z.string().min(1),
  slug: z.string().regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/),
  displayName: z.string().min(1).max(80),
  age: z.number().int().min(18).max(100).optional(),
  countryCode: z.string().length(2),
  avatar: z.string().min(1),
  photos: z.array(staffPhotoSchema).min(1),
  shortBio: z.string().min(1).max(240),
  longBio: z.string().min(1).max(3000),
  location: z.string().min(1),
  roles: z.array(z.string().min(1)).min(1),
  languages: z.array(z.string().min(1)).min(1),
  averageRating: z.number().min(0).max(5),
  reviewCount: z.number().int().nonnegative(),
  reviews: z.array(staffReviewSchema),
  totalJobsWorked: z.number().int().nonnegative(),
  isAvailable: z.boolean(),
  joinedAt: z.string().min(1),
});

export const staffListResponseSchema = z.object({
  data: z.array(staffProfileSchema),
  meta: z.object({
    total: z.number().int().nonnegative(),
    limit: z.number().int().positive(),
    offset: z.number().int().nonnegative(),
  }),
});
