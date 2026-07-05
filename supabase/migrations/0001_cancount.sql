-- CanCount backend schema v1
-- Apply to a DEDICATED Supabase project (never a shared one).
--
-- Design notes:
-- * profiles carries only public-safe fields; phone hashes live in
--   contact_directory, which has NO cross-user select path — matching goes
--   through the match_contacts SECURITY DEFINER function only.
-- * can_events mirrors local CanLog rows (same UUID) so sync is idempotent.
-- * Crews are the social scope: leaderboard visibility = shared crew.
-- * Week windows are computed CLIENT-side (the user's calendar decides when
--   a week rolls over — consistent with StatsEngine.startOfWeek in-app).

-- ───────────────────────── profiles ─────────────────────────
create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null default 'Racer'
        check (char_length(display_name) between 1 and 40),
    created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by signed-in users"
    on public.profiles for select to authenticated using (true);

create policy "insert own profile"
    on public.profiles for insert to authenticated
    with check (id = (select auth.uid()));

create policy "update own profile"
    on public.profiles for update to authenticated
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

-- Auto-create a profile row on signup (display name from Apple, if present).
create function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(
            nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
            nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
            'Racer'
        )
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ─────────────────── contact directory (private) ───────────────────
-- SHA-256 hashes of E.164 phone numbers. Row-readable only by the owner;
-- cross-user lookups happen exclusively inside match_contacts().
create table public.contact_directory (
    user_id uuid primary key references public.profiles (id) on delete cascade,
    phone_hash text not null unique,
    updated_at timestamptz not null default now()
);

alter table public.contact_directory enable row level security;

create policy "own directory row: select"
    on public.contact_directory for select to authenticated
    using (user_id = (select auth.uid()));

create policy "own directory row: upsert"
    on public.contact_directory for insert to authenticated
    with check (user_id = (select auth.uid()));

create policy "own directory row: update"
    on public.contact_directory for update to authenticated
    using (user_id = (select auth.uid()))
    with check (user_id = (select auth.uid()));

create policy "own directory row: delete"
    on public.contact_directory for delete to authenticated
    using (user_id = (select auth.uid()));

-- ───────────────────────── crews ─────────────────────────
create table public.crews (
    id uuid primary key default gen_random_uuid(),
    name text not null check (char_length(name) between 1 and 40),
    invite_code text not null unique,
    created_by uuid not null references public.profiles (id) on delete cascade,
    created_at timestamptz not null default now()
);

create table public.crew_members (
    crew_id uuid not null references public.crews (id) on delete cascade,
    user_id uuid not null references public.profiles (id) on delete cascade,
    joined_at timestamptz not null default now(),
    primary key (crew_id, user_id)
);

create index crew_members_user_idx on public.crew_members (user_id);

alter table public.crews enable row level security;
alter table public.crew_members enable row level security;

-- Membership check that dodges RLS recursion between crews/crew_members.
create function public.is_crew_member(p_crew uuid)
returns boolean
language sql security definer set search_path = ''
stable
as $$
    select exists (
        select 1 from public.crew_members
        where crew_id = p_crew and user_id = (select auth.uid())
    );
$$;

create policy "crews readable by members"
    on public.crews for select to authenticated
    using (public.is_crew_member(id) or created_by = (select auth.uid()));

create policy "crew members readable by fellow members"
    on public.crew_members for select to authenticated
    using (public.is_crew_member(crew_id));

create policy "leave a crew"
    on public.crew_members for delete to authenticated
    using (user_id = (select auth.uid()));

-- creates/joins go through the RPCs below (no direct insert policies)

-- ───────────────────────── can events ─────────────────────────
create table public.can_events (
    id uuid primary key,                    -- client CanLog.id → idempotent sync
    user_id uuid not null references public.profiles (id) on delete cascade,
    logged_at timestamptz not null,
    flavor text not null default 'Original',
    lineup text not null default 'original',
    caffeine_mg int not null default 80 check (caffeine_mg between 0 and 500),
    created_at timestamptz not null default now()
);

create index can_events_user_time_idx on public.can_events (user_id, logged_at desc);

alter table public.can_events enable row level security;

create policy "insert own events"
    on public.can_events for insert to authenticated
    with check (user_id = (select auth.uid()));

create policy "events readable by self and crew mates"
    on public.can_events for select to authenticated
    using (
        user_id = (select auth.uid())
        or exists (
            select 1
            from public.crew_members mine
            join public.crew_members theirs on mine.crew_id = theirs.crew_id
            where mine.user_id = (select auth.uid())
              and theirs.user_id = can_events.user_id
        )
    );

create policy "delete own events"
    on public.can_events for delete to authenticated
    using (user_id = (select auth.uid()));

-- ───────────────────────── RPCs ─────────────────────────

-- Ambiguity-free alphabet, same as the client's invite codes (no 0/O/1/I/L).
create function public.create_crew(p_name text)
returns table (crew_id uuid, invite_code text)
language plpgsql security definer set search_path = ''
as $$
declare
    v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    v_code text;
    v_crew uuid;
    v_uid uuid := (select auth.uid());
