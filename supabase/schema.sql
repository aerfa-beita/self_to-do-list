-- Run once in the Supabase SQL editor.
create table if not exists public.app_records (
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type text not null,
  entity_id text not null,
  operation text not null check (operation in ('upsert', 'delete')),
  payload jsonb not null default '{}'::jsonb,
  revision integer not null default 1,
  updated_at timestamptz not null default now(),
  primary key (user_id, entity_type, entity_id)
);

create index if not exists app_records_user_updated_idx
  on public.app_records (user_id, updated_at);

alter table public.app_records enable row level security;

drop policy if exists "read own app records" on public.app_records;
create policy "read own app records"
  on public.app_records for select
  using (auth.uid() = user_id);

drop policy if exists "insert own app records" on public.app_records;
create policy "insert own app records"
  on public.app_records for insert
  with check (auth.uid() = user_id);

drop policy if exists "update own app records" on public.app_records;
create policy "update own app records"
  on public.app_records for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

grant select, insert, update on public.app_records to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'app_records'
  ) then
    alter publication supabase_realtime add table public.app_records;
  end if;
end
$$;
