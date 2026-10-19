-- =====================================================================
-- Tech Labs: database schema and Row Level Security (RLS)
-- Run this ONCE in Supabase > SQL Editor, BEFORE uploading the new site.
-- It is safe to run again later.
--
-- WARNING: section 3 deletes every existing policy on the three tables
-- below and replaces them with the strict ones in this file. That is
-- intentional: an old, looser policy would otherwise keep working
-- alongside the new ones (Postgres combines policies with OR).
-- =====================================================================

-- 1. Admin helper ------------------------------------------------------
-- Admin = a user whose app_metadata.role is 'admin'. Users cannot edit
-- app_metadata, so this cannot be faked from the browser.
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
$$;

-- 2. Tables (created only if missing; existing data is kept) -----------
create table if not exists public.messages (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  name text,
  email text,
  service text,
  message text,
  created_at timestamptz default now()
);

create table if not exists public.client_projects (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  project_title text not null,
  service_type text,
  budget_ghc numeric,
  status text not null default 'Received',
  created_at timestamptz default now()
);

create table if not exists public.project_comments (
  id bigint generated always as identity primary key,
  project_id bigint not null references public.client_projects(id) on delete cascade,
  user_id uuid references auth.users(id) on delete set null,
  sender_name text,
  message text not null,
  created_at timestamptz default now()
);

-- columns the new site uses
alter table public.client_projects add column if not exists client_name text;
alter table public.client_projects add column if not exists client_email text;
alter table public.client_projects alter column status set default 'Received';
alter table public.client_projects alter column user_id set default auth.uid();
alter table public.project_comments alter column user_id set default auth.uid();

-- 3. Remove every old policy on these tables ---------------------------
do $$
declare r record;
begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public'
      and tablename in ('messages', 'client_projects', 'project_comments')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

alter table public.messages         enable row level security;
alter table public.client_projects  enable row level security;
alter table public.project_comments enable row level security;

-- Anonymous visitors may only send contact messages, nothing else.
revoke all on public.client_projects  from anon;
revoke all on public.project_comments from anon;
revoke all on public.messages         from anon;
grant insert on public.messages to anon;

-- 4. Triggers: the database, not the browser, decides who wrote what ---
create or replace function public.tl_before_project_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  u_email text;
  u_name  text;
begin
  new.user_id := coalesce(auth.uid(), new.user_id);
  select email, coalesce(raw_user_meta_data ->> 'full_name', split_part(email, '@', 1))
    into u_email, u_name
    from auth.users where id = new.user_id;
  new.client_email := u_email;
  new.client_name  := u_name;
  new.status       := 'Received';
  return new;
end $$;

drop trigger if exists tl_before_project_insert on public.client_projects;
create trigger tl_before_project_insert
  before insert on public.client_projects
  for each row execute function public.tl_before_project_insert();

create or replace function public.tl_before_comment_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  u_name text;
begin
  new.user_id := coalesce(auth.uid(), new.user_id);
  if public.is_admin() then
    new.sender_name := 'Tech Labs Admin';
  else
    select coalesce(raw_user_meta_data ->> 'full_name', split_part(email, '@', 1))
      into u_name from auth.users where id = new.user_id;
    new.sender_name := coalesce(u_name, 'Client');
  end if;
  return new;
end $$;

drop trigger if exists tl_before_comment_insert on public.project_comments;
create trigger tl_before_comment_insert
  before insert on public.project_comments
  for each row execute function public.tl_before_comment_insert();

-- 5. Policies -----------------------------------------------------------

-- messages: anyone can send (with sane limits); people read their own; admin reads/deletes all
create policy messages_insert on public.messages
  for insert to anon, authenticated
  with check (
    (user_id is null or user_id = auth.uid())
    and char_length(coalesce(name, ''))    between 1 and 100
    and char_length(coalesce(email, ''))   between 3 and 200
    and char_length(coalesce(message, '')) between 1 and 5000
  );
create policy messages_select on public.messages
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy messages_delete on public.messages
  for delete to authenticated
  using (public.is_admin());

-- client_projects: clients create and read their own; only admin changes status or deletes
create policy projects_select on public.client_projects
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
create policy projects_insert on public.client_projects
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and status = 'Received'
    and char_length(project_title) between 1 and 150
  );
create policy projects_update on public.client_projects
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy projects_delete on public.client_projects
  for delete to authenticated
  using (public.is_admin());

-- project_comments: only the project's owner and the admin can read or write
create policy comments_select on public.project_comments
  for select to authenticated
  using (
    public.is_admin()
    or exists (select 1 from public.client_projects p
               where p.id = project_id and p.user_id = auth.uid())
  );
create policy comments_insert on public.project_comments
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and char_length(message) between 1 and 2000
    and (
      public.is_admin()
      or exists (select 1 from public.client_projects p
                 where p.id = project_id and p.user_id = auth.uid())
    )
  );
create policy comments_delete on public.project_comments
  for delete to authenticated
  using (public.is_admin());

-- 6. Live updates for the admin portal ----------------------------------
do $$
begin
  begin alter publication supabase_realtime add table public.messages;         exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.client_projects;  exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.project_comments; exception when duplicate_object then null; end;
end $$;

-- 7. Fill in client names/emails on projects created before this update -
update public.client_projects p
   set client_email = u.email,
       client_name  = coalesce(u.raw_user_meta_data ->> 'full_name', split_part(u.email, '@', 1))
  from auth.users u
 where u.id = p.user_id
   and p.client_email is null;

-- 8. MAKE YOURSELF ADMIN ------------------------------------------------
-- Run this once. Then LOG OUT and LOG IN again on the site so your login
-- token picks up the new role. Without this step the Admin link will not
-- appear and the admin portal will show nothing.
update auth.users
   set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
 where email = 'fawaazmahama@gmail.com';