begin
    if v_uid is null then
        raise exception 'not signed in';
    end if;
    if p_name is null or char_length(trim(p_name)) not between 1 and 40 then
        raise exception 'crew name must be 1-40 characters';
    end if;

    loop
        v_code := (
            select string_agg(substr(v_alphabet, 1 + floor(random() * 31)::int, 1), '')
            from generate_series(1, 6)
        );
        exit when not exists (select 1 from public.crews c where c.invite_code = v_code);
    end loop;

    insert into public.crews (name, invite_code, created_by)
    values (trim(p_name), v_code, v_uid)
    returning id into v_crew;

    insert into public.crew_members (crew_id, user_id) values (v_crew, v_uid);

    return query select v_crew, v_code;
end;
$$;

create function public.join_crew(p_code text)
returns table (crew_id uuid, crew_name text)
language plpgsql security definer set search_path = ''
as $$
declare
    v_crew public.crews%rowtype;
    v_uid uuid := (select auth.uid());
begin
    if v_uid is null then
        raise exception 'not signed in';
    end if;

    select * into v_crew
    from public.crews c
    where c.invite_code = upper(trim(p_code));

    if not found then
        raise exception 'no crew with that code';
    end if;

    insert into public.crew_members (crew_id, user_id)
    values (v_crew.id, v_uid)
    on conflict do nothing;

    return query select v_crew.id, v_crew.name;
end;
$$;

-- Weekly standings for one crew. Caller must be a member. Week bounds are
-- client-provided (the user's local calendar owns the definition of "week").
create function public.crew_leaderboard(
    p_crew uuid,
    p_start timestamptz,
    p_end timestamptz,
    p_prev_start timestamptz,
    p_prev_end timestamptz
)
returns table (
    user_id uuid,
    display_name text,
    current_count int,
    prev_count int,
    flavors jsonb
)
language sql security definer set search_path = ''
stable
as $$
    select
        m.user_id,
        p.display_name,
        count(e.id) filter (where e.logged_at >= p_start and e.logged_at < p_end)::int,
        count(e.id) filter (where e.logged_at >= p_prev_start and e.logged_at < p_prev_end)::int,
        coalesce(
            (
                select jsonb_object_agg(f.flavor, f.n)
                from (
                    select e2.flavor, count(*)::int as n
                    from public.can_events e2
                    where e2.user_id = m.user_id
                      and e2.logged_at >= p_start and e2.logged_at < p_end
                    group by e2.flavor
                ) f
            ),
            '{}'::jsonb
        )
    from public.crew_members m
    join public.profiles p on p.id = m.user_id
    left join public.can_events e
        on e.user_id = m.user_id
       and e.logged_at >= least(p_prev_start, p_start)
       and e.logged_at < greatest(p_prev_end, p_end)
    where m.crew_id = p_crew
      and public.is_crew_member(p_crew)
    group by m.user_id, p.display_name;
$$;

-- Contact matching: hand in SHA-256 hashes of normalized E.164 numbers,
-- get back matching members + the crew they most recently joined.
create function public.match_contacts(p_hashes text[])
returns table (
    user_id uuid,
    display_name text,
    crew_id uuid,
    crew_name text
)
language sql security definer set search_path = ''
stable
as $$
    select
        p.id,
        p.display_name,
        cm.crew_id,
        c.name
    from public.contact_directory d
    join public.profiles p on p.id = d.user_id
    left join lateral (
        select m.crew_id
        from public.crew_members m
        where m.user_id = p.id
        order by m.joined_at desc
        limit 1
    ) cm on true
    left join public.crews c on c.id = cm.crew_id
    where d.phone_hash = any (p_hashes)
      and p.id <> (select auth.uid())
      and (select auth.uid()) is not null
    limit 100;
$$;

create function public.set_phone_hash(p_hash text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
    v_uid uuid := (select auth.uid());
begin
    if v_uid is null then
        raise exception 'not signed in';
    end if;
    if p_hash is null or char_length(p_hash) <> 64 then
        raise exception 'expected a sha256 hex digest';
    end if;

    insert into public.contact_directory (user_id, phone_hash, updated_at)
    values (v_uid, lower(p_hash), now())
    on conflict (user_id) do update
        set phone_hash = excluded.phone_hash, updated_at = now();
end;
$$;

-- Lock the functions down to signed-in callers.
revoke execute on all functions in schema public from anon, public;
grant execute on function public.create_crew(text) to authenticated;
grant execute on function public.join_crew(text) to authenticated;
grant execute on function public.crew_leaderboard(uuid, timestamptz, timestamptz, timestamptz, timestamptz) to authenticated;
grant execute on function public.match_contacts(text[]) to authenticated;
grant execute on function public.set_phone_hash(text) to authenticated;
grant execute on function public.is_crew_member(uuid) to authenticated;
