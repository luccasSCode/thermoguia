# Ativar o login com Google e Facebook

O app já tem os botões e todo o fluxo pronto. Falta só criar as credenciais em cada
rede e cadastrá-las no Render. Enquanto elas não existirem, o botão mostra "O login com
Google ainda não foi ativado no servidor".

Como funciona: o app abre `https://SUA_API/auth/google/start` no navegador seguro do
celular, a pessoa entra na conta, o Google devolve um código para a API, a API cria ou
encontra a conta e volta para o app (`thermoguia://auth`) já com a sessão. As chaves
secretas ficam só no servidor; nada precisa ser configurado no app.

Nos exemplos, troque `https://thermoguia-api.onrender.com` pela URL da sua API.

## Google

1. Acesse https://console.cloud.google.com e crie um projeto (ex.: ThermoGuia).
2. Em **APIs e serviços → Tela de permissão OAuth**, escolha **Externo**, preencha o nome
   do app, o e-mail de suporte e salve. Enquanto o app estiver em "Teste", adicione em
   **Usuários de teste** os e-mails que vão entrar.
3. Em **APIs e serviços → Credenciais → Criar credenciais → ID do cliente OAuth**:
   - Tipo de aplicativo: **Aplicativo da Web**
   - URIs de redirecionamento autorizados:
     `https://thermoguia-api.onrender.com/auth/google/callback`
4. Copie o **ID do cliente** e a **Chave secreta do cliente**.

## Facebook

1. Acesse https://developers.facebook.com, clique em **Meus apps → Criar app** e escolha
   o caso de uso **Autenticar e solicitar dados dos usuários com o Login do Facebook**.
2. Em **Login do Facebook → Configurações**, em **URIs de redirecionamento do OAuth
   válidos**, coloque:
   `https://thermoguia-api.onrender.com/auth/facebook/callback`
3. Em **Configurações do app → Básico**, copie o **ID do aplicativo** e a **Chave secreta
   do aplicativo**.
4. Enquanto o app estiver em modo de desenvolvimento, só quem tem função no app
   (administrador, testador) consegue entrar. Para liberar a todos, publique o app no painel.

## Cadastrar no Render

No serviço **thermoguia-api → Environment**, adicione:

| Key | Value |
|---|---|
| `GOOGLE_CLIENT_ID` | ID do cliente do Google |
| `GOOGLE_CLIENT_SECRET` | Chave secreta do cliente do Google |
| `FACEBOOK_APP_ID` | ID do aplicativo do Facebook |
| `FACEBOOK_APP_SECRET` | Chave secreta do aplicativo do Facebook |

Salve: o Render reinicia a API sozinho. Não é preciso gerar o APK de novo.

O Render informa o endereço público da API (`RENDER_EXTERNAL_URL`) automaticamente. Em
outro provedor, cadastre também `PUBLIC_URL` com a URL da API, sem barra no final.

## Testar

Abra o app, toque em **Entrar com uma conta Google** e escolha a conta. Ao voltar, o app
já abre na tela inicial. Se a conta Google usar o mesmo e-mail de uma conta criada com
e-mail e senha, as duas viram uma só.
