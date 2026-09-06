# Atlas Browser — protótipo nativo para iPad

Repositório: [MarceloAvelinoMoreira/browseravelino](https://github.com/MarceloAvelinoMoreira/browseravelino).

Primeira base de desenvolvimento: SwiftUI, WKWebView, chat lateral e servidor Node que consulta a Responses API. Ainda não compilado em Xcode nem validado em iPad. Não é uma versão pronta para distribuição.

## Executar

1. Em um Mac com Xcode e Homebrew, execute `brew install xcodegen`, depois `xcodegen generate --spec project.json` na raiz deste projeto. Abra `AtlasBrowser.xcodeproj`, selecione o esquema AtlasBrowser e um simulador de iPad. Para iPad físico, configure sua equipe Apple em Signing & Capabilities e um identificador de app disponível.
2. No servidor com Node 22+, defina OPENAI_API_KEY, OPENAI_MODEL (modelo da sua conta compatível com function calling), ATLAS_TOKEN (segredo longo exclusivo para este protótipo). Execute `node server/server.mjs`.
3. Disponibilize o servidor por HTTPS. Ele escuta em localhost:8787 para ficar atrás de um proxy HTTPS. Não exponha sua chave OpenAI ao aplicativo.
4. No app, abra Configurações e informe a URL HTTPS do servidor e ATLAS_TOKEN. O token fica apenas em memória nesta versão.
5. Abra uma página, ative o compartilhamento de conteúdo com a IA e peça para resumir ou preencher um campo. O conteúdo visível da página será enviado ao servidor e à OpenAI enquanto a tarefa estiver ativa.

## O que está implementado

- Navegação HTTPS, voltar, avançar, recarregar e painel lateral.
- Leitura do texto da página principal e identificação de campos/botões visíveis.
- Ciclo de até 8 ações com nova leitura depois de cada ação.
- Preenchimento de inputs e textareas, seleção de opções, rolagem, navegação e cliques.
- Revisão de cada clique/navegação solicitado pela IA antes da execução; botão Parar.
- Exclusão de campos password/hidden da lista de controles; valores dos campos não são enviados no snapshot.
- Credencial OpenAI exclusivamente no servidor; autenticação do protótipo por token.

## Limites e próximos passos

Esta base usa uma aba. Não inclui downloads, uploads, pop-ups, gerenciador de senhas, histórico persistente, sincronização nem distribuição TestFlight. Iframes e shadow DOM não estão cobertos. Texto sensível exibido na página pode entrar no contexto: a exclusão de campos password não equivale a anonimização. CAPTCHAs e autenticação dependem do usuário. Não há acesso à assinatura ou ao histórico do ChatGPT: a integração usa API.

Antes de distribuição: compilar e testar em dispositivo, autenticação por usuário, limites de consumo, Keychain, testes em sites reais, acessibilidade, cancelamento do trabalho no servidor, auditoria de privacidade e preparação de assinatura/distribuição Apple. A resposta da IA é uma proposta; o executor aceita apenas operações definidas, sem JavaScript arbitrário gerado pelo modelo.

## Verificação local

`npm run check`

`npm test`

A verificação de sintaxe e os quatro testes do executor JavaScript passaram no Windows. Esses testes não substituem testes do WKWebView, a compilação Swift ou a conexão real com a API. Nenhuma chamada paga foi executada nesta preparação.

## Rodar primeiro no GitHub

O workflow `.github/workflows/ci.yml` roda em pushes para `main`, pull requests e pelo botão **Run workflow** na aba **Actions**. Ele verifica JavaScript no Linux e gera/compila o projeto Swift no macOS para o simulador. Não exige chave OpenAI, certificado Apple nem secrets para esses testes. O workflow não hospeda o servidor e não faz chamadas reais de IA.

Após uma execução bem-sucedida, o artefato **AtlasBrowser-simulator** contém o app compilado para simulador; não é um IPA instalável em iPad físico. O log fica disponível no artefato **xcodebuild-log**. Para testar a interface, use um Mac e o simulador do Xcode. GitHub Pages não executa este aplicativo SwiftUI nem o servidor Node.

O identificador `com.marceloavelino.AtlasBrowser` é provisório e deve ser confirmado na etapa de assinatura. O arquivo `project.json` é a fonte versionada do projeto Xcode; a pasta `.xcodeproj` é gerada a partir dele.

Referências: https://developers.openai.com/api/docs/guides/function-calling e https://developer.apple.com/documentation/webkit/wkwebview.
