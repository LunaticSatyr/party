create type public.staff_profile_status as enum (
  'draft',
  'pending_review',
  'published',
  'suspended'
);

create type public.media_status as enum (
  'pending_review',
  'approved',
  'rejected'
);

create type public.review_status as enum (
  'pending_review',
  'published',
  'rejected'
);

create table public.staff_profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  display_name text not null check (char_length(display_name) between 1 and 80),
  public_age smallint check (public_age between 18 and 100),
  country_code text not null check (char_length(country_code) = 2),
  avatar_path text,
  short_bio text not null default '' check (char_length(short_bio) <= 240),
  long_bio text not null default '' check (char_length(long_bio) <= 3000),
  location text not null default '',
  average_rating numeric(2, 1) not null default 0 check (average_rating between 0 and 5),
  review_count integer not null default 0 check (review_count >= 0),
  total_jobs_worked integer not null default 0 check (total_jobs_worked >= 0),
  is_available boolean not null default false,
  status public.staff_profile_status not null default 'draft',
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_private_details (
  profile_id uuid primary key references public.staff_profiles (id) on delete cascade,
  legal_name text not null,
  date_of_birth date not null,
  phone text,
  emergency_contact_name text,
  emergency_contact_phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_roles (
  id text primary key check (id ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  label text not null unique,
  is_active boolean not null default true,
  sort_order integer not null default 0
);

create table public.staff_profile_roles (
  profile_id uuid not null references public.staff_profiles (id) on delete cascade,
  role_id text not null references public.staff_roles (id) on delete restrict,
  primary key (profile_id, role_id)
);

create table public.languages (
  code text primary key check (code ~ '^[a-z]{2,3}$'),
  label text not null unique
);

create table public.staff_profile_languages (
  profile_id uuid not null references public.staff_profiles (id) on delete cascade,
  language_code text not null references public.languages (code) on delete restrict,
  primary key (profile_id, language_code)
);

create table public.staff_profile_photos (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.staff_profiles (id) on delete cascade,
  submission_path text not null,
  public_path text,
  sort_order integer not null default 0 check (sort_order >= 0),
  status public.media_status not null default 'pending_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.staff_reviews (
  id uuid primary key default gen_random_uuid(),
  staff_profile_id uuid not null references public.staff_profiles (id) on delete cascade,
  reviewer_user_id uuid references auth.users (id) on delete set null,
  reviewer_name text not null check (char_length(reviewer_name) between 1 and 80),
  rating smallint not null check (rating between 1 and 5),
  comment text not null check (char_length(comment) between 1 and 1500),
  status public.review_status not null default 'pending_review',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index staff_profiles_public_listing_idx
  on public.staff_profiles (status, is_available, location, average_rating desc);
create index staff_profiles_name_search_idx
  on public.staff_profiles using gin (to_tsvector('simple', display_name || ' ' || short_bio));
create index staff_profile_photos_profile_idx
  on public.staff_profile_photos (profile_id, status, sort_order);
create index staff_reviews_profile_idx
  on public.staff_reviews (staff_profile_id, status, created_at desc);
create index staff_profile_roles_role_idx
  on public.staff_profile_roles (role_id, profile_id);

insert into public.staff_roles (id, label, sort_order)
values
  ('party-host', 'Party Host', 10),
  ('event-host', 'Event Host', 20),
  ('event-bartender', 'Event Bartender', 30),
  ('wait-staff', 'Wait Staff', 40),
  ('promotional-model', 'Promotional Model', 50),
  ('brand-ambassador', 'Brand Ambassador', 60),
  ('dj', 'DJ', 70),
  ('mc', 'MC', 80)
on conflict (id) do nothing;

insert into public.languages (code, label)
values
  ('en', 'English'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('hi', 'Hindi'),
  ('it', 'Italian'),
  ('ko', 'Korean')
on conflict (code) do nothing;

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_staff_profiles_updated_at
before update on public.staff_profiles
for each row execute function public.set_updated_at();

create trigger set_staff_private_details_updated_at
before update on public.staff_private_details
for each row execute function public.set_updated_at();

create trigger set_staff_profile_photos_updated_at
before update on public.staff_profile_photos
for each row execute function public.set_updated_at();

create trigger set_staff_reviews_updated_at
before update on public.staff_reviews
for each row execute function public.set_updated_at();

create function public.mark_staff_profile_for_review()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status = 'published' and (
    new.slug is distinct from old.slug or
    new.display_name is distinct from old.display_name or
    new.public_age is distinct from old.public_age or
    new.country_code is distinct from old.country_code or
    new.avatar_path is distinct from old.avatar_path or
    new.short_bio is distinct from old.short_bio or
    new.long_bio is distinct from old.long_bio or
    new.location is distinct from old.location
  ) then
    new.status = 'pending_review';
    new.published_at = null;
  end if;
  return new;
end;
$$;

create trigger mark_staff_profile_for_review
before update on public.staff_profiles
for each row execute function public.mark_staff_profile_for_review();

create function public.mark_related_staff_profile_for_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid;
begin
  target_profile_id = coalesce(new.profile_id, old.profile_id);

  update public.staff_profiles
  set status = 'pending_review', published_at = null
  where id = target_profile_id and status = 'published';

  return coalesce(new, old);
end;
$$;

create trigger mark_profile_for_review_after_role_change
after insert or delete on public.staff_profile_roles
for each row execute function public.mark_related_staff_profile_for_review();

create trigger mark_profile_for_review_after_language_change
after insert or delete on public.staff_profile_languages
for each row execute function public.mark_related_staff_profile_for_review();

create function public.refresh_staff_rating()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_profile_id uuid;
begin
  target_profile_id = coalesce(new.staff_profile_id, old.staff_profile_id);

  update public.staff_profiles
  set
    average_rating = coalesce((
      select round(avg(rating)::numeric, 1)
      from public.staff_reviews
      where staff_profile_id = target_profile_id and status = 'published'
    ), 0),
    review_count = (
      select count(*)
      from public.staff_reviews
      where staff_profile_id = target_profile_id and status = 'published'
    )
  where id = target_profile_id;

  return coalesce(new, old);
end;
$$;

create trigger refresh_staff_rating
after insert or update or delete on public.staff_reviews
for each row execute function public.refresh_staff_rating();

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

alter table public.staff_profiles enable row level security;
alter table public.staff_private_details enable row level security;
alter table public.staff_roles enable row level security;
alter table public.staff_profile_roles enable row level security;
alter table public.languages enable row level security;
alter table public.staff_profile_languages enable row level security;
alter table public.staff_profile_photos enable row level security;
alter table public.staff_reviews enable row level security;

create policy "Published staff profiles are public"
on public.staff_profiles for select
using (status = 'published');

create policy "Staff can view their own profile"
on public.staff_profiles for select to authenticated
using ((select auth.uid()) = user_id or (select public.is_admin()));

create policy "Staff can create their own profile"
on public.staff_profiles for insert to authenticated
with check ((select auth.uid()) = user_id);

create policy "Staff can update their own profile"
on public.staff_profiles for update to authenticated
using ((select auth.uid()) = user_id or (select public.is_admin()))
with check ((select auth.uid()) = user_id or (select public.is_admin()));

create policy "Staff can manage their private details"
on public.staff_private_details for all to authenticated
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and (user_id = (select auth.uid()) or (select public.is_admin()))
  )
)
with check (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and (user_id = (select auth.uid()) or (select public.is_admin()))
  )
);

create policy "Active roles are public"
on public.staff_roles for select
using (is_active or (select public.is_admin()));

create policy "Languages are public"
on public.languages for select
using (true);

create policy "Published profile roles are public"
on public.staff_profile_roles for select
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and (
      status = 'published' or user_id = (select auth.uid()) or (select public.is_admin())
    )
  )
);

