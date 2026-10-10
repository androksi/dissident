<div align="center">

<img src="assets/logo.svg" width="120" alt="dissident">

# dissident

**Seu PC. Suas regras.**

Scripts para um Windows que trabalha pra você — sem telemetria, sem lixo, sem pedir licença.

![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0d1117?style=flat-square)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-0d1117?style=flat-square)
<!-- Badge do lint: em repositório privado ele só aparece para quem tem acesso. Troque USUARIO e descomente se quiser:
![Lint](https://github.com/USUARIO/dissident/actions/workflows/lint.yml/badge.svg) -->

</div>

<!-- Grave um GIF do menu com o ScreenToGif, salve em assets/demo.gif e descomente:
<p align="center"><img src="assets/demo.gif" width="720" alt="demonstração"></p> -->

---

## Uso rápido

Baixe o repositório (**Code → Download ZIP**, ou `git clone`), extraia e abra o **Terminal como Administrador** (Win + X) na pasta:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\windows\Configure-Windows.ps1
```

Todas as perguntas têm um padrão — só apertar **Enter** já faz a escolha recomendada.
Todos os scripts podem ser rodados mais de uma vez sem problema.

## Scripts

| Script | O que faz | Detalhes |
|---|---|---|
| `scripts/windows/Configure-Windows.ps1` | Telemetria, apps inúteis, OneDrive, Edge, tema, barra de tarefas, Explorador, DNS criptografado e mais — tudo com perguntas | [docs/windows.md](docs/windows.md) |
| `scripts/windows/Revert-Configure-Windows.ps1` | Desfaz o que o Configure-Windows mudou | [docs/windows.md](docs/windows.md#reverter) |
| `scripts/apps/Configure-Apps.ps1` | Lista com 100 apps para marcar e instalar pelo WinGet | [docs/apps.md](docs/apps.md) |
| `scripts/browsers/Configure-Brave.ps1` | Brave sem Wallet, VPN, Rewards, Leo, News e telemetria | [docs/browsers.md](docs/browsers.md#brave) |
| `scripts/browsers/Configure-Chrome.ps1` | Chrome sem telemetria e IA, com login do Google funcionando | [docs/browsers.md](docs/browsers.md#chrome) |
| `scripts/browsers/Configure-Firefox.ps1` | Firefox sem telemetria, patrocinados e IA, com uBlock Origin e Bitwarden | [docs/browsers.md](docs/browsers.md#firefox) |

Para desfazer os navegadores: rode o mesmo script com `-Revert`.

## Ordem recomendada depois de formatar

1. Windows Update até não aparecer mais nada (inclusive *Atualizações opcionais*)
2. Drivers do fabricante (placa de vídeo pelo app do fabricante)
3. Microsoft Store → *Obter atualizações*
4. Reiniciar
5. `Configure-Windows.ps1` → `Configure-Apps.ps1` → scripts dos navegadores

## O que **não** faz

- Não desliga o Windows Defender, o Firewall nem a Navegação Segura
- Não bloqueia nem adia o Windows Update
- Não mexe em drivers, energia ou hibernação
- Não instala nada escondido — o `Configure-Apps` só instala o que você marcar
- Não usa "tweaks" de desempenho sem efeito real (serviços em manual, planos de energia, registro "mágico")

Antes de mudar qualquer coisa, o `Configure-Windows` cria um **ponto de restauração**.

## Requisitos

- Windows 10 ou 11
- Windows PowerShell 5.1 (já vem no Windows), executado como Administrador
- `Configure-Apps`: WinGet (o próprio script oferece instalar, se faltar)

## Uso

Repositório privado, para uso pessoal.
