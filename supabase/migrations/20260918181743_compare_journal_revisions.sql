-- Compare-and-set journal updates. A stale device must never overwrite a
-- revision it did not read. Keep RLS and the existing server updated_at trigger.
create or replace function public.neura_sync_journal_revision(
  entry jsonb,
  expected_updated_at timestamptz default null
)
returns setof public.journal_entries
language plpgsql
security invoker
set search_path = ''
as $$
declare
  current_row public.journal_entries%rowtype;
  owner_id uuid := auth.uid();
begin
  if owner_id is null then
    raise exception 'Authentication required';
  end if;
  if expected_updated_at is null then
    insert into public.journal_entries (id, user_id, "timestamp", content, "moodTag", "isVoice", updated_at)
    values (entry->>'id', owner_id, (entry->>'timestamp')::timestamptz,
      entry->>'content', coalesce(entry->>'moodTag', ''),
      coalesce((entry->>'isVoice')::boolean, false),
      coalesce((entry->>'updated_at')::timestamptz, (entry->>'timestamp')::timestamptz))
    on conflict (id) do nothing;
  end if;

  select * into current_row from public.journal_entries
    where id = entry->>'id' and user_id = owner_id for update;
  if not found then
    raise exception 'Journal revision is unavailable';
  end if;

  if expected_updated_at is not null and
      current_row.updated_at = expected_updated_at and
      coalesce((entry->>'updated_at')::timestamptz, (entry->>'timestamp')::timestamptz) >= current_row.updated_at and
      (current_row.content, current_row."moodTag", current_row."isVoice") is distinct from
      (entry->>'content', coalesce(entry->>'moodTag', ''), coalesce((entry->>'isVoice')::boolean, false)) then
    update public.journal_entries set
      content = entry->>'content',
      "moodTag" = coalesce(entry->>'moodTag', ''),
      "isVoice" = coalesce((entry->>'isVoice')::boolean, false)
      where id = current_row.id and user_id = owner_id
      returning * into current_row;
  end if;
  return next current_row;
end;
$$;

revoke all on function public.neura_sync_journal_revision(jsonb, timestamptz) from public, anon;
grant execute on function public.neura_sync_journal_revision(jsonb, timestamptz) to authenticated;
