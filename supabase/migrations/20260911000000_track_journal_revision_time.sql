-- Keep revision time authoritative on the server for conflict-aware sync.
-- The journal event timestamp remains unchanged when an entry is edited.

create or replace function public.set_journal_entry_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists journal_entries_set_updated_at
  on public.journal_entries;

create trigger journal_entries_set_updated_at
before update on public.journal_entries
for each row
execute function public.set_journal_entry_updated_at();
