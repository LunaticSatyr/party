import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const publicPhotoBucket = "staff-profile-public";
const allowedOrigins = new Set(
  (Deno.env.get("STAFF_API_ALLOWED_ORIGINS") ?? "http://localhost:2608")
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
);

const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { persistSession: false },
});

function responseHeaders(origin: string | null): Headers {
  const headers = new Headers({
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Content-Type": "application/json; charset=utf-8",
    "Vary": "Origin",
  });

  if (origin && allowedOrigins.has(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
  }

  return headers;
}

function json(data: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(data), { status, headers: responseHeaders(origin) });
}

function publicPhotoUrl(path: string | null | undefined): string {
  if (!path) return "";
  return supabase.storage.from(publicPhotoBucket).getPublicUrl(path).data.publicUrl;
}

function toPublicProfile(record: Record<string, any>) {
  const photos = [...(record.staff_profile_photos ?? [])]
    .sort((left, right) => left.sort_order - right.sort_order)
    .map((photo) => ({
      id: photo.id,
      url: publicPhotoUrl(photo.public_path),
      order: photo.sort_order,
    }));

  return {
    id: record.id,
    slug: record.slug,
    displayName: record.display_name,
    age: record.public_age ?? undefined,
    countryCode: record.country_code,
    avatar: publicPhotoUrl(record.avatar_path) || photos[0]?.url || "",
    photos,
    shortBio: record.short_bio,
    longBio: record.long_bio,
    location: record.location,
    roles: (record.staff_profile_roles ?? []).map((item) => item.role?.label).filter(Boolean),
    languages: (record.staff_profile_languages ?? []).map((item) => item.language?.label).filter(Boolean),
    averageRating: Number(record.average_rating),
    reviewCount: record.review_count,
    reviews: (record.staff_reviews ?? []).map((review) => ({
      id: review.id,
      rating: review.rating,
      comment: review.comment,
      reviewerName: review.reviewer_name,
      createdAt: review.created_at,
    })),
    totalJobsWorked: record.total_jobs_worked,
    isAvailable: record.is_available,
    joinedAt: record.created_at,
  };
}

const publicProfileSelect = `
  id,
  slug,
  display_name,
  public_age,
  country_code,
  avatar_path,
  short_bio,
  long_bio,
  location,
  average_rating,
  review_count,
  total_jobs_worked,
  is_available,
  created_at,
  staff_profile_photos(id, public_path, sort_order),
  staff_profile_roles(role:staff_roles(id, label)),
  staff_profile_languages(language:languages(code, label)),
  staff_reviews(id, rating, comment, reviewer_name, created_at)
`;

async function listStaff(url: URL, origin: string | null): Promise<Response> {
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit")) || 24, 1), 50);
  const offset = Math.max(Number(url.searchParams.get("offset")) || 0, 0);
  const search = url.searchParams.get("query")?.trim();
  const location = url.searchParams.get("location")?.trim();
  const role = url.searchParams.get("role")?.trim();
  const available = url.searchParams.get("available");
  const sort = url.searchParams.get("sort") ?? "recommended";

  let profileIds: string[] | null = null;
  if (role) {
    const { data: roleMatches, error: roleError } = await supabase
      .from("staff_profile_roles")
      .select("profile_id")
      .eq("role_id", role);
    if (roleError) return json({ error: "Unable to filter staff." }, 500, origin);
    profileIds = roleMatches.map((match) => match.profile_id);
    if (!profileIds.length) return json({ data: [], meta: { total: 0, limit, offset } }, 200, origin);
  }

  let query = supabase
    .from("staff_profiles")
    .select(publicProfileSelect, { count: "exact" })
    .eq("status", "published")
    .range(offset, offset + limit - 1);

  if (search) query = query.ilike("display_name", `%${search}%`);
  if (location) query = query.ilike("location", location);
  if (available === "true") query = query.eq("is_available", true);
  if (profileIds) query = query.in("id", profileIds);

  if (sort === "rating") query = query.order("average_rating", { ascending: false });
  else if (sort === "most-booked") query = query.order("total_jobs_worked", { ascending: false });
  else if (sort === "newest") query = query.order("created_at", { ascending: false });
  else {
    query = query
      .order("is_available", { ascending: false })
      .order("average_rating", { ascending: false })
      .order("total_jobs_worked", { ascending: false });
  }

  const { data, error, count } = await query;
  if (error) return json({ error: "Unable to load staff." }, 500, origin);

  return json(
    {
      data: (data ?? []).map((profile) => toPublicProfile(profile)),
      meta: { total: count ?? 0, limit, offset },
    },
    200,
    origin,
  );
}

async function getStaff(slug: string, origin: string | null): Promise<Response> {
  const { data, error } = await supabase
    .from("staff_profiles")
    .select(publicProfileSelect)
    .eq("status", "published")
    .eq("slug", slug)
    .maybeSingle();

  if (error) return json({ error: "Unable to load this profile." }, 500, origin);
  if (!data) return json({ error: "Profile not found." }, 404, origin);
  return json(toPublicProfile(data), 200, origin);
}

Deno.serve(async (request) => {
  const origin = request.headers.get("Origin");
  if (origin && !allowedOrigins.has(origin)) {
    return json({ error: "Origin not allowed." }, 403, origin);
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: responseHeaders(origin) });
  }
  if (request.method !== "GET") {
    return json({ error: "Method not allowed." }, 405, origin);
  }
  if (!supabaseUrl || !supabaseAnonKey) {
    return json({ error: "Backend environment is not configured." }, 500, origin);
  }

  const url = new URL(request.url);
  const marker = "/staff/";
  const markerIndex = url.pathname.indexOf(marker);
  const slug = markerIndex >= 0 ? decodeURIComponent(url.pathname.slice(markerIndex + marker.length)) : "";

  return slug ? getStaff(slug, origin) : listStaff(url, origin);
});
