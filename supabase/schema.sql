-- =====================================================================
--  MASTER SPORTWEAR · SISTEMA FINANCEIRO — Banco de dados (Supabase)
--  Execute este arquivo inteiro UMA vez em: Supabase → SQL Editor → New query → Run
--  Pode ser executado de novo sem perder dados (comandos idempotentes).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. PERFIS DE USUÁRIO (quem pode ver / lançar)
--    admin      = tudo, inclusive liberar usuários e ver auditoria
--    financeiro = consulta e lança
--    leitura    = só consulta
--    pendente   = cadastrado, aguardando liberação do admin (sem acesso)
-- ---------------------------------------------------------------------
create table if not exists public.perfis (
  id         uuid primary key references auth.users(id) on delete cascade,
  email      text,
  nome       text,
  papel      text not null default 'pendente' check (papel in ('admin','financeiro','leitura','pendente')),
  criado_em  timestamptz not null default now()
);

-- papel do usuário logado (security definer evita recursão nas políticas)
create or replace function public.papel_atual() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select papel from public.perfis where id = auth.uid()), 'pendente');
$$;

create or replace function public.pode_ler() returns boolean
language sql stable security definer set search_path = public as $$
  select public.papel_atual() in ('admin','financeiro','leitura');
$$;

create or replace function public.pode_lancar() returns boolean
language sql stable security definer set search_path = public as $$
  select public.papel_atual() in ('admin','financeiro');
$$;

-- novo usuário → cria perfil. O PRIMEIRO usuário do sistema vira admin; os demais ficam pendentes.
create or replace function public.novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfis (id, email, nome, papel)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email,'@',1)),
          case when exists (select 1 from public.perfis where papel = 'admin') then 'pendente' else 'admin' end)
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function public.novo_usuario();

-- usuários que já existiam antes deste script
insert into public.perfis (id, email, nome, papel)
select u.id, u.email, split_part(u.email,'@',1),
       case when row_number() over (order by u.created_at) = 1
             and not exists (select 1 from public.perfis where papel='admin') then 'admin' else 'pendente' end
from auth.users u
on conflict (id) do nothing;

alter table public.perfis enable row level security;
drop policy if exists perfis_ver on public.perfis;
create policy perfis_ver on public.perfis for select to authenticated
  using (id = auth.uid() or public.papel_atual() = 'admin');
drop policy if exists perfis_admin on public.perfis;
create policy perfis_admin on public.perfis for update to authenticated
  using (public.papel_atual() = 'admin') with check (public.papel_atual() = 'admin');
drop policy if exists perfis_excluir on public.perfis;
create policy perfis_excluir on public.perfis for delete to authenticated
  using (public.papel_atual() = 'admin' and id <> auth.uid());

-- impede que o sistema fique sem nenhum administrador
create or replace function public.protege_ultimo_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.papel = 'admin' and (tg_op = 'DELETE' or new.papel <> 'admin')
     and (select count(*) from public.perfis where papel = 'admin') <= 1 then
    raise exception 'O sistema precisa de pelo menos um administrador.';
  end if;
  return coalesce(new, old);
end $$;
drop trigger if exists ultimo_admin on public.perfis;
create trigger ultimo_admin before update or delete on public.perfis
  for each row execute function public.protege_ultimo_admin();

-- ---------------------------------------------------------------------
-- 2. AUDITORIA — registra quem criou, alterou ou excluiu cada lançamento
-- ---------------------------------------------------------------------
create table if not exists public.auditoria (
  id           bigint generated always as identity primary key,
  em           timestamptz not null default now(),
  usuario_id   uuid,
  usuario      text,
  tabela       text not null,
  registro_id  text not null,
  acao         text not null,          -- INSERT / UPDATE / DELETE
  antes        jsonb,
  depois       jsonb
);
create index if not exists auditoria_em_idx on public.auditoria (em desc);
alter table public.auditoria enable row level security;
drop policy if exists auditoria_ver on public.auditoria;
create policy auditoria_ver on public.auditoria for select to authenticated using (public.papel_atual() = 'admin');

