-- =====================================================================
-- Project Tracker — multi-user roles upgrade (managers + technicians)
-- Run ONCE in Supabase → SQL Editor. Safe to re-run.
-- Replaces the single-blob (user_state) model with shared projects/tasks.
-- =====================================================================

-- ---------- Profiles + roles ----------
create table if not exists public.profiles (
  id         uuid primary key references auth.users on delete cascade,
  email      text,
  name       text,
  role       text not null default 'unassigned' check (role in ('manager','technician','unassigned')),
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Manager check — SECURITY DEFINER (owned by postgres) bypasses RLS, so no policy recursion.
create or replace function public.is_manager()
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'manager');
$$;

-- Auto-create a profile on signup; the very first user becomes the manager.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare mgr_count int;
begin
  select count(*) into mgr_count from public.profiles where role = 'manager';
  insert into public.profiles (id, email, name, role)
  values (new.id, new.email, split_part(new.email, '@', 1),
          case when mgr_count = 0 then 'manager' else 'unassigned' end);
  return new;
end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Only a manager may change anyone's role (blocks self-promotion).
create or replace function public.guard_profile_role()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role is distinct from old.role and not public.is_manager() then
    raise exception 'Only a manager can change roles';
  end if;
  return new;
end; $$;
drop trigger if exists guard_role on public.profiles;
create trigger guard_role before update on public.profiles
  for each row execute function public.guard_profile_role();

drop policy if exists "profiles read all" on public.profiles;
create policy "profiles read all" on public.profiles for select to authenticated using (true);
drop policy if exists "profiles update self or manager" on public.profiles;
create policy "profiles update self or manager" on public.profiles for update to authenticated
  using (auth.uid() = id or public.is_manager()) with check (auth.uid() = id or public.is_manager());
grant select, update on public.profiles to authenticated;

-- ---------- Projects ----------
create table if not exists public.projects (
  id         uuid primary key default gen_random_uuid(),
  name       text not null default 'Untitled Project',
  position   int  not null default 0,
  created_at timestamptz not null default now()
);
alter table public.projects enable row level security;
drop policy if exists "projects read all" on public.projects;
create policy "projects read all" on public.projects for select to authenticated using (true);
drop policy if exists "projects manage manager" on public.projects;
create policy "projects manage manager" on public.projects for all to authenticated
  using (public.is_manager()) with check (public.is_manager());
grant select, insert, update, delete on public.projects to authenticated;

-- ---------- Tasks ----------
create table if not exists public.tasks (
  id                uuid primary key default gen_random_uuid(),
  project_id        uuid not null references public.projects on delete cascade,
  parent_id         uuid references public.tasks on delete cascade,
  position          int  not null default 0,
  name              text not null default '',
  priority          text not null default 'Medium',
  status            text not null default 'not_started',
  percent           int  not null default 0,
  base_start date, base_end date, plan_start date, plan_end date, act_start date, act_end date,
  dependency        text default '',
  remarks           text default '',   -- manager / general remarks
  assignee          uuid references public.profiles on delete set null,
  instruction_photo text,              -- manager's reference photo (storage path)
  completion_photo  text,              -- technician's proof photo (storage path)
  tool_crib_items   text default '',   -- items taken from the tool crib for replacement
  close_date        date,              -- date the technician closed the task
  tech_remarks      text default '',   -- technician completion remarks
  in_progress_reason text default '',  -- why a task is still in progress
  updated_at        timestamptz not null default now()
);
alter table public.tasks enable row level security;
create index if not exists tasks_project_idx  on public.tasks(project_id);
create index if not exists tasks_assignee_idx on public.tasks(assignee);

drop policy if exists "tasks read all" on public.tasks;
create policy "tasks read all" on public.tasks for select to authenticated using (true);
drop policy if exists "tasks insert manager" on public.tasks;
create policy "tasks insert manager" on public.tasks for insert to authenticated with check (public.is_manager());
drop policy if exists "tasks update manager or assignee" on public.tasks;
create policy "tasks update manager or assignee" on public.tasks for update to authenticated
  using (public.is_manager() or assignee = auth.uid())
  with check (public.is_manager() or assignee = auth.uid());
drop policy if exists "tasks delete manager" on public.tasks;
create policy "tasks delete manager" on public.tasks for delete to authenticated using (public.is_manager());
grant select, insert, update, delete on public.tasks to authenticated;

-- ---------- Storage: task-photos shared across the team ----------
-- One company workspace: any signed-in user may read; UI enforces who writes what.
drop policy if exists "task-photos read own" on storage.objects;
drop policy if exists "task-photos insert own" on storage.objects;
drop policy if exists "task-photos update own" on storage.objects;
drop policy if exists "task-photos delete own" on storage.objects;
drop policy if exists "task-photos read auth" on storage.objects;
create policy "task-photos read auth" on storage.objects for select to authenticated using (bucket_id = 'task-photos');
drop policy if exists "task-photos insert auth" on storage.objects;
create policy "task-photos insert auth" on storage.objects for insert to authenticated with check (bucket_id = 'task-photos');
drop policy if exists "task-photos update auth" on storage.objects;
create policy "task-photos update auth" on storage.objects for update to authenticated using (bucket_id = 'task-photos');
drop policy if exists "task-photos delete auth" on storage.objects;
create policy "task-photos delete auth" on storage.objects for delete to authenticated using (bucket_id = 'task-photos');
