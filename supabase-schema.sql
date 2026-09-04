-- Shared 75 HARD accountability schema for Supabase.
-- Run this in the Supabase SQL editor before enabling the shared dashboard.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.challenge_settings (
  id boolean primary key default true check (id),
  challenge_name text not null default '75 HARD',
  start_date date not null default current_date,
  timezone text not null default 'UTC',
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  day_number integer not null check (day_number between 1 and 75),
  log_date date not null,
  tasks jsonb not null default '{}'::jsonb,
  notes text not null default '' check (char_length(notes) <= 10000),
  metrics jsonb not null default '{}'::jsonb,
  nutrition jsonb not null default '{}'::jsonb,
  recovery jsonb not null default '{}'::jsonb,
  deen jsonb not null default '{}'::jsonb,
  workout jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(user_id, day_number)
);

create table if not exists public.evidence_photos (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  daily_log_id uuid not null references public.daily_logs(id) on delete cascade,
  evidence_type text not null check (evidence_type in ('progress', 'workout1', 'workout2')),
  storage_path text not null,
  note text not null default '' check (char_length(note) <= 160),
  is_shared boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists evidence_one_workout_type_per_day
  on public.evidence_photos(user_id, daily_log_id, evidence_type)
  where evidence_type in ('workout1', 'workout2');

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and is_admin);
$$;

create or replace function public.log_score(log_row public.daily_logs)
returns integer
language sql
immutable
as $$
  select
    (case when coalesce((log_row.tasks->>'w1')::boolean, false) then 15 else 0 end) +
    (case when coalesce((log_row.tasks->>'w2')::boolean, false) then 15 else 0 end) +
    (case when coalesce((log_row.tasks->>'diet')::boolean, false) then 15 else 0 end) +
    (case when coalesce((log_row.tasks->>'water')::boolean, false) then 10 else 0 end) +
    (case when coalesce((log_row.tasks->>'read')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'photo')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'sleep')::boolean, false) then 10 else 0 end) +
    (case when coalesce((log_row.tasks->>'recovery')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'deen')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'mosque')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'cal')::boolean, false) then 5 else 0 end) +
    (case when coalesce((log_row.tasks->>'protein')::boolean, false) then 5 else 0 end);
$$;

create or replace view public.shared_participant_progress as
with scored as (
  select p.id, p.display_name, p.avatar_url,
    count(l.id)::integer as active_days,
    count(*) filter (where public.log_score(l) = 100)::integer as completed_days,
    coalesce(sum(public.log_score(l)), 0)::integer as total_points,
    coalesce(round(avg(public.log_score(l))), 0)::integer as average_score,
    coalesce(max(l.day_number), 0)::integer as current_day,
    count(*) filter (where l.log_date < current_date and not coalesce((l.tasks->>'w1')::boolean, false))::integer as missed_workout_1,
    count(*) filter (where l.log_date < current_date and not coalesce((l.tasks->>'w2')::boolean, false))::integer as missed_workout_2
  from public.profiles p
  left join public.daily_logs l on l.user_id = p.id
  group by p.id, p.display_name, p.avatar_url
)
select *,
  round(completed_days::numeric / 75 * 100, 1) as completion_percent,
  case when active_days = 0 then 0 else current_day end as challenge_day,
  greatest(0, 100 - coalesce((select public.log_score(l2) from public.daily_logs l2 where l2.user_id = scored.id order by l2.day_number desc limit 1), 0)) as points_to_finish_today
from scored;

create or replace view public.shared_daily_activity as
select
  l.user_id,
  l.day_number,
  l.log_date,
  public.log_score(l) as score,
  coalesce((l.tasks->>'w1')::boolean, false) as workout_1_complete,
  coalesce((l.tasks->>'w2')::boolean, false) as workout_2_complete,
  l.updated_at
from public.daily_logs l;

alter table public.profiles enable row level security;
alter table public.challenge_settings enable row level security;
alter table public.daily_logs enable row level security;
alter table public.evidence_photos enable row level security;


