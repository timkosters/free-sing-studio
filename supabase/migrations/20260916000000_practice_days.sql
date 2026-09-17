-- Free Sing practice sync.
--
-- One row per user per calendar day. The client merges by taking the larger
-- value per field, so this table only ever needs last-write-wins upserts and
-- never has to resolve a conflict itself.
--
-- Run once in the Supabase SQL editor.

create table if not exists public.practice_days (
  user_id uuid not null references auth.users (id) on delete cascade,
  day date not null,
  seconds integer not null default 0 check (seconds >= 0),
  steps integer not null default 0 check (steps >= 0),
  completed boolean not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

alter table public.practice_days enable row level security;

-- A signed-in singer can read and write their own days, and nothing else.
-- Split per command so the policies stay readable and auditable.
drop policy if exists "practice_days_select_own" on public.practice_days;
create policy "practice_days_select_own" on public.practice_days
  for select using (auth.uid() = user_id);

drop policy if exists "practice_days_insert_own" on public.practice_days;
create policy "practice_days_insert_own" on public.practice_days
  for insert with check (auth.uid() = user_id);

drop policy if exists "practice_days_update_own" on public.practice_days;
create policy "practice_days_update_own" on public.practice_days
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "practice_days_delete_own" on public.practice_days;
create policy "practice_days_delete_own" on public.practice_days
  for delete using (auth.uid() = user_id);

create index if not exists practice_days_user_day_idx
  on public.practice_days (user_id, day desc);
