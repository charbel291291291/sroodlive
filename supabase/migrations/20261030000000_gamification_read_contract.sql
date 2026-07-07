-- Source-controlled read contract for Store, Tasks, and Backpack.
-- Mutating operations remain intentionally separate and server-authoritative.

create table if not exists public.gamification_store_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_ar text not null default '',
  description text not null default '',
  description_ar text not null default '',
  item_type text not null,
  price_coins bigint not null default 0 check (price_coins >= 0),
  price_diamonds bigint not null default 0 check (price_diamonds >= 0),
  rarity text not null default 'common',
  image_url text,
  icon text,
  required_vip_level integer not null default 0
    check (required_vip_level >= 0),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gamification_tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  title_ar text not null default '',
  description text not null default '',
  description_ar text not null default '',
  task_type text not null default 'daily',
  requirement_type text not null,
  requirement_count integer not null default 1
    check (requirement_count > 0),
  reward_type text not null default 'coins',
  reward_amount bigint not null default 0 check (reward_amount >= 0),
  reset_period text not null default 'daily'
    check (reset_period in ('once', 'daily', 'weekly')),
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.gamification_task_progress (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_id uuid not null
    references public.gamification_tasks(id) on delete cascade,
  period_started_at timestamptz not null,
  progress integer not null default 0 check (progress >= 0),
  completed_at timestamptz,
  claimed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, task_id, period_started_at)
);

create table if not exists public.gamification_backpack_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null
    references public.gamification_store_items(id) on delete cascade,
  equipped boolean not null default false,
  acquired_at timestamptz not null default now(),
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb
    check (jsonb_typeof(metadata) = 'object'),
  unique (user_id, item_id)
);

create index if not exists gamification_store_items_active_sort_idx
  on public.gamification_store_items (is_active, sort_order, id);

create index if not exists gamification_store_items_type_active_idx
  on public.gamification_store_items (item_type, is_active);

create index if not exists gamification_tasks_active_sort_idx
  on public.gamification_tasks (is_active, sort_order, id);

create index if not exists gamification_tasks_type_active_idx
  on public.gamification_tasks (task_type, is_active);

create index if not exists gamification_task_progress_user_task_idx
  on public.gamification_task_progress
  (user_id, task_id, period_started_at desc);

create index if not exists gamification_task_progress_user_status_idx
  on public.gamification_task_progress
  (user_id, completed_at, claimed_at);

create index if not exists gamification_backpack_user_item_idx
  on public.gamification_backpack_items (user_id, item_id);

create index if not exists gamification_backpack_user_equipped_idx
  on public.gamification_backpack_items (user_id, equipped)
  where equipped;

create index if not exists gamification_backpack_expiry_idx
  on public.gamification_backpack_items (expires_at)
  where expires_at is not null;

alter table public.gamification_store_items enable row level security;
alter table public.gamification_tasks enable row level security;
alter table public.gamification_task_progress enable row level security;
alter table public.gamification_backpack_items enable row level security;

drop policy if exists "Authenticated users read active store items"
  on public.gamification_store_items;
create policy "Authenticated users read active store items"
  on public.gamification_store_items
  for select
  to authenticated
  using (is_active);

drop policy if exists "Authenticated users read active tasks"
  on public.gamification_tasks;
create policy "Authenticated users read active tasks"
  on public.gamification_tasks
  for select
  to authenticated
  using (is_active);

drop policy if exists "Users read own gamification task progress"
  on public.gamification_task_progress;
create policy "Users read own gamification task progress"
  on public.gamification_task_progress
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users read own gamification backpack"
  on public.gamification_backpack_items;
create policy "Users read own gamification backpack"
  on public.gamification_backpack_items
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.gamification_store_items from anon, authenticated;
revoke all on table public.gamification_tasks from anon, authenticated;
revoke all on table public.gamification_task_progress from anon, authenticated;
revoke all on table public.gamification_backpack_items from anon, authenticated;

grant select on table public.gamification_store_items to authenticated;
grant select on table public.gamification_tasks to authenticated;
grant select on table public.gamification_task_progress to authenticated;
grant select on table public.gamification_backpack_items to authenticated;

