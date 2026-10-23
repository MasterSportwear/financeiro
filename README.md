# Master Sportwear · Sistema Financeiro (versão online)

Sistema financeiro da Master Sportwear publicado no **GitHub Pages**, com os dados guardados no **Supabase** (banco PostgreSQL com login, permissões por usuário, auditoria e atualização em tempo real entre os usuários).

## O que tem neste pacote

| Arquivo | Para que serve | Vai para o GitHub? |
|---|---|---|
| `index.html` | O sistema. Não contém nenhum dado da empresa. | ✅ Sim |
| `config.js` | Endereço e chave pública do seu projeto Supabase (você preenche). | ✅ Sim |
| `supabase/schema.sql` | Cria tabelas, permissões, auditoria e views no Supabase. | ✅ Pode ir (não tem dados) |
| `README.md` | Este passo a passo. | ✅ Sim |
| `dados_iniciais_2025.json` | Dados de 2025 das planilhas, para carregar no banco. | ❌ **NUNCA** — contém dados financeiros |

> **Por que os dados não ficam no GitHub?** No plano gratuito, o GitHub Pages exige repositório **público**: qualquer pessoa pode ver os arquivos. Por isso o `index.html` vai vazio e os dados ficam só no Supabase, protegidos por login.

---

## Parte 1 — Criar o banco no Supabase (≈10 min)

1. Acesse **https://supabase.com** → **Start your project** e entre (pode usar a conta do GitHub).
2. Clique em **New project** e preencha:
   - **Name:** `master-financeiro`
   - **Database Password:** crie uma senha forte e **guarde** (não é a senha do sistema, é a do banco).
   - **Region:** `South America (São Paulo)`.
   - Clique em **Create new project** e aguarde 1–2 minutos.
3. No menu lateral, abra **SQL Editor** → **New query**.
4. Abra o arquivo `supabase/schema.sql`, copie **todo** o conteúdo, cole no editor e clique em **Run**.
   - Deve aparecer **"Success. No rows returned"**. Pode rodar de novo sem problema, se precisar.
5. Crie o **seu** usuário (o primeiro usuário vira **Administrador** automaticamente):
   - **Authentication** → **Users** → **Add user** → **Create new user**
   - Informe seu e-mail e uma senha, marque **Auto Confirm User** e clique em **Create user**.
6. Copie as duas informações de conexão — o jeito mais fácil é o botão **Connect** no topo do painel do projeto, que mostra as duas:
   - **Project URL** (ex.: `https://abcdefgh.supabase.co`).
   - **Publishable key** (começa com `sb_publishable_…`). Ela também fica em **Project Settings → API Keys**.
   - A chave antiga **`anon` `public`** também funciona, mas o Supabase vai desativá-la até o fim de 2026 — prefira a *Publishable key*.
   - ⚠️ **Nunca** use a *Secret key* (`sb_secret_…`) nem a `service_role` no sistema.

## Parte 2 — Preencher o `config.js`

Abra o `config.js` em um editor de texto (Bloco de Notas serve) e substitua os textos entre aspas:

```js
window.MASTER_CONFIG = {
  supabaseUrl: 'https://abcdefgh.supabase.co',
  supabaseAnonKey: 'sb_publishable_xxxxxxxxxxxxxxxx'
};
```

Salve o arquivo.

## Parte 3 — Publicar no GitHub Pages (≈5 min)

1. Entre em **https://github.com** → botão **+** (canto superior direito) → **New repository**.
   - **Repository name:** `master-financeiro`
   - Marque **Public** → **Create repository**.
2. Na página do repositório, clique em **uploading an existing file** (ou **Add file → Upload files**).
3. Arraste `index.html`, `config.js`, `README.md` e a pasta `supabase` → **Commit changes**.
   - ❌ Não envie o `dados_iniciais_2025.json` nem arquivos de backup.
4. Vá em **Settings** → **Pages** (menu lateral):
   - **Source:** *Deploy from a branch*
   - **Branch:** `main` e pasta `/ (root)` → **Save**.
5. Aguarde 1–2 minutos e atualize a página: aparece o endereço do sistema, no formato
   `https://SEU-USUARIO.github.io/master-financeiro/`

## Parte 4 — Ligar o endereço do GitHub ao Supabase

Necessário para os links de **confirmação de e-mail** e **"esqueci minha senha"** voltarem para o sistema.

1. Supabase → **Authentication** → **URL Configuration**.
2. **Site URL:** cole o endereço do GitHub Pages (ex.: `https://SEU-USUARIO.github.io/master-financeiro/`) → **Save**.
3. Em **Redirect URLs** → **Add URL** → cole o mesmo endereço → **Save**.

## Parte 5 — Primeiro acesso e carga dos dados

1. Abra o endereço do GitHub Pages e entre com o e-mail e a senha criados na Parte 1.
2. Como o banco está vazio, o sistema pergunta como começar. Clique em **Carregar um arquivo .json** e escolha:
   - **Recomendado:** o **backup da versão local** que você já usa (na versão local: *Configurações & Backup → Baixar backup (.json)*). Ele traz tudo o que você lançou, inclusive OS importadas, conciliações e plano de contas.
   - **Ou** o `dados_iniciais_2025.json` deste pacote, se quiser começar só com os dados das planilhas de 2025.
3. Confirme. O sistema envia os registros ao banco e o indicador no topo mostra **"Sincronizado"**.

## Parte 6 — Liberar outros usuários

1. O colaborador abre o endereço do sistema → **Solicitar acesso** → preenche nome, e-mail e senha → confirma o e-mail recebido.
2. Você (administrador) entra em **Configurações & Backup → Usuários e acessos** e escolhe o acesso:
   - **Administrador:** tudo, inclusive liberar usuários e ver a auditoria.
   - **Financeiro:** consulta e lança.
   - **Somente leitura:** só consulta (os botões de lançar somem).
   - **Pendente:** sem acesso.
3. Opcional, para fechar o cadastro público: Supabase → **Authentication → Sign In / Providers → Email** → desligue **Allow new users to sign up**. A partir daí, só você cria usuários em **Authentication → Users → Add user**.

---

## Como funciona

- **Tempo real:** o que um usuário lança aparece na tela dos outros em segundos, sem recarregar.
- **Auditoria:** toda inclusão, alteração e exclusão fica registrada com usuário, data e hora (*Configurações → Últimas alterações*, visível para administradores).
- **Segurança:** a chave pública só permite acesso depois do login, e cada perfil só faz o que o papel permite. As regras ficam no banco (RLS), não no navegador.
- **Consultas e relatórios externos:** o banco já tem *views* com colunas prontas (`vw_contas_pagar`, `vw_duplicatas`, `vw_duplicatas_recebimentos`, `vw_receitas`, `vw_compras`, `vw_logistica`, `vw_cartoes`, `vw_extrato_bancario`), úteis no SQL Editor, Excel ou Power BI.

## Cuidados

- **Backup:** baixe o backup `.json` toda semana (*Configurações & Backup*). O plano gratuito do Supabase não oferece download de backups automáticos.
- **Projeto pausado:** no plano gratuito, projetos sem uso por alguns dias podem ser pausados pelo Supabase. Se o sistema não conectar, entre no painel do Supabase e clique em **Restore project**.
- **Atualizar o sistema:** quando houver nova versão, substitua só o `index.html` no GitHub (*Add file → Upload files*). O `config.js` e os dados continuam os mesmos.
