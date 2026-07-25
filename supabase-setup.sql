-- =====================================================================
-- Project Tracker — one-time Supabase setup
-- Run this ONCE in your Supabase dashboard: SQL Editor → New query → paste → Run.
-- Safe to re-run (uses IF NOT EXISTS / DROP POLICY IF EXISTS).
-- No secrets here — only schema + row-level-security rules.
-- =====================================================================

-- 1) Table that stores each user's whole app state as one JSON blob ------
create table if not exists public.user_state (
  user_id    uuid primary key references auth.users on delete cascade,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.user_state enable row level security;

-- Each signed-in user can read/write ONLY their own row.
drop policy if exists "user_state select own" on public.user_state;
create policy "user_state select own" on public.user_state
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists "user_state insert own" on public.user_state;
create policy "user_state insert own" on public.user_state
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists "user_state update own" on public.user_state;
create policy "user_state update own" on public.user_state
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);

grant select, insert, update on public.user_state to authenticated;

-- 2) Private Storage bucket for task photos -----------------------------
insert into storage.buckets (id, name, public)
values ('task-photos', 'task-photos', false)
on conflict (id) do nothing;

-- Each user can read/write ONLY files inside a folder named after their uid,
-- i.e. path "<uid>/<taskId>-xxxx.jpg". (storage.foldername(name))[1] = the uid folder.
drop policy if exists "task-photos read own" on storage.objects;
create policy "task-photos read own" on storage.objects
  for select to authenticated
  using (bucket_id = 'task-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "task-photos insert own" on storage.objects;
create policy "task-photos insert own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'task-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "task-photos update own" on storage.objects;
create policy "task-photos update own" on storage.objects
  for update to authenticated
  using (bucket_id = 'task-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "task-photos delete own" on storage.objects;
create policy "task-photos delete own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'task-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 3) (Recommended) Frictionless signup:
--    Authentication → Providers → Email → turn OFF "Confirm email",
--    so you and your subordinates can sign in immediately after creating an account.
-- =====================================================================