create or replace function public.get_store_items()
returns table (
  id uuid,
  name text,
  name_ar text,
  description text,
  description_ar text,
  item_type text,
  price_coins bigint,
  price_diamonds bigint,
  rarity text,
  image_url text,
  icon text,
  required_vip_level integer,
  metadata jsonb,
  is_active boolean,
  sort_order integer,
  owned boolean
)
language sql
stable
security invoker
set search_path = public
as $function$
  select
    i.id,
    i.name,
    i.name_ar,
    i.description,
    i.description_ar,
    i.item_type,
    i.price_coins,
    i.price_diamonds,
    i.rarity,
    i.image_url,
    i.icon,
    i.required_vip_level,
    coalesce(i.metadata, '{}'::jsonb)
      || jsonb_strip_nulls(
        jsonb_build_object(
          'rarity', i.rarity,
          'image_url', i.image_url,
          'icon', i.icon,
          'vip_level', i.required_vip_level
        )
      ) as metadata,
    i.is_active,
    i.sort_order,
    exists (
      select 1
      from public.gamification_backpack_items b
      where b.user_id = (select auth.uid())
        and b.item_id = i.id
        and (b.expires_at is null or b.expires_at > now())
    ) as owned
  from public.gamification_store_items i
  where (select auth.uid()) is not null
    and i.is_active
  order by i.sort_order, i.id;
$function$;

comment on function public.get_store_items() is
  'Returns active gamification catalog items and ownership for the authenticated user.';

create or replace function public.get_my_tasks()
returns table (
  id uuid,
  title text,
  title_ar text,
  description text,
  description_ar text,
  task_type text,
  requirement_type text,
  requirement_count integer,
  reward_type text,
  reward_amount bigint,
  reset_period text,
  metadata jsonb,
  sort_order integer,
  progress integer,
  completed boolean,
  claimed boolean,
  completed_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $function$
  select
    t.id,
    t.title,
    t.title_ar,
    t.description,
    t.description_ar,
    t.task_type,
    t.requirement_type,
    t.requirement_count,
    t.reward_type,
    t.reward_amount,
    t.reset_period,
    t.metadata,
    t.sort_order,
    coalesce(p.progress, 0) as progress,
    (
      p.completed_at is not null
      or coalesce(p.progress, 0) >= t.requirement_count
    ) as completed,
    p.claimed_at is not null as claimed,
    p.completed_at
  from public.gamification_tasks t
  left join public.gamification_task_progress p
    on p.user_id = (select auth.uid())
   and p.task_id = t.id
   and p.period_started_at = case t.reset_period
     when 'daily' then date_trunc('day', now())
     when 'weekly' then date_trunc('week', now())
     else '1970-01-01 00:00:00+00'::timestamptz
   end
  where (select auth.uid()) is not null
    and t.is_active
  order by t.sort_order, t.id;
$function$;

comment on function public.get_my_tasks() is
  'Returns active tasks with progress only for the authenticated user and current reset period.';

create or replace function public.get_my_backpack()
returns table (
  id uuid,
  item_id uuid,
  item_type text,
  equipped boolean,
  acquired_at timestamptz,
  expires_at timestamptz,
  expired boolean,
  metadata jsonb,
  item jsonb
)
language sql
stable
security invoker
set search_path = public
as $function$
  select
    b.id,
    b.item_id,
    i.item_type,
    b.equipped,
    b.acquired_at,
    b.expires_at,
    b.expires_at is not null and b.expires_at <= now() as expired,
    b.metadata,
    jsonb_build_object(
      'id', i.id,
      'name', i.name,
      'name_ar', i.name_ar,
      'description', i.description,
      'description_ar', i.description_ar,
      'item_type', i.item_type,
      'price_coins', i.price_coins,
      'price_diamonds', i.price_diamonds,
      'rarity', i.rarity,
      'image_url', i.image_url,
      'icon', i.icon,
      'required_vip_level', i.required_vip_level,
      'metadata', coalesce(i.metadata, '{}'::jsonb)
        || jsonb_strip_nulls(
          jsonb_build_object(
            'rarity', i.rarity,
            'image_url', i.image_url,
            'icon', i.icon,
            'vip_level', i.required_vip_level
          )
        ),
      'is_active', i.is_active,
      'sort_order', i.sort_order,
      'owned', true
    ) as item
  from public.gamification_backpack_items b
  join public.gamification_store_items i on i.id = b.item_id
  where b.user_id = (select auth.uid())
    and (select auth.uid()) is not null
  order by b.equipped desc, b.acquired_at desc, b.id;
$function$;

comment on function public.get_my_backpack() is
  'Returns only the authenticated user backpack with nested catalog item data and expiry state.';

revoke execute on function public.get_store_items() from public, anon;
revoke execute on function public.get_my_tasks() from public, anon;
revoke execute on function public.get_my_backpack() from public, anon;

grant execute on function public.get_store_items() to authenticated;
grant execute on function public.get_my_tasks() to authenticated;
grant execute on function public.get_my_backpack() to authenticated;