drop policy if exists profiles_shared_read on public.profiles;
create policy profiles_shared_read on public.profiles for select to authenticated using (true);
drop policy if exists profiles_self_insert on public.profiles;
create policy profiles_self_insert on public.profiles for insert to authenticated with check (id = auth.uid() and is_admin = false);
drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles for update to authenticated using (id = auth.uid() or public.current_user_is_admin()) with check (public.current_user_is_admin() or (id = auth.uid() and is_admin = false));

drop policy if exists settings_authenticated_read on public.challenge_settings;
create policy settings_authenticated_read on public.challenge_settings for select to authenticated using (true);
drop policy if exists settings_admin_write on public.challenge_settings;
create policy settings_admin_write on public.challenge_settings for all to authenticated using (public.current_user_is_admin()) with check (public.current_user_is_admin());

drop policy if exists logs_shared_read on public.daily_logs;
create policy logs_shared_read on public.daily_logs for select to authenticated using (user_id = auth.uid() or public.current_user_is_admin());
drop policy if exists logs_owner_insert on public.daily_logs;
create policy logs_owner_insert on public.daily_logs for insert to authenticated with check (user_id = auth.uid());
drop policy if exists logs_owner_update on public.daily_logs;
create policy logs_owner_update on public.daily_logs for update to authenticated using (user_id = auth.uid() or public.current_user_is_admin()) with check (user_id = auth.uid() or public.current_user_is_admin());
drop policy if exists logs_owner_delete on public.daily_logs;
create policy logs_owner_delete on public.daily_logs for delete to authenticated using (user_id = auth.uid() or public.current_user_is_admin());

drop policy if exists photos_shared_read on public.evidence_photos;
create policy photos_shared_read on public.evidence_photos for select to authenticated using (is_shared or user_id = auth.uid() or public.current_user_is_admin());
drop policy if exists photos_owner_insert on public.evidence_photos;
create policy photos_owner_insert on public.evidence_photos for insert to authenticated with check (user_id = auth.uid());
drop policy if exists photos_owner_update on public.evidence_photos;
create policy photos_owner_update on public.evidence_photos for update to authenticated using (user_id = auth.uid() or public.current_user_is_admin()) with check (user_id = auth.uid() or public.current_user_is_admin());
drop policy if exists photos_owner_delete on public.evidence_photos;
create policy photos_owner_delete on public.evidence_photos for delete to authenticated using (user_id = auth.uid() or public.current_user_is_admin());

do $$
begin
  alter publication supabase_realtime add table public.profiles;
  alter publication supabase_realtime add table public.daily_logs;
  alter publication supabase_realtime add table public.evidence_photos;
exception when duplicate_object then null;
end $$;

insert into public.challenge_settings(id) values (true) on conflict (id) do nothing;

insert into storage.buckets(id, name, public)
values ('evidence-photos', 'evidence-photos', false)
on conflict (id) do nothing;

drop policy if exists evidence_storage_read on storage.objects;
create policy evidence_storage_read on storage.objects for select to authenticated
using (bucket_id = 'evidence-photos' and (owner_id = auth.uid()::text or (storage.foldername(name))[1] is not null));

drop policy if exists evidence_storage_insert on storage.objects;
create policy evidence_storage_insert on storage.objects for insert to authenticated
with check (bucket_id = 'evidence-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists evidence_storage_update on storage.objects;
create policy evidence_storage_update on storage.objects for update to authenticated
using (bucket_id = 'evidence-photos' and owner_id = auth.uid()::text)
with check (bucket_id = 'evidence-photos' and owner_id = auth.uid()::text);

drop policy if exists evidence_storage_delete on storage.objects;
create policy evidence_storage_delete on storage.objects for delete to authenticated
using (bucket_id = 'evidence-photos' and (owner_id = auth.uid()::text or public.current_user_is_admin()));

revoke all on public.shared_participant_progress from anon;
grant select on public.shared_participant_progress to authenticated;
revoke all on public.shared_daily_activity from anon;
grant select on public.shared_daily_activity to authenticated;
