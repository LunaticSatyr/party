# Staff Platform

## Architecture

The public website remains a static Astro build. This keeps GitHub Pages deployment working and avoids running a server for content that does not need one.

Mutable staff data lives in Supabase:

- Supabase Auth owns staff and administrator identities.
- Postgres owns profiles, roles, languages, private details, reviews, and moderation state.
- Supabase Storage separates private submissions from approved public photos.
- Row Level Security (RLS) protects private records and only exposes published profiles.
- The `staff` Edge Function is the public read API used by a browser or another frontend.
- Astro accesses staff through `StaffRepository`, so fixture data can be replaced without coupling pages to Supabase queries.

Astro content collections are not the primary database for this feature. They are well suited to version-controlled, build-time content, but self-service profiles need authentication, concurrent edits, moderation, private fields, and runtime updates.

## Implemented

- `/staff` directory with search, location, role, availability, sorting, grid/list views, URL state, and incremental loading
- Static `/staff/[slug]` profile routes generated from validated fixture data
- Shared TypeScript domain types, Zod validation, and a repository interface
- Postgres schema and reference data in `supabase/migrations/202608230001_staff_platform.sql`
- RLS ownership/publication policies and restricted column grants
- Moderation states for profiles, photos, and reviews
- Private submission and public photo Storage buckets with access policies
- Public list/detail Edge Function in `supabase/functions/staff/index.ts`
- A pinned Supabase CLI and pnpm backend scripts

## Local Backend

Prerequisite: Docker Desktop, or another Docker-compatible container runtime, must be running.

Start Supabase and apply the migration:

```bash
pnpm backend:start
pnpm backend:reset
```

Serve the public function in a second terminal:

```bash
pnpm backend:functions
```

The local endpoint is normally:

```text
http://127.0.0.1:54321/functions/v1/staff
```

Useful checks:

```bash
pnpm backend:lint
curl "http://127.0.0.1:54321/functions/v1/staff?limit=24&location=Sydney&role=party-host"
curl "http://127.0.0.1:54321/functions/v1/staff/avery-brooks"
```

Stop the containers when finished:

```bash
pnpm backend:stop
```

The current fixture-backed Astro site does not need an `.env` file. Supabase CLI supplies `SUPABASE_URL` and `SUPABASE_ANON_KEY` to the local Edge Function. The function defaults to allowing browser requests from `http://localhost:2608`.

## Remote Setup

These steps require access to your Supabase account and therefore cannot be completed from the repository alone.

1. Create a Supabase project and note its project reference.
2. Authenticate and link this repository:

```bash
pnpm exec supabase login
pnpm exec supabase link --project-ref YOUR_PROJECT_REF
```

3. Review and apply the database migration:

```bash
pnpm exec supabase db push --dry-run
pnpm exec supabase db push
```

4. Configure every browser origin that may call the public API. An origin contains the scheme and host, not a path, so GitHub Pages uses `https://lunaticsatyr.github.io`, not `/party`.

```bash
pnpm exec supabase secrets set STAFF_API_ALLOWED_ORIGINS="http://localhost:2608,https://lunaticsatyr.github.io,https://your-future-domain.example"
```

5. Deploy the public function. JWT verification is disabled for this read-only endpoint in `supabase/config.toml`; database RLS still limits it to published data.

```bash
pnpm exec supabase functions deploy staff
```

6. Test the deployed endpoint:

```text
https://YOUR_PROJECT_REF.supabase.co/functions/v1/staff?limit=24
https://YOUR_PROJECT_REF.supabase.co/functions/v1/staff/PROFILE_SLUG
```

Do not place the service-role key in Astro client code, a `PUBLIC_*` variable, or GitHub Pages settings. It bypasses RLS and belongs only in trusted backend/admin code.

## Data Flow

1. A staff member signs up with Supabase Auth.
2. The authenticated user creates and edits their own draft profile through the Supabase client under RLS.
3. Private contact details stay in `staff_private_details`; they are never returned by the public function.
4. The user uploads photos under their user ID in the private submissions bucket.
5. Trusted moderation code reviews the profile and media, copies approved media into the public bucket, and publishes the profile.
6. Public visitors only receive published profiles, approved media, and published reviews.
7. Editing published profile content, roles, or languages returns the profile to `pending_review`.

Administrator actions must run through a protected admin application or server-side function using the service role. Setting `app_metadata.role` to `admin` must also be performed from trusted code, never by the browser.

## Development Order

1. Complete the current public directory slice and replace fixture imagery/content.
2. Create and link the Supabase project, run the migration, and deploy the read function.
3. Add a browser-side API repository and switch `/staff` from fixtures to the deployed endpoint.
4. Build staff sign-up, sign-in, draft editing, and private photo upload.
5. Build the protected moderation queue and publishing workflow.
6. Add booking enquiries, availability scheduling, and transactional email/WhatsApp notifications.
7. Add automated tests, rate limiting, audit logs, backups, and monitoring before accepting real personal data.

The migration intentionally models bookings as a later feature. Profiles, identity, moderation, and media ownership need to be stable before booking and payment tables are introduced.

## References

- [Astro content collections](https://docs.astro.build/en/guides/content-collections/)
- [Astro on-demand rendering](https://docs.astro.build/en/guides/on-demand-rendering/)
- [Supabase local development](https://supabase.com/docs/guides/local-development/cli/getting-started)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Supabase Storage access control](https://supabase.com/docs/guides/storage/security/access-control)
