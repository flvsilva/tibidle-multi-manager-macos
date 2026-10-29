# Tibidle Multi-Manager para macOS

Aplicativo de comunidade para jogar [Tibidle](https://play.tibidle.com/) no macOS com quatro contas em uma janela. Port nativo do [Tibidle Multi-Manager para Windows](https://github.com/danbatista/tibidle-multi-manager), feito em Swift, AppKit e WebKit (`WKWebView`), sem dependências externas.

Cada pessoa entra com suas próprias contas diretamente no site do jogo. Não há assinatura nem serviço próprio do gerenciador. Código aberto sob a [licença MIT](LICENSE).

Contato: flv.silva@yahoo.com.br

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

- um cartão por conta com status (caçando, na cidade, desconectada), XP/h, lucro/h, loot, supplies, balance, dano, cura, supplies por kill, lucro por 1k XP, monstros mais abatidos e HP/mana da party, com a **parte dos supplies de cada membro** (em destaque quando um só gasta metade ou mais);
- **mesma hunt, lado a lado**: quando duas ou mais contas caçam no mesmo mapa, uma tabela compara lucro, loot, supplies, XP, kills, dano causado e recebido, cura, supplies/kill, lucro/1k XP e cura ÷ dano recebido por hora; fica em vermelho o que está 20% ou mais pior que a melhor conta (contas com menos de 10 min ficam de fora);
- o **histórico no mesmo nível**: no cartão, como as hunts encerradas de 30 min ou mais nesse mapa renderam no nível atual ±2, por conta (lucro, supplies e kills por hora), para separar "é o nível" de "é o setup";
- **comparado à sua melhor hunt recente**: no cartão, a hunt mais lucrativa da conta nesse mapa nas últimas 2 semanas (nível ±5, 30 min ou mais), o lucro/h de lá e de agora, o que mudou no setup de batalha desde então e os **supplies por hora de cada membro** agora e naquela hunt, com as mudanças de cura, poção e munição de quem passou a gastar mais; um botão abre o setup completo daquela hunt, e cada vocação pode ser salva como preset;
- o **próximo nível**: XP que falta, tempo no ritmo atual e, nas hunts que a conta fez perto desse nível, XP/h, lucro/h, tempo até subir e o gold ganho (ou gasto) até lá;
- um gráfico de **lucro por nível** em cada mapa (ou supplies, XP e kills por hora), um ponto por hunt encerrada de 30 min ou mais, com tabela;
- gráficos de XP/h e lucro/h nas últimas 1 h, 6 h, 12 h, 24 h ou 7 dias, com tabela;
- o histórico de hunts encerradas: duração, motivo (morte, cap cheio, sem gold…), level, XP, loot, supplies, balance e mortes;
- as **missões diárias** de cada conta: progresso, tempo até o reset e se a hunt atual conta ou não;
- a **hunt sugerida** para cada missão de monstro, quando a hunt atual não conta ou nada está em andamento;
- o progresso offline informado pelo jogo ao reconectar;
- um **resumo geral** (XP/h e lucro/h somados, contas caçando, missões a resgatar, reset diário) e um painel **"precisa de atenção"**: missão pronta, sequência semanal em risco, mochila ou bolsa de chaves cheia, hunt que terminou por morte/sem gold/cap cheio, conta parada na cidade e sessão aberta em outro lugar, recompensa do calendário de login a resgatar **invasão** (inscrição aberta sem você ter entrado, ou começando em até 15 min), **lucro 20% abaixo da melhor hunt recente com o setup mudado**, skill de um **elemento que os monstros resistem** (menos de 50% do dano) que ainda dispara, e membro que passa a hunt com **menos de 10% de mana**;
- a **previsão** de cada missão de monstro (kills/h dos alvos → quando conclui e se dá tempo antes do reset), a **sequência semanal**, as **metas semanais**, as chaves (com hora da próxima) e a mochila;
- **totais por dia** (XP, lucro, kills, horas caçadas por conta) e um **ranking de hunts** por mapa (XP/h, lucro/h, kills/h, mortes), com filtro por conta; só entram hunts de 5 min ou mais;
- detalhes de cada hunt encerrada (clique na linha): lucro/h e por kill, supplies/kill, lucro por 1k XP, dano recebido e cura, supplies por membro, causa da morte, monstros e drops, e o **setup da hunt**: as configurações de batalha com que ela rodou e o que mudou em relação a outra hunt (por padrão, a anterior da mesma conta no mesmo mapa). Só hunts encerradas a partir desta versão guardam o setup, que é o que o app leu ao abrir o jogo ou retomar a hunt;
- o **bestiário da hunt** atual: kills registradas no mapa, os três marcos de bônus, o tempo estimado até o próximo marco e até completar (pela taxa de kills/h da hunt em andamento; as kills da hunt atual são somadas ao contador do servidor, então é uma estimativa);
- **análise de skills** de cada personagem da party: dano estimado por skill contra os monstros da hunt (resistências do bestiário público do jogo), avisos de elemento que os alvos resistem e sugestões de troca ou adição com o ganho estimado e o custo de mana (veja abaixo);
- exportação em **CSV** do histórico de hunts e das amostras por minuto.

**Análise de skills.** O app combina três dados: as skills equipadas e seus níveis (lidos do jogo, só números e nomes de skills), as fórmulas e elementos de cada magia (`https://play.tibidle.com/spells`) e as resistências de cada monstro abatido (`/bestiary/creature`, baixadas sob demanda e guardadas em `creatures-cache.json`). Com isso ele simula a rotação da party (a primeira skill da prioridade que está pronta e atende ao mínimo de criaturas) e estima o dano por segundo. O dano exibido é uma **estimativa**: o app não conhece as regras internas do servidor.
Ele **aprende com as suas hunts**: ao fim de cada hunt iniciada com o app aberto, compara o dano previsto com o dano real informado pelo jogo (tabela `calibration` em `dashboard.sqlite`). Com 3 hunts ou mais ele escolhe o tamanho médio de pull que melhor explica o seu dano real e aplica um fator de correção; o cartão passa a mostrar "calibrado com N hunts". O app também acompanha a **mana média** de cada membro durante a hunt; quando ela fica abaixo de 25%, as sugestões que gastam mais mana vêm com um aviso, porque essa mana extra sai de poção (mais supplies) ou a skill falha. Limitações: não há dano por skill (só o total da party), o ataque da arma pode não vir nos dados (assume 40) e itens, buffs e resistências extras do jogo não entram no modelo.

**Presets de batalha.** O botão **Presets** do dashboard abre a biblioteca local de configurações de batalha: skills em ordem de prioridade, mínimo de criaturas por skill, curas, poção de mana, suportes e munição. **Salvar** guarda a configuração atual de um personagem com o nome da hunt (por exemplo "Dragon Lair · Druid"; repetições ganham "(2)"). Cada preset vira um texto compacto (`tbp1.…`, com checksum) que você copia para outro Mac ou cola em **Importar**; o conteúdo importado é higienizado e validado. **Ver passos** mostra as diferenças para a config atual da conta escolhida, avisos (skill de outra vocação ou level maior) e o passo a passo para reproduzir no jogo. O app **não aplica** nada no jogo: ele só lê a configuração. Salvar, importar, renomear e excluir só funcionam abrindo o dashboard neste Mac (`localhost`); pela rede local a biblioteca fica somente leitura. Os presets ficam em `dashboard.sqlite`. A configuração é lida quando o jogo conecta; se você mudar no jogo, recarregue a aba antes de salvar.

**Notificações.** O app avisa pelo macOS quando algo novo entra no painel de atenção (missão pronta, sequência em risco, login a resgatar, invasão, mochila/chaves cheias, hunt que acabou mal). Liga e desliga em **Dashboard → Notificar eventos importantes**. É local: nada sai do Mac. Só funciona no `.app` instalado, não no `swift run`.

**Missões diárias.** Cada missão de monstro lista os mapas que têm o monstro-alvo, usando a lista pública de hunts do jogo (`https://play.tibidle.com/hunts`), a mesma que o jogo usa no botão "Explorar". O app baixa essa lista sozinho, sem cookies nem login, guarda uma cópia em `hunts-catalog.json` e atualiza a cada 12 horas. Estados exibidos: *Contando nesta hunt*, *A hunt atual não conta*, *Pendente*, *Concluída — resgate no jogo*, *Resgatada*, além de *Elite* e *Forja* (que não dependem de hunt). A regra "esta hunt conta" é inferida dos monstros do mapa; o app não consegue confirmar as regras do servidor.

**Como os dados são coletados.** Um script somente leitura (`Sources/TibidleCore/CollectorScript.swift`) roda apenas em `play.tibidle.com` e observa as mensagens que o jogo **recebe** do servidor pelo WebSocket. Ele não envia nada ao jogo, não toca nas mensagens enviadas (onde trafega a autenticação) e repassa ao app só uma lista fixa de campos de hunt, das duas missões diárias e do horário da invasão do dia (se você está inscrito, sem prêmios) (sem calendário de login nem prêmios além do nome e da quantidade; da sequência e das metas semanais só os números de progresso); o resto, inclusive o token de sessão, é descartado. Os testes em `Tests/TibidleCoreTests/DashboardTests.swift` executam esse script e verificam isso.

**Privacidade.** A dashboard não tem senha e, pela rede, é somente leitura (a única escrita é a biblioteca de presets, aceita só de `localhost`): **qualquer pessoa na mesma rede** pode ver os dados de hunt (nomes dos personagens, levels, XP, gold). Ela não expõe logins nem cookies e não permite ações no jogo; os presets podem ser lidos (inclusive o texto deles) por quem estiver na rede. Use em redes de confiança.

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
