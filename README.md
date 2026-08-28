# isolated-claude-code

Template de ambiente Docker para rodar o **Claude Code** sem dar a ele acesso ao
filesystem do host, já com toolchain Java (JDK 21 + Maven), o ferramental de
sessão (`caveman`, `rtk`) e as convenções da Platform Builders (MCP
`buildersos` + subagents).

## Pré-requisitos

Docker + Compose, e três variáveis exportadas no host — o `docker-compose.yml`
falha na hora nomeando a que faltar, em vez de subir um container que só quebra
depois no `mvn`:

```bash
export BUILDERSOS_TOKEN="<token>"   # MCP buildersos
export GITHUB_USERNAME="<user>"     # GitHub Packages (platformbuilders/ppn-shared)
export GITHUB_TOKEN="<pat>"         # idem, scope read:packages
```

O `export` vale só na sessão atual do shell; para não repetir a cada terminal,
coloque as três linhas no `~/.bashrc`.

`UID`/`GID` são opcionais (default `1000`). Se o seu uid for outro, exporte-os:
o bind rw de `~/.m2/repository` é compartilhado com o host e gravaria arquivos
com dono errado.

O token do buildersOS vem do instalador, rodado na raiz do repositório:

```bash
curl -fsSL https://os-api.platformbuilders.io/install.sh | bash \
  && . "$HOME/.config/buildersos/env"
```

Ele escreve `~/.config/buildersos/env` (fonte do `export` acima),
`.buildersos/.env` e `.claude/settings.local.json`. Os dois últimos ficam no
repositório, carregam o token e são gitignored — nunca commite nenhum deles.

## Uso

```bash
docker compose up -d --build            # primeira vez (~5 min: JDK, Maven, Node, caveman)
docker compose exec claude caveman claude
```

`caveman claude` é o comando de entrada: ele sobe o proxy do caveman em
`127.0.0.1:8787` *dentro* do container, que é para onde o `ANTHROPIC_BASE_URL`
do `~/.claude/settings.json` aponta. Chamar `claude` direto pula o caveman.

Shell sem o Claude: `docker compose exec claude bash`.

Na primeira sessão o Claude pede para confiar no diretório; a aprovação fica
gravada no volume.

## O que é isolado

| Recurso | Comportamento |
|---|---|
| Filesystem | Só `/workspace/pnb`. O resto do host não existe para o container. |
| Usuário | `dev`, non-root, uid/gid espelhando o host (`UID`/`GID` como build args). |
| Login do Claude | `~/.claude/.credentials.json` montado **read-only** em `/seed/` e copiado **uma vez** pelo entrypoint. O arquivo do host nunca é reescrito. |
| Histórico e settings do host | **Não** entram. Os hooks do `settings.json` do host apontam para caminhos do host e quebrariam aqui — o container gera os seus no build. |
| MCPs | `buildersos` vem do `.mcp.json` do repo; `caveman` e `caveman-cloud` são registrados no build. MCPs locais do host (IDE, por exemplo) ficam de fora. |
| Cache Maven | **Bind rw** de `~/.m2/repository` — compartilhado com o host de propósito, para não rebaixar o repositório inteiro. |
| `settings.xml` | `docker/maven/settings.xml` montado read-only. Sem credencial no arquivo: só `${env.GITHUB_USERNAME}`/`${env.GITHUB_TOKEN}`, resolvidos em runtime. |
| Rede | Livre, sem allowlist de egress. |

O restante do home (`~/.claude`, `~/.caveman`, config do rtk) vive no volume
nomeado `claude-home`, então login, histórico e aprovações sobrevivem a
`docker compose down`.

## Estrutura

| Caminho | Papel |
|---|---|
| `docker-compose.yml` | Serviço `claude`: binds, volume de home, variáveis obrigatórias. |
| `docker/claude/Dockerfile` | Imagem `pnb/claude-dev` — JDK 21, Maven, Node, Claude Code, caveman, rtk. |
| `docker/claude/entrypoint.sh` | Provisionamento idempotente do home a cada start. |
| `docker/maven/settings.xml` | `settings.xml` do Maven, montado read-only. |
| `.mvn/maven.config`, `.mvn/rrf/` | Remote Repository Filter do Maven. |
| `.mcp.json`, `CLAUDE.md`, `.claude/agents/` | Integração com o buildersOS. |

