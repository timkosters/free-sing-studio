-- What the routine needs to know about one particular voice.
--
-- The app ships generic on purpose: nobody's break sits in the same place, and
-- naming one singer's notes or repertoire in the code is wrong for everyone
-- else. Anything personal lives here, in that singer's own row, and reaches the
-- app only when they are signed in.

create table if not exists public.singer_profile (
  user_id uuid primary key references auth.users (id) on delete cascade,
  -- Comfortable range, as MIDI note numbers. A2 is 45, C4 is 60.
  low_note smallint check (low_note between 24 and 96),
  high_note smallint check (high_note between 24 and 96),
  -- Where chest voice starts handing over to head voice: the passaggio.
  break_low smallint check (break_low between 24 and 96),
  break_high smallint check (break_high between 24 and 96),
  -- What they are working on, and the one phrase they loop.
  songs text[] not null default '{}',
  hard_line text,
  updated_at timestamptz not null default now(),
  constraint singer_profile_range_ordered
    check (low_note is null or high_note is null or low_note <= high_note),
  constraint singer_profile_break_ordered
    check (break_low is null or break_high is null or break_low <= break_high),
  constraint singer_profile_songs_sane
    check (array_length(songs, 1) is null or array_length(songs, 1) <= 12),
  constraint singer_profile_hard_line_sane
    check (hard_line is null or char_length(hard_line) <= 200)
);

alter table public.singer_profile enable row level security;

-- A singer can read and write their own profile, and nothing else.
drop policy if exists "singer_profile_select_own" on public.singer_profile;
create policy "singer_profile_select_own" on public.singer_profile
  for select using (auth.uid() = user_id);

drop policy if exists "singer_profile_insert_own" on public.singer_profile;
create policy "singer_profile_insert_own" on public.singer_profile
  for insert with check (auth.uid() = user_id);

drop policy if exists "singer_profile_update_own" on public.singer_profile;
create policy "singer_profile_update_own" on public.singer_profile
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "singer_profile_delete_own" on public.singer_profile;
create policy "singer_profile_delete_own" on public.singer_profile
  for delete using (auth.uid() = user_id);