create policy "Staff can add their own roles"
on public.staff_profile_roles for insert to authenticated
with check (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Staff can remove their own roles"
on public.staff_profile_roles for delete to authenticated
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Published profile languages are public"
on public.staff_profile_languages for select
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and (
      status = 'published' or user_id = (select auth.uid()) or (select public.is_admin())
    )
  )
);

create policy "Staff can add their own languages"
on public.staff_profile_languages for insert to authenticated
with check (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Staff can remove their own languages"
on public.staff_profile_languages for delete to authenticated
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Approved profile photos are public"
on public.staff_profile_photos for select
using (
  (status = 'approved' and exists (
    select 1 from public.staff_profiles
    where id = profile_id and status = 'published'
  )) or exists (
    select 1 from public.staff_profiles
    where id = profile_id and (user_id = (select auth.uid()) or (select public.is_admin()))
  )
);

create policy "Staff can add their own photos"
on public.staff_profile_photos for insert to authenticated
with check (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Staff can update their own photos"
on public.staff_profile_photos for update to authenticated
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
)
with check (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Staff can remove their own photos"
on public.staff_profile_photos for delete to authenticated
using (
  exists (
    select 1 from public.staff_profiles
    where id = profile_id and user_id = (select auth.uid())
  ) or (select public.is_admin())
);

create policy "Published reviews are public"
on public.staff_reviews for select
using (
  (status = 'published' and exists (
    select 1 from public.staff_profiles
    where id = staff_profile_id and status = 'published'
  )) or reviewer_user_id = (select auth.uid()) or (select public.is_admin())
);

create policy "Authenticated users can submit reviews"
on public.staff_reviews for insert to authenticated
with check ((select auth.uid()) = reviewer_user_id);

revoke all on table
  public.staff_profiles,
  public.staff_private_details,
  public.staff_roles,
  public.staff_profile_roles,
  public.languages,
  public.staff_profile_languages,
  public.staff_profile_photos,
  public.staff_reviews
from anon, authenticated;

grant select (
  id, slug, display_name, public_age, country_code, avatar_path, short_bio,
  long_bio, location, average_rating, review_count, total_jobs_worked,
  is_available, status, published_at, created_at, updated_at
) on public.staff_profiles to anon, authenticated;

grant insert (
  user_id, slug, display_name, public_age, country_code, avatar_path,
  short_bio, long_bio, location, is_available
) on public.staff_profiles to authenticated;

grant update (
  slug, display_name, public_age, country_code, avatar_path,
  short_bio, long_bio, location, is_available
) on public.staff_profiles to authenticated;

grant select, insert, update, delete on public.staff_private_details to authenticated;
grant select on public.staff_roles, public.languages to anon, authenticated;
grant select on public.staff_profile_roles, public.staff_profile_languages to anon, authenticated;
grant insert, delete on public.staff_profile_roles, public.staff_profile_languages to authenticated;
grant select (id, profile_id, public_path, sort_order, status, created_at)
  on public.staff_profile_photos to anon, authenticated;
grant insert (profile_id, submission_path, sort_order)
  on public.staff_profile_photos to authenticated;
grant update (submission_path, sort_order)
  on public.staff_profile_photos to authenticated;
grant delete on public.staff_profile_photos to authenticated;
grant select (id, staff_profile_id, reviewer_name, rating, comment, status, created_at)
  on public.staff_reviews to anon, authenticated;
grant insert (staff_profile_id, reviewer_user_id, reviewer_name, rating, comment)
  on public.staff_reviews to authenticated;

grant all on table
  public.staff_profiles,
  public.staff_private_details,
  public.staff_roles,
  public.staff_profile_roles,
  public.languages,
  public.staff_profile_languages,
  public.staff_profile_photos,
  public.staff_reviews
to service_role;

revoke all on function public.set_updated_at() from public, anon, authenticated;
revoke all on function public.mark_staff_profile_for_review() from public, anon, authenticated;
revoke all on function public.mark_related_staff_profile_for_review() from public, anon, authenticated;
revoke all on function public.refresh_staff_rating() from public, anon, authenticated;
revoke all on function public.is_admin() from public, anon, authenticated;
grant execute on function public.is_admin() to anon, authenticated;

insert into storage.buckets (id, name, public)
values
  ('staff-profile-submissions', 'staff-profile-submissions', false),
  ('staff-profile-public', 'staff-profile-public', true)
on conflict (id) do update set public = excluded.public;

create policy "Staff upload into their own submission folder"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'staff-profile-submissions'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

create policy "Staff read their own submitted photos"
on storage.objects for select to authenticated
using (
  bucket_id = 'staff-profile-submissions'
  and ((storage.foldername(name))[1] = (select auth.uid()::text) or (select public.is_admin()))
);

create policy "Staff update their own submitted photos"
on storage.objects for update to authenticated
using (
  bucket_id = 'staff-profile-submissions'
  and ((storage.foldername(name))[1] = (select auth.uid()::text) or (select public.is_admin()))
)
with check (
  bucket_id = 'staff-profile-submissions'
  and ((storage.foldername(name))[1] = (select auth.uid()::text) or (select public.is_admin()))
);

create policy "Staff delete their own submitted photos"
on storage.objects for delete to authenticated
using (
  bucket_id = 'staff-profile-submissions'
  and ((storage.foldername(name))[1] = (select auth.uid()::text) or (select public.is_admin()))
);

create policy "Published staff photos are public"
on storage.objects for select
using (bucket_id = 'staff-profile-public');