create or replace function public.registra_auditoria() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  select email into v_email from public.perfis where id = auth.uid();
  insert into public.auditoria (usuario_id, usuario, tabela, registro_id, acao, antes, depois)
  values (auth.uid(), v_email, tg_table_name, coalesce(new.id, old.id), tg_op,
          case when tg_op <> 'INSERT' then old.dados end,
          case when tg_op <> 'DELETE' then new.dados end);
  return coalesce(new, old);
end $$;

create or replace function public.carimbo() returns trigger
language plpgsql as $$
begin
  new.atualizado_em := now();
  new.atualizado_por := auth.uid();
  return new;
end $$;

-- ---------------------------------------------------------------------
-- 3. TABELAS DE LANÇAMENTOS
--    Cada linha guarda o lançamento completo em "dados" (jsonb), no mesmo
--    formato usado pelo sistema. As VIEWS no fim do arquivo expõem as colunas
--    tipadas (data, valor, fornecedor…) para relatórios e consultas SQL.
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['receitas','duplicatas','cartoes','contas_pagar','compras','logistica',
                           'relatorio_pagamentos','extrato_bancario','pedidos','configuracoes']
  loop
    execute format('create table if not exists public.%I (
        id             text primary key,
        dados          jsonb not null,
        criado_em      timestamptz not null default now(),
        atualizado_em  timestamptz not null default now(),
        atualizado_por uuid)', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I replica identity full', t);

    execute format('drop policy if exists ler on public.%I', t);
    execute format('create policy ler on public.%I for select to authenticated using (public.pode_ler())', t);
    execute format('drop policy if exists incluir on public.%I', t);
    execute format('create policy incluir on public.%I for insert to authenticated with check (public.pode_lancar())', t);
    execute format('drop policy if exists alterar on public.%I', t);
    execute format('create policy alterar on public.%I for update to authenticated using (public.pode_lancar()) with check (public.pode_lancar())', t);
    execute format('drop policy if exists excluir on public.%I', t);
    execute format('create policy excluir on public.%I for delete to authenticated using (public.pode_lancar())', t);

    execute format('drop trigger if exists carimbo on public.%I', t);
    execute format('create trigger carimbo before insert or update on public.%I for each row execute function public.carimbo()', t);
    execute format('drop trigger if exists auditoria on public.%I', t);
    execute format('create trigger auditoria after insert or update or delete on public.%I for each row execute function public.registra_auditoria()', t);
  end loop;
end $$;

-- índices úteis para consultas por data
create index if not exists receitas_data_idx      on public.receitas ((dados->>'data'));
create index if not exists duplicatas_entrega_idx on public.duplicatas ((dados->>'entrega'));
create index if not exists contas_pagar_venc_idx  on public.contas_pagar ((dados->>'venc'));
create index if not exists compras_data_idx       on public.compras ((dados->>'data'));
create index if not exists logistica_data_idx     on public.logistica ((dados->>'data'));
create index if not exists extrato_data_idx       on public.extrato_bancario ((dados->>'data'));

-- ---------------------------------------------------------------------
-- 4. TEMPO REAL — vários usuários veem as alterações uns dos outros na hora
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['receitas','duplicatas','cartoes','contas_pagar','compras','logistica',
                           'relatorio_pagamentos','extrato_bancario','pedidos','configuracoes']
  loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 5. VIEWS PARA RELATÓRIOS (Table Editor, SQL, Excel, Power BI, Looker…)
--    security_invoker = as views respeitam as mesmas permissões das tabelas
-- ---------------------------------------------------------------------
create or replace view public.vw_contas_pagar with (security_invoker = on) as
select id,
       dados->>'fornecedor'                        as fornecedor,
       dados->>'descricao'                         as descricao,
       dados->>'categoria'                         as categoria,
       (dados->>'valor')::numeric                  as valor_previsto,
       nullif(dados->>'venc','')::date             as vencimento,
       dados->>'status'                            as situacao,
       nullif(dados->>'dataPg','')::date           as data_pagamento,
       coalesce((dados->>'valorPago')::numeric,0)  as valor_pago,
       coalesce((dados->>'juros')::numeric,0)      as juros,
       coalesce((dados->>'multa')::numeric,0)      as multa,
       dados->>'fonte'                             as fonte_pagamento
