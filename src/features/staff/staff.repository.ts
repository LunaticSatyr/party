import { staffFixtures } from "./staff.fixtures";
import type {
  StaffFacets,
  StaffListQuery,
  StaffListResponse,
  StaffProfile,
  StaffRepository,
} from "./staff.types";

const DEFAULT_LIMIT = 24;
const MAX_LIMIT = 50;

function normalize(value: string): string {
  return value.trim().toLocaleLowerCase();
}

export class InMemoryStaffRepository implements StaffRepository {
  constructor(private readonly profiles: readonly StaffProfile[]) {}

  async list(query: StaffListQuery = {}): Promise<StaffListResponse> {
    const search = normalize(query.query ?? "");
    const location = normalize(query.location ?? "");
    const role = normalize(query.role ?? "");
    const limit = Math.min(Math.max(query.limit ?? DEFAULT_LIMIT, 1), MAX_LIMIT);
    const offset = Math.max(query.offset ?? 0, 0);

    const filtered = this.profiles.filter((profile) => {
      const matchesSearch =
        !search ||
        normalize(profile.displayName).includes(search) ||
        normalize(profile.shortBio).includes(search) ||
        profile.roles.some((item) => normalize(item).includes(search));
      const matchesLocation = !location || normalize(profile.location) === location;
      const matchesRole = !role || profile.roles.some((item) => normalize(item) === role);
      const matchesAvailability = query.available !== true || profile.isAvailable;

      return matchesSearch && matchesLocation && matchesRole && matchesAvailability;
    });

    filtered.sort((left, right) => {
      switch (query.sort) {
        case "rating":
          return right.averageRating - left.averageRating || right.reviewCount - left.reviewCount;
        case "most-booked":
          return right.totalJobsWorked - left.totalJobsWorked;
        case "newest":
          return Date.parse(right.joinedAt) - Date.parse(left.joinedAt);
        default:
          return (
            Number(right.isAvailable) - Number(left.isAvailable) ||
            right.averageRating - left.averageRating ||
            right.totalJobsWorked - left.totalJobsWorked
          );
      }
    });

    return {
      data: filtered.slice(offset, offset + limit),
      meta: { total: filtered.length, limit, offset },
    };
  }

  async getBySlug(slug: string): Promise<StaffProfile | null> {
    return this.profiles.find((profile) => profile.slug === slug) ?? null;
  }

  async getFacets(): Promise<StaffFacets> {
    return {
      locations: [...new Set(this.profiles.map((profile) => profile.location))].sort(),
      roles: [...new Set(this.profiles.flatMap((profile) => profile.roles))].sort(),
    };
  }
}

export const staffRepository: StaffRepository = new InMemoryStaffRepository(staffFixtures);
