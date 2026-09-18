begin;
set local statement_timeout = '20s';
do $qa$
declare
  owner_a uuid := gen_random_uuid();
  owner_b uuid := gen_random_uuid();
  entry_id text := 'neura-deployment-qa-' || gen_random_uuid()::text;
  original jsonb;
  candidate jsonb;
  row_value public.journal_entries%rowtype;
  first_revision timestamptz;
  saved_revision timestamptz;
  denied boolean;
begin
  insert into auth.users (id) values (owner_a), (owner_b);
  original := jsonb_build_object('id',entry_id,'user_id',owner_b,'timestamp',now()-interval '2 days','updated_at',now()-interval '2 days','content','synthetic deployment QA original','moodTag','','isVoice',false);
  perform set_config('request.jwt.claim.sub',owner_a::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_a,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  select * into strict row_value from public.neura_sync_journal_revision(original,null);
  if row_value.user_id <> owner_a or row_value.content <> original->>'content' then raise exception 'QA insert or ownership failed'; end if;
  first_revision := row_value.updated_at;
  candidate := original || jsonb_build_object('updated_at',now()-interval '1 day','content','synthetic deployment QA newer');
  select * into strict row_value from public.neura_sync_journal_revision(candidate,first_revision);
  if row_value.content <> candidate->>'content' or row_value.updated_at <= first_revision then raise exception 'QA update or server timestamp failed'; end if;
  saved_revision := row_value.updated_at;
  select * into strict row_value from public.neura_sync_journal_revision(original || jsonb_build_object('content','stale'),first_revision);
  if row_value.content <> candidate->>'content' or row_value.updated_at <> saved_revision then raise exception 'QA stale overwrite guard failed'; end if;
  select * into strict row_value from public.neura_sync_journal_revision(original,null);
  if row_value.content <> candidate->>'content' then raise exception 'QA insert conflict guard failed'; end if;
  select * into strict row_value from public.neura_sync_journal_revision(candidate || jsonb_build_object('updated_at',now()+interval '1 minute'),saved_revision);
  if row_value.updated_at <> saved_revision then raise exception 'QA idempotence failed'; end if;
  denied := false;
  begin
    update public.journal_entries set user_id=owner_b where id=entry_id;
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'QA ownership transfer was allowed'; end if;
  perform set_config('request.jwt.claim.sub',owner_b::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_b,'role','authenticated')::text,true);
  if exists(select 1 from public.journal_entries where id=entry_id) then raise exception 'QA cross-user read allowed'; end if;
  denied := false;
  begin
    perform public.neura_sync_journal_revision(candidate,saved_revision);
  exception when raise_exception then
    if sqlerrm = 'Journal revision is unavailable' then denied := true; else raise; end if;
  end;
  if not denied then raise exception 'QA cross-user RPC allowed'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  denied := false;
  begin
    perform public.neura_sync_journal_revision(original,null);
  exception when raise_exception then
    if sqlerrm = 'Authentication required' then denied := true; else raise; end if;
  end;
  if not denied then raise exception 'QA missing identity allowed'; end if;
  execute 'set local role anon';
  denied := false;
  begin
    perform public.neura_sync_journal_revision(original,null);
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'QA anonymous RPC allowed'; end if;
  denied := false;
  begin
    perform 1 from public.journal_entries limit 1;
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'QA anonymous table access allowed'; end if;
end;
$qa$;
rollback;
select 'PASS: insert, server timestamp, stale revision and insert conflict guards, idempotence, owner binding, ownership transfer denial, cross-user isolation, missing identity denial, anonymous denial; all synthetic data rolled back' as deployment_qa;
