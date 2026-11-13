-- =====================================================================
--  JERIDE — Synchronisation cloud (Supabase)
--  À coller UNE SEULE FOIS dans Supabase › SQL Editor › New query › Run
-- =====================================================================
--  Principe : la table n'est PAS lisible directement. L'appli passe par
--  3 fonctions qui exigent ton « code de synchro » secret (16 caractères
--  minimum). Sans ce code, personne ne peut lire ni écrire tes séances.
-- =====================================================================

create table if not exists public.jeride_items (
  owner      text        not null,              -- ton code de synchro
  kind       text        not null,              -- 'sessions' ou 'routes'
  id         text        not null,              -- identifiant de la séance / du parcours
  data       jsonb,                             -- contenu complet
  deleted    boolean     not null default false,-- true = supprimé (propagé aux autres appareils)
  u          bigint      not null default 0,    -- date de dernière modification (ms)
  updated_at timestamptz not null default now(),
  primary key (owner, kind, id)
);

alter table public.jeride_items enable row level security;
revoke all on public.jeride_items from anon, authenticated;

-- Liste légère (sans le contenu) de tout ce qui est en ligne
create or replace function public.jeride_list(code text)
returns table(kind text, id text, deleted boolean, u bigint)
language sql security definer set search_path = public as $$
  select t.kind, t.id, t.deleted, t.u
  from jeride_items t
  where t.owner = code and length(code) >= 16
$$;

-- Récupère le contenu de certains éléments (clés au format 'kind:id')
create or replace function public.jeride_get(code text, keys text[])
returns table(kind text, id text, data jsonb)
language sql security definer set search_path = public as $$
  select t.kind, t.id, t.data
  from jeride_items t
  where t.owner = code and length(code) >= 16
    and (t.kind || ':' || t.id) = any(keys)
$$;

-- Envoie / met à jour des éléments (la version la plus récente gagne)
create or replace function public.jeride_put(code text, items jsonb)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if code is null or length(code) < 16 then
    raise exception 'code de synchro trop court';
  end if;
  insert into jeride_items as t (owner, kind, id, data, deleted, u, updated_at)
  select code,
         x->>'kind',
         x->>'id',
         x->'data',
         coalesce((x->>'deleted')::boolean, false),
         coalesce((x->>'u')::bigint, 0),
         now()
  from jsonb_array_elements(items) as x
  on conflict (owner, kind, id) do update
    set data = excluded.data,
        deleted = excluded.deleted,
        u = excluded.u,
        updated_at = now()
    where t.u <= excluded.u;
end
$$;

revoke all on function public.jeride_list(text)            from public;
revoke all on function public.jeride_get(text, text[])     from public;
revoke all on function public.jeride_put(text, jsonb)      from public;
grant execute on function public.jeride_list(text)         to anon, authenticated;
grant execute on function public.jeride_get(text, text[])  to anon, authenticated;
grant execute on function public.jeride_put(text, jsonb)   to anon, authenticated;
