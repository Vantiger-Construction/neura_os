-- Neura cloud journal schema.
-- Local journaling remains the source of truth; cloud sync is optional and
-- unavailable in Safe Mode.

create table if not exists public.journal_entries (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  "timestamp" timestamptz not null,
  content text not null,
  "moodTag" text not null default '',
  "isVoice" boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists journal_entries_user_timestamp_idx
  on public.journal_entries (user_id, "timestamp" desc);

alter table public.journal_entries enable row level security;

drop policy if exists "journal_entries_select_own" on public.journal_entries;
create policy "journal_entries_select_own"
  on public.journal_entries for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "journal_entries_insert_own" on public.journal_entries;
create policy "journal_entries_insert_own"
  on public.journal_entries for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "journal_entries_update_own" on public.journal_entries;
create policy "journal_entries_update_own"
  on public.journal_entries for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "journal_entries_delete_own" on public.journal_entries;
create policy "journal_entries_delete_own"
  on public.journal_entries for delete
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.journal_entries from anon;
grant select, insert, update, delete on table public.journal_entries
  to authenticated;