from public.contas_pagar;

create or replace view public.vw_duplicatas with (security_invoker = on) as
select d.id,
       d.dados->>'os'                                   as os,
       d.dados->>'cliente'                              as cliente,
       nullif(d.dados->>'entrega','')::date             as entrega,
       coalesce((d.dados->>'valor')::numeric,0)         as valor,
       coalesce((d.dados->>'frete')::numeric,0)         as frete,
       coalesce(p.recebido,0)                           as recebido,
       greatest(coalesce((d.dados->>'valor')::numeric,0) + coalesce((d.dados->>'frete')::numeric,0) - coalesce(p.recebido,0), 0) as saldo,
       p.ultimo_recebimento
from public.duplicatas d
left join lateral (
  select sum((pg->>'valor')::numeric) as recebido, max(nullif(pg->>'data','')::date) as ultimo_recebimento
  from jsonb_array_elements(coalesce(d.dados->'pagamentos','[]'::jsonb)) pg
) p on true;

create or replace view public.vw_duplicatas_recebimentos with (security_invoker = on) as
select d.id as duplicata_id, d.dados->>'os' as os, d.dados->>'cliente' as cliente,
       pg->>'id' as recebimento_id, nullif(pg->>'data','')::date as data, (pg->>'valor')::numeric as valor,
       pg->>'forma' as forma, pg->>'obs' as observacao
from public.duplicatas d, jsonb_array_elements(coalesce(d.dados->'pagamentos','[]'::jsonb)) pg;

create or replace view public.vw_receitas with (security_invoker = on) as
select id, nullif(dados->>'data','')::date as data, dados->>'tipo' as tipo, dados->>'descricao' as descricao,
       dados->>'forma' as forma, (dados->>'valor')::numeric as valor, coalesce((dados->>'frete')::numeric,0) as frete,
       dados->>'osRef' as os
from public.receitas;

create or replace view public.vw_compras with (security_invoker = on) as
select id, nullif(dados->>'data','')::date as data, dados->>'cat' as insumo, dados->>'item' as produto,
       dados->>'fornecedor' as fornecedor, (dados->>'qtd')::numeric as quantidade, dados->>'unid' as unidade,
       (dados->>'preco')::numeric as preco_unitario, (dados->>'total')::numeric as total
from public.compras;

create or replace view public.vw_logistica with (security_invoker = on) as
select id, nullif(dados->>'data','')::date as data, dados->>'tipo' as tipo, dados->>'prestador' as prestador,
       dados->>'origem' as origem, dados->>'destino' as destino, (dados->>'valor')::numeric as valor
from public.logistica;

create or replace view public.vw_cartoes with (security_invoker = on) as
select id, dados->>'os' as os, nullif(dados->>'data','')::date as data, dados->>'operadora' as operadora,
       dados->>'forma' as forma, (dados->>'parcelas')::int as parcelas, (dados->>'valor')::numeric as valor_bruto,
       nullif(dados->>'taxa','')::numeric as taxa_pct, (dados->>'liquido')::numeric as valor_liquido
from public.cartoes;

create or replace view public.vw_extrato_bancario with (security_invoker = on) as
select id, dados->>'conta' as conta, nullif(dados->>'data','')::date as data, dados->>'desc' as descricao,
       (dados->>'valor')::numeric as valor,
       case when (dados->>'ignorado')::boolean then 'Ignorado'
            when jsonb_array_length(coalesce(nullif(dados->'links','null'::jsonb),'[]'::jsonb)) > 0 then 'Conciliado'
            else 'Pendente' end as situacao
from public.extrato_bancario;

-- Pronto! Próximo passo: criar o seu usuário em Authentication → Users (ele será o administrador).
