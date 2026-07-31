-- =====================================================================
-- Project Tracker — approval workflow upgrade
-- Adds the Assistant Engineer role + a task workflow:
--   worker (technician/AE) does work + proof  ->  Assistant Engineer verifies
--   ->  Manager confirms & closes. Reject sends it back to the worker with a reason.
-- Run ONCE in Supabase -> SQL Editor. Safe to re-run.
-- =====================================================================

-- 1) Add the assistant_engineer role
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check (role in ('manager','assistant_engineer','technician','unassigned'));

-- 2) Task workflow columns
alter table public.tasks add column if not exists stage text not null default 'open';   -- open | pending_verify | pending_confirm | closed
alter table public.tasks add column if not exists verifier uuid references public.profiles on delete set null;  -- Assistant Engineer chosen by the manager to verify
alter table public.tasks add column if not exists reject_reason text default '';
alter table public.tasks add column if not exists submitted_at timestamptz;
alter table public.tasks add column if not exists verified_at timestamptz;
alter table public.tasks add column if not exists confirmed_at timestamptz;
create index if not exists tasks_verifier_idx on public.tasks(verifier);
create index if not exists tasks_stage_idx on public.tasks(stage);

-- 3) RLS: worker (assignee), the chosen verifier, or a manager may update the row.
--    (Column-level workflow rules are enforced in the app UI.)
drop policy if exists "tasks update manager or assignee" on public.tasks;
drop policy if exists "tasks update worker verifier manager" on public.tasks;
create policy "tasks update worker verifier manager" on public.tasks for update to authenticated
  using (public.is_manager() or assignee = auth.uid() or verifier = auth.uid())
  with check (public.is_manager() or assignee = auth.uid() or verifier = auth.uid());
