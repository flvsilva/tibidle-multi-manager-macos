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

## Dados das contas

Os dados ficam fora do repositório e do app:

```text
~/Library/Application Support/TibidleMultiManager/settings.json   # nomes, ordem, som e visualização
~/Library/WebKit/io.github.flvsilva.tibidle-multi-manager/        # cookies e armazenamento dos 4 perfis
```

Cada conta usa um identificador de perfil fixo (`ProfileIdentity` em `Sources/TibidleCore/Settings.swift`). Renomear ou arrastar uma aba não altera esse identificador nem transfere o login. **Não altere esses UUIDs**, ou os logins existentes deixam de ser encontrados.

O gerenciador não captura senhas. O site mantém a autenticação no perfil, como em um navegador comum. A pasta de perfis é privada e não deve ser compartilhada.

## Desenvolvimento

```sh
swift build          # compila
swift test           # testes de configurações, ordem das abas e grade
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
| `scripts/build-app.sh` | Gera o `.app` e o ZIP |

## Limitações

- **Som:** o WebKit não tem API pública para silenciar uma página; o app usa a SPI `_setPageMuted:`. Se uma versão futura do macOS removê-la, o botão de som fica desativado.
- **Google, Discord ou CAPTCHA:** provedores podem impor restrições a navegadores embutidos. O app se identifica como Safari e abre os popups de login no mesmo perfil da conta, mas não automatiza essas etapas.
- **Login expirou:** o servidor pode pedir login de novo mesmo com o perfil salvo.
- **Memória:** são quatro páginas do jogo abertas ao mesmo tempo.

## Licença e créditos

Código sob [MIT](LICENSE), derivado do projeto original de Windows, cujo aviso de copyright é preservado. Projeto de comunidade sem afiliação oficial com o Tibidle. Veja [os avisos de terceiros](THIRD_PARTY_NOTICES.md).
