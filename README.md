# Tibidle Multi-Manager para macOS

Aplicativo de comunidade para jogar [Tibidle](https://play.tibidle.com/) no macOS com quatro contas em uma janela. Port nativo do [Tibidle Multi-Manager para Windows](https://github.com/danbatista/tibidle-multi-manager), feito em Swift, AppKit e WebKit (`WKWebView`), sem dependências externas.

Cada pessoa entra com suas próprias contas diretamente no site do jogo. Não há assinatura nem serviço próprio do gerenciador. Código aberto sob a [licença MIT](LICENSE).

## Recursos

- Quatro abas com perfis de navegador separados (cookies e armazenamento isolados).
- Logins e preferências persistentes entre aberturas.
- Visualização normal ou quatro telas em grade 2 × 2.
- Arraste as abas para reorganizar; a grade segue a mesma ordem.
- Nome personalizado, som e recarregamento por conta.
- Atalhos `⌘1` a `⌘4`, seguindo a ordem visual.
- Trocar de visualização ou reorganizar não recarrega as páginas.
- Páginas ocultas continuam rodando em velocidade normal (`inactiveSchedulingPolicy = .none`).
- Zoom por conta (`⌘+`, `⌘-`, `⌘0`) e tela cheia (`⌃⌘F`).
- **Limpar sessão** por conta: apaga cookies e dados só daquele perfil.
- **Dashboard de hunts** no navegador, acessível pela rede local (veja abaixo).

**Requisitos:** macOS 14 Sonoma ou mais recente, Apple Silicon ou Intel. É necessária internet para jogar.

## Compilar e instalar

Requer as Command Line Tools do Xcode (`xcode-select --install`) ou o Xcode.

```sh
./scripts/build-app.sh
```

Resultado:

- `dist/Tibidle Multi-Manager.app` — arraste para `/Applications`.
- `dist/TibidleMultiManager-macOS.zip` — pacote para distribuir (binário universal arm64 + x86_64).

O app é assinado *ad hoc* (sem Developer ID). Ao abrir um ZIP baixado da internet, o Gatekeeper pode bloquear: clique com o botão direito no app → **Abrir**, ou rode `xattr -dr com.apple.quarantine "/Applications/Tibidle Multi-Manager.app"`.

## Como usar

1. **Login:** abra cada aba e entre na conta desejada no site do jogo.
2. **Nome:** altere **Nome da conta** e clique em **Salvar nome** (ou Enter).
3. **Visualização:** **4 telas** mostra a grade; **Tela normal** amplia a conta selecionada (`⇧⌘G`).
4. **Ordem:** arraste uma aba sobre outra. A ordem é salva na hora e vale na grade da esquerda para a direita, de cima para baixo.
5. **Seleção:** use a aba, o título do bloco ou clique no jogo. Som (`⇧⌘M`) e Recarregar (`⌘R`) atuam na conta selecionada.
6. **Atalhos:** `⌘1` a `⌘4` selecionam as posições atuais.

Fechar a janela encerra o aplicativo e mantém seus dados. Abrir o app de novo com ele já aberto apenas traz a janela para frente.

## Dashboard de hunts

Com o app aberto, acesse **Dashboard → Abrir dashboard** (`⇧⌘D`) ou, de outro aparelho na mesma rede, o endereço mostrado na barra inferior do app (por exemplo `http://192.168.0.10:8787`; **Dashboard → Copiar endereço para a rede local**). Se o macOS perguntar se o app pode aceitar conexões de entrada, permita.

A página atualiza sozinha e mostra:

- um cartão por conta com status (caçando, na cidade, desconectada), XP/h, lucro/h, loot, supplies, balance, dano, cura, monstros mais abatidos e HP/mana da party;
- gráficos de XP/h e lucro/h nas últimas 1 h, 6 h, 12 h, 24 h ou 7 dias, com tabela;
- o histórico de hunts encerradas: duração, motivo (morte, cap cheio, sem gold…), level, XP, loot, supplies, balance e mortes;
- as **missões diárias** de cada conta: progresso, tempo até o reset e se a hunt atual conta ou não;
- a **hunt sugerida** para cada missão de monstro, quando a hunt atual não conta ou nada está em andamento;
- o progresso offline informado pelo jogo ao reconectar;
- um **resumo geral** (XP/h e lucro/h somados, contas caçando, missões a resgatar, reset diário) e um painel **"precisa de atenção"**: missão pronta, sequência semanal em risco, mochila ou bolsa de chaves cheia, hunt que terminou por morte/sem gold/cap cheio, conta parada na cidade e sessão aberta em outro lugar;
- a **previsão** de cada missão de monstro (kills/h dos alvos → quando conclui e se dá tempo antes do reset), a **sequência semanal**, as **metas semanais**, as chaves (com hora da próxima) e a mochila;
- **totais por dia** (XP, lucro, kills, horas caçadas por conta) e um **ranking de hunts** por mapa (XP/h, lucro/h, kills/h, mortes), com filtro por conta; só entram hunts de 5 min ou mais;
- detalhes de cada hunt encerrada (clique na linha): lucro/h e por kill, dano recebido e cura, causa da morte, monstros e drops;
- exportação em **CSV** do histórico de hunts e das amostras por minuto.

**Notificações.** O app avisa pelo macOS quando algo novo entra no painel de atenção (missão pronta, sequência em risco, mochila/chaves cheias, hunt que acabou mal). Liga e desliga em **Dashboard → Notificar eventos importantes**. É local: nada sai do Mac. Só funciona no `.app` instalado, não no `swift run`.

**Missões diárias.** Cada missão de monstro lista os mapas que têm o monstro-alvo, usando a lista pública de hunts do jogo (`https://play.tibidle.com/hunts`), a mesma que o jogo usa no botão "Explorar". O app baixa essa lista sozinho, sem cookies nem login, guarda uma cópia em `hunts-catalog.json` e atualiza a cada 12 horas. Estados exibidos: *Contando nesta hunt*, *A hunt atual não conta*, *Pendente*, *Concluída — resgate no jogo*, *Resgatada*, além de *Elite* e *Forja* (que não dependem de hunt). A regra "esta hunt conta" é inferida dos monstros do mapa; o app não consegue confirmar as regras do servidor.

**Como os dados são coletados.** Um script somente leitura (`Sources/TibidleCore/CollectorScript.swift`) roda apenas em `play.tibidle.com` e observa as mensagens que o jogo **recebe** do servidor pelo WebSocket. Ele não envia nada ao jogo, não toca nas mensagens enviadas (onde trafega a autenticação) e repassa ao app só uma lista fixa de campos de hunt e das duas missões diárias (sem calendário de login nem prêmios além do nome e da quantidade; da sequência e das metas semanais só os números de progresso); o resto, inclusive o token de sessão, é descartado. Os testes em `Tests/TibidleCoreTests/DashboardTests.swift` executam esse script e verificam isso.

**Privacidade.** A dashboard é somente leitura e não tem senha: **qualquer pessoa na mesma rede** pode ver os dados de hunt (nomes dos personagens, levels, XP, gold). Ela não expõe logins, cookies nem permite ações. Use em redes de confiança.

**Limitações.** Os dados só são registrados com o app aberto (o período fechado aparece como "progresso offline", sem detalhes). Se o jogo mudar o formato das mensagens, a coleta pode parar até ser ajustada. O histórico (amostras por minuto, guardadas por 30 dias, e hunts encerradas) fica em `dashboard.sqlite`.

Para ver a página com dados de exemplo, sem abrir o jogo: `swift run DashboardPreview preview.png` (opções `light` e `phone`).

## Dados das contas

Os dados ficam fora do repositório e do app:

```text
~/Library/Application Support/TibidleMultiManager/settings.json   # nomes, ordem, som e visualização
~/Library/Application Support/TibidleMultiManager/dashboard.sqlite # histórico da dashboard
~/Library/Application Support/TibidleMultiManager/hunts-catalog.json # cópia da lista pública de hunts
~/Library/WebKit/io.github.flvsilva.tibidle-multi-manager/        # cookies e armazenamento dos 4 perfis
```

Cada conta usa um identificador de perfil fixo (`ProfileIdentity` em `Sources/TibidleCore/Settings.swift`). Renomear ou arrastar uma aba não altera esse identificador nem transfere o login. **Não altere esses UUIDs**, ou os logins existentes deixam de ser encontrados.

O gerenciador não captura senhas. O site mantém a autenticação no perfil, como em um navegador comum. A pasta de perfis é privada e não deve ser compartilhada.

## Desenvolvimento

```sh
swift build          # compila
swift test           # configurações, abas, grade, coletor, histórico e servidor
swift run            # roda sem empacotar (prefira o .app: o bundle ID separa os perfis)
```

| Arquivo | Responsabilidade |
| --- | --- |
| `Sources/TibidleCore/Settings.swift` | Configurações, normalização e identidades dos perfis |
| `Sources/TibidleCore/TabOrder.swift` | Ordem visual |
| `Sources/TibidleCore/BrowserLayout.swift` | Tela única e grade |
| `Sources/TibidleMultiManager/MainWindowController.swift` | Janela, abas, controles |
| `Sources/TibidleMultiManager/BrowserSession.swift` | `WKWebView`, perfis, popups de login, som |
| `Sources/TibidleMultiManager/BrowserHostView.swift` | Posicionamento dos painéis |
| `Sources/TibidleMultiManager/Theme.swift` | Cores, botões e arraste das abas |
| `Sources/TibidleCore/CollectorScript.swift` | Coletor somente leitura injetado no jogo |
| `Sources/TibidleCore/DashboardStore.swift` | Estado ao vivo e histórico (SQLite) |
| `Sources/TibidleCore/DashboardServer.swift`, `DashboardRouter.swift` | Servidor HTTP da rede local |
| `Sources/TibidleCore/HuntCatalog.swift`, `HuntCatalogLoader.swift`, `MissionAdvisor.swift` | Lista de hunts e avaliação das missões diárias |
| `Sources/TibidleCore/Attention.swift` | Painel "precisa de atenção" |
| `Sources/TibidleCore/DashboardPage.swift` | Página da dashboard |
| `Sources/TibidleMultiManager/Notifier.swift` | Notificações do macOS |
| `Sources/DashboardPreview/main.swift` | Pré-visualização com dados de exemplo |
| `scripts/build-app.sh` | Gera o `.app` e o ZIP |

## Limitações

- **Som:** o WebKit não tem API pública para silenciar uma página; o app usa a SPI `_setPageMuted:`. Se uma versão futura do macOS removê-la, o botão de som fica desativado.
- **Google, Discord ou CAPTCHA:** provedores podem impor restrições a navegadores embutidos. O app se identifica como Safari e abre os popups de login no mesmo perfil da conta, mas não automatiza essas etapas.
- **Login expirou:** o servidor pode pedir login de novo mesmo com o perfil salvo.
- **Memória:** são quatro páginas do jogo abertas ao mesmo tempo.

## Licença e créditos

Código sob [MIT](LICENSE), derivado do projeto original de Windows, cujo aviso de copyright é preservado. Projeto de comunidade sem afiliação oficial com o Tibidle. Veja [os avisos de terceiros](THIRD_PARTY_NOTICES.md).
