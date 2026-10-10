[← voltar ao README](../README.md)

# Windows

```powershell
.\scripts\windows\Configure-Windows.ps1
```

As perguntas vêm todas no começo; depois aparece um resumo e a confirmação.
Para usar só os padrões, sem perguntas: `-NoPrompt`.

## Automático
| Funcionalidade | O que faz |
|---|---|
| Ponto de restauração | Cria um ponto de restauração antes de qualquer mudança. |
| Resumo | Mostra tudo o que foi escolhido e pergunta "Aplicar agora?". |
| Tolerante a falhas | Se uma etapa falhar, avisa e segue para a próxima. |

## Privacidade e limpeza
| Funcionalidade | O que faz |
|---|---|
| Telemetria | Desliga o serviço de telemetria, as tarefas de coleta e aplica as políticas de diagnóstico mínimo, sem anúncios, sem histórico de atividades e sem Bing na pesquisa. Desliga os Widgets. |
| Sugestões | Desliga sugestões, anúncios e instalação silenciosa de apps (Candy Crush etc.). |
| Apps inúteis | Remove Clipchamp, Bing, Solitaire, Teams, Outlook novo, Copilot e outros. |
| Apps opcionais | Remove também Vincular ao Celular, Sticky Notes, Gravador, Relógio, Assistência Rápida, Media Player e OneNote. |
| OneDrive | Desinstala o OneDrive e impede que volte. |
| Edge | Políticas do Edge: sem telemetria, segundo plano, barra lateral, Copilot e compras. |
| Segurança do Windows | Liga o bloqueio de apps e downloads indesejados e esconde avisos sem importância. |
| Pastas do C: | Esconde a `inetpub` e apaga a `PerfLogs`. |
| Apps de periféricos | Não baixa apps e ícones de fabricante ao conectar periféricos (drivers continuam vindo). |
| Esconder áreas | Esconde "Proteção de contas" e "Segurança do dispositivo" da Segurança do Windows (avisos de conta Microsoft). |

## Personalização
| Funcionalidade | O que faz |
|---|---|
| Tema | Manter, Windows claro ou Windows escuro. Desliga o Destaques do Windows e aplica o papel de parede do tema. |
| Barra de tarefas | Manter, ícones ao centro ou à esquerda. |
| Pesquisa | Manter, oculta, só o ícone ou caixa de pesquisa. |
| Visão de Tarefas | Manter, mostrar ou ocultar o botão. |
| Sem fixados | Remove todos os ícones fixados na barra de tarefas. |
| Bateria em % | Mostra a porcentagem da bateria na barra de tarefas (só notebook). |
| Extensões | Mostra as extensões dos arquivos. |
| Sem frequentes | Esconde as pastas frequentes do Acesso rápido. |
| Sem recentes | Esconde os arquivos recentes no Explorador. |
| Arquivos ocultos | Mostra arquivos e pastas ocultos. |
| Sem descoberta de pasta | Pastas grandes abrem mais rápido. Zera as visualizações personalizadas. |
| Sem Início/Galeria | Remove Início e Galeria do Explorador, que passa a abrir em "Este Computador". |
| Borda fina | Afina a área invisível de redimensionar janelas. |

## Uso no dia a dia
| Funcionalidade | O que faz |
|---|---|
| Caminhos longos | Permite caminhos com mais de 260 caracteres. |
| Finalizar tarefa | Adiciona "Finalizar tarefa" ao clicar com o direito num app na barra. |
| Sudo | Ativa o `sudo` no terminal. |
| Histórico Win+V | Ativa o histórico da área de transferência. |
| Sem aceleração | Desliga a aceleração do mouse. |
| Sem aderência | Desliga o atalho das Teclas de Aderência (Shift 5 vezes). |
| Volume 100% | Coloca o volume do aparelho de som em uso em 100%. |
| Tela azul detalhada | Mostra os detalhes técnicos do erro na tela azul. |

## Rede
| Funcionalidade | O que faz |
|---|---|
| DNS | Define DNS IPv4 e IPv6 manualmente, com DNS por HTTPS (modelo automático) no Windows 11. |

## Reverter

```powershell
.\scripts\windows\Revert-Configure-Windows.ps1
```

| Funcionalidade | O que faz |
|---|---|
| Reverter | Desfaz telemetria, políticas, sugestões, borda, DNS, Edge, áreas da Segurança, Início/Galeria, descoberta de pasta, periféricos, tela azul e `inetpub`. |
| Não reverte | Apps removidos, OneDrive, tema, barra de tarefas, extensões, volume, arquivos ocultos e bateria (desfazer pelas Configurações). |
