// =====================================================================
//  Configuração de conexão com o Supabase
//  Supabase → botão "Connect" no topo do projeto (ou Project Settings → API Keys)
//  Copie a "Project URL" e a "Publishable key" (sb_publishable_...) e cole abaixo, entre as aspas.
//  A chave publishable é pública por natureza: quem protege os dados são o login
//  e as regras de segurança (RLS) criadas pelo schema.sql.
//  NUNCA coloque aqui a Secret key (sb_secret_...) nem a "service_role".
// =====================================================================
window.MASTER_CONFIG = {
  supabaseUrl: 'https://npnfnhvknffecldknybo.supabase.co',
  supabaseAnonKey: 'sb_publishable_34z39ptyRiw8FR8yTRl65w_-6RRWjK-'
};
