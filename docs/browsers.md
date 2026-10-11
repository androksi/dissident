[← voltar ao README](../README.md)

# Navegadores

Os três usam as políticas oficiais de cada navegador: valem para todos os perfis, mesmo se o navegador for instalado depois. Feche e abra o navegador para aplicar (ele vai mostrar "Gerenciado pela organização" — é o normal com políticas). Confira em `brave://policy`, `chrome://policy` ou `about:policies`.

Para desfazer: o mesmo script com `-Revert`.

## Brave

```powershell
.\scripts\browsers\Configure-Brave.ps1
```

| Funcionalidade | O que faz |
|---|---|
| Recursos do Brave | Desliga Wallet, VPN, Recompensas, Leo, News, Talk, Playlist, Wayback, Tor e Speedreader. |
| Telemetria | Desliga P3A, ping diário e Web Discovery. |
| Políticas do Chromium | Desliga relatórios, pesquisas, guias promocionais, segundo plano, lista de compras e o aviso "não é o navegador padrão". |
| Apps, senhas e cartões | Bloqueia instalar sites como app, gerenciador de senhas e cartões salvos. |
| Transmitir para TV | Manter (cria a regra no firewall) ou desligar. Nos dois casos, sem aviso do firewall. |

## Chrome

```powershell
.\scripts\browsers\Configure-Chrome.ps1
```

| Funcionalidade | O que faz |
|---|---|
| Telemetria | Desliga relatórios, envio de URLs, ortografia na nuvem, pesquisas e feedback. |
| Sugestões de pesquisa | Desliga o envio do que você digita ao Google em tempo real (pergunta). |
| Pré-carregamento | Desliga o pré-carregamento de páginas (pergunta). |
| IA | Desliga Gemini, Modo IA e todos os recursos de IA. |
| Cookies | Bloqueia cookies de terceiros, liberando os domínios do Google. |
| Extras | Bloqueia sincronização, segundo plano, lista de compras e o aviso "não é o navegador padrão". Navegação Segura no modo Padrão. |

## Firefox

```powershell
.\scripts\browsers\Configure-Firefox.ps1
```

| Funcionalidade | O que faz |
|---|---|
| Telemetria | Desliga telemetria, estudos e o agente de navegador padrão. |
| Patrocinados e recomendações | Remove patrocinados e recomendações da nova aba e da barra de endereço. |
| IA | Desliga os recursos de IA. A tradução local continua. |
| Extensões | Instala uBlock Origin e Bitwarden. |
| Só Bitwarden | Desliga o gerenciador de senhas do Firefox e o preenchimento de endereços e cartões (avisa se houver senhas salvas). |
| Sem avisos | Tira as dicas da barra de endereço, os convites para recursos experimentais e os favoritos de fábrica. |
| Sugestões de pesquisa | Desliga o envio do que você digita ao buscador em tempo real (pergunta). |
| Pré-carregamento | Desliga o pré-carregamento de páginas (pergunta). |
| Somente HTTPS | Avisa antes de abrir sites sem conexão segura (pergunta). |