## Adaptando o template

**Nomes.** Imagem `pnb/claude-dev`, container `pnb-claude`, volume
`claude-home` e o par `working_dir` (compose) / `WORKDIR` (Dockerfile), ambos
`/workspace/pnb` — precisam concordar. Rodar dois projetos em paralelo exige
renomeá-los.

**Maven.** `docker/maven/settings.xml` declara o GitHub Packages
`platformbuilders/ppn-shared`. O `.mvn/maven.config` liga o *Remote Repository
Filter* por `groupId` e `.mvn/rrf/groupId-github.txt` restringe esse repositório
aos groupIds listados (por padrão só `io.platformbuilders`), mandando o resto
direto para o Maven Central sem 404 a cada build. O filtro casa groupId
**exato**, então cada projeto acrescenta ali os seus — subgrupos como
`io.platformbuilders.<projeto>` não são cobertos pelo pai. Para levantar a lista
real de um reator, rode uma vez com
`-Daether.remoteRepositoryFilter.groupId.record=true`.

**buildersOS.** O `CLAUDE.md` obriga o Claude a chamar a tool MCP
`route_request` antes de qualquer tarefa e a tratar o retorno (persona, skills,
diretivas, delegação) como autoritativo. Os 27 arquivos em `.claude/agents/` são
cascas: cada um só chama `load_agent(...)` no servidor e falha fechado se ele
não responder. O bloco entre `# >>> buildersos >>>` e `# <<< buildersos <<<` no
`CLAUDE.md` é gerenciado pelo instalador — edite fora dos marcadores.

## Configurações não óbvias

- **`BUILDERSOS_PROJECT_SLUG`** é interpolado pelo `.mcp.json` mas **não** está
  no `environment` do compose: vem do `.claude/settings.local.json`, que fica
  dentro do bind do repositório. Sem esse arquivo, o header `x-project-slug` vai
  vazio.
- **`.buildersos/.env` não é lido por nada** em runtime — o compose não faz
  `env_file` dele e a URL do `.mcp.json` está fixa. É estado do instalador.
- **`ANTHROPIC_BASE_URL`** não está no compose: é escrito em
  `~/.claude/settings.json` pelo `caveman setup --agent-native claude` no build.
- **Fixado na imagem**: `TZ=America/Sao_Paulo`, `DISABLE_AUTOUPDATER=1` e
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- **`init: true`** evita que `sleep infinity` como PID 1 deixe zumbis dos
  processos disparados pelo Claude e pelo caveman.

## Manutenção

Maven, Node, Claude Code e caveman têm versão fixada como `ARG` no `Dockerfile`
— cada bump é deliberado. `rtk` é a exceção: o instalador oficial não aceita
versão fixa sem `RTK_VERSION`.

Os binários ficam em `/usr/local`, fora do home, então `docker compose build`
atualiza Claude Code, caveman e rtk mesmo com o volume `claude-home` existente.
O que mora no home (proxy nativo do caveman, `settings.json`) é semeado da
imagem na criação do volume. Para reprovisionar do zero, incluindo novo login:

```bash
docker compose down -v && docker compose up -d --build
```

## Troubleshooting

**`claude` pede login.** O token copiado expirou. Rode `claude login` *dentro*
do container, ou `docker compose down -v` para re-semear a partir do host.

**`mvn` falha com 401 em `maven.pkg.github.com`.** `GITHUB_TOKEN` sem scope
`read:packages`, ou o container subiu antes de você exportar a variável —
`docker compose up -d --force-recreate`.

**Hooks do caveman/rtk sumiram.** O entrypoint reprovisiona cada etapa que
faltar no próximo start: `docker compose restart claude` e veja os logs.

## Licença

Unlicense — domínio público. Veja [`LICENSE`](LICENSE).
