# isolated-claude-code

Template de ambiente Docker para rodar o **Claude Code** sem dar a ele acesso ao
filesystem do host, já com o ferramental de sessão (`caveman`, `rtk`) e com o
toolchain de build (JDK, Maven, Node, Rust) vindo do **asdf do host** — a imagem
não instala nenhum deles.

## Pré-requisitos

Docker + Compose, o asdf instalado no host (`~/.asdf` e o binário
`/usr/bin/asdf`) e duas variáveis exportadas — o `docker-compose.yml` falha na
hora nomeando a que faltar, em vez de subir um container que só quebra depois no
`mvn`:

```bash
export GITHUB_USERNAME="<user>"     # GitHub Packages (platformbuilders/ppn-shared)
export GITHUB_TOKEN="<pat>"         # idem, scope read:packages
```

O `export` vale só na sessão atual do shell; para não repetir a cada terminal,
coloque as duas linhas no `~/.bashrc`.

`UID`/`GID` são opcionais (default `1000`). Se o seu uid for outro, exporte-os:
o bind rw de `~/.m2/repository` é compartilhado com o host e gravaria arquivos
com dono errado.

## Uso

```bash
docker compose up -d --build            # primeira vez (~2 min: Claude Code, caveman, rtk)
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
| Filesystem | Só `/workspace/pnb-code`. O resto do host não existe para o container. |
| Usuário | `dev`, non-root, uid/gid espelhando o host (`UID`/`GID` como build args). |
| Login do Claude | `~/.claude/.credentials.json` montado **read-only** em `/seed/` e copiado **uma vez** pelo entrypoint. O arquivo do host nunca é reescrito. |
| `~/.gitconfig` | Mesmo esquema: montado read-only em `/seed/gitconfig` e copiado uma vez. O arquivo do host nunca é reescrito. |
| Histórico e settings do host | **Não** entram. Os hooks do `settings.json` do host apontam para caminhos do host e quebrariam aqui — o container gera os seus no build. |
| MCPs | Só `caveman` e `caveman-cloud`, registrados no build. MCPs locais do host (IDE, por exemplo) ficam de fora. |
| Cache Maven | **Bind rw** de `~/.m2/repository` — compartilhado com o host de propósito, para não rebaixar o repositório inteiro. |
| Toolchain (JDK, Maven, Node, Rust) | **Bind ro** de `~/.asdf` em `/opt/asdf`, mais o binário `/usr/bin/asdf`. Compartilhado com o host de propósito: o container usa o que já está instalado e não pode instalar nem apagar ferramenta. |
| `settings.xml` | `docker/maven/settings.xml` montado read-only. Sem credencial no arquivo: só `${env.GITHUB_USERNAME}`/`${env.GITHUB_TOKEN}`, resolvidos em runtime. |
| Rede | Livre, sem allowlist de egress. |

O restante do home (`~/.claude`, `~/.caveman`, config do rtk) vive no volume
nomeado `claude-home`, então login, histórico e aprovações sobrevivem a
`docker compose down`.

## Toolchain: asdf do host, não da imagem

Instalar JDK e Maven em cada imagem era trabalho repetido e travava o container
em *uma* versão de cada. Em vez disso o `~/.asdf` do host entra read-only em
`/opt/asdf` (`ASDF_DATA_DIR`, fixado no `Dockerfile`) e `/opt/asdf/shims` vem
**antes** de `/usr/local` no `PATH`. `node`, `java`, `mvn` e `cargo` resolvem
pelo `.tool-versions` do diretório em que o comando roda, com fallback no
`~/.tool-versions` do host (montado em `/home/dev/.tool-versions`) — de graça
para um reator multi-módulo em que cada projeto pede um JDK diferente.

`JAVA_HOME` não pode ser fixo na imagem porque depende do `.tool-versions` em
vigor: `/etc/profile.d/asdf-java-home.sh` o exporta via `asdf where java`, então
**shell de login** (`bash -l`, o que `docker compose exec claude bash` dá) tem
`JAVA_HOME`; `docker compose exec claude <cmd>` direto não tem. O `mvn` não
precisa dele (acha o JDK pelo `PATH`); Gradle e `quarkus dev` precisam.

A base da imagem é `ubuntu:26.04`, espelhando a distro do host: binário do asdf
compilado localmente exige a glibc do host (2.43), e uma base mais velha o
recusaria. **Ao adaptar o template, case a base com a distro do seu host.**

### Node só no estágio de build

O Claude Code e o caveman são pacotes npm, então instalar um precisa de Node —
mas a imagem final não carrega Node por isso. O `Dockerfile` tem um estágio
`cli` (`FROM node:${NODE_VERSION}-slim`) que roda o `npm install -g --prefix
/opt/cli` e o `caveman setup --install`; a imagem final copia só `/opt/cli` e o
`/home/dev` semeado, sem `node`, `npm` nem `corepack`. O `rtk` é binário Rust e
nem no build precisa de Node.

A cópia é de **diretório** (`/opt/cli/bin`, `/opt/cli/lib/node_modules`) de
propósito: apontar o `COPY` para cada arquivo de `bin/` desreferencia os
symlinks que o npm cria e duplica 200 MB. E o `HOME` do estágio `cli` é
`/home/dev`, igual ao da imagem final, porque `caveman setup --agent-native`
grava caminhos absolutos no `settings.json`.

Em runtime o Node vem do shim do asdf. O `claude` em si é binário nativo e roda
sem ele, mas `caveman` e `cave` são JS — e `caveman claude` é o comando de
entrada, então **sem o mount do asdf não há sessão**.

## Estrutura

| Caminho | Papel |
|---|---|
| `docker-compose.yml` | Serviço `claude`: binds, volume de home, variáveis obrigatórias. |
| `docker/claude/Dockerfile` | Imagem `pnb-logger/claude-dev` — base do sistema, Claude Code, caveman, rtk. |
| `docker/claude/entrypoint.sh` | Provisionamento idempotente do home a cada start. |
| `docker/maven/settings.xml` | `settings.xml` do Maven, montado read-only. |
| `.mvn/maven.config`, `.mvn/rrf/` | Remote Repository Filter do Maven. |

## Adaptando o template

**Nomes.** Imagem `pnb-logger/claude-dev`, container `pnb-code`, volume
`claude-home` e o par `working_dir` (compose) / `WORKDIR` (Dockerfile) — estes
dois são `/workspace/pnb-code` e **precisam concordar**, assim como o bind do
repositório. Rodar dois projetos em paralelo exige renomear imagem, container e
volume.

**asdf.** O mount `${HOME}/.asdf:/opt/asdf:ro` casa com `ASDF_DATA_DIR` no
`Dockerfile` — mudar um exige mudar o outro. O binário vem de `/usr/bin/asdf`;
se no seu host ele estiver em outro caminho, ajuste o bind.

**Maven.** `docker/maven/settings.xml` declara o GitHub Packages
`platformbuilders/ppn-shared`. O `.mvn/maven.config` liga o *Remote Repository
Filter* por `groupId` e `.mvn/rrf/groupId-github.txt` restringe esse repositório
aos groupIds listados (por padrão só `io.platformbuilders`), mandando o resto
direto para o Maven Central sem 404 a cada build. O filtro casa groupId
**exato**, então cada projeto acrescenta ali os seus — subgrupos como
`io.platformbuilders.<projeto>` não são cobertos pelo pai. Para levantar a lista
real de um reator, rode uma vez com
`-Daether.remoteRepositoryFilter.groupId.record=true`.

## Configurações não óbvias

- **`ANTHROPIC_BASE_URL`** não está no compose: é escrito em
  `~/.claude/settings.json` pelo `caveman setup --agent-native claude` no build.
- **Fixado na imagem**: `TZ=America/Sao_Paulo`, `DISABLE_AUTOUPDATER=1` e
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- **`init: true`** evita que `sleep infinity` como PID 1 deixe zumbis dos
  processos disparados pelo Claude e pelo caveman.
- **O hook do rtk exige TTY**: sem ele o prompt de patch cai no default `N` e o
  hook não é gravado — daí o `script -qec` no `Dockerfile` e no entrypoint.

## Manutenção

Node (só do estágio de build), Claude Code e caveman têm versão fixada como
`ARG` no `Dockerfile` — cada bump é deliberado. `rtk` é a exceção: o instalador
oficial não aceita versão fixa sem `RTK_VERSION`. JDK, Maven, Node e Rust dos
projetos não são versionados aqui: quem manda é o asdf do host, com `asdf
install` rodado **no host** (o bind é read-only) — a ferramenta nova aparece no
container na hora, sem rebuild.

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

**`env: 'node': No such file or directory` ao rodar `caveman`.** O bind do asdf
não subiu, ou o `.tool-versions` do diretório não declara `nodejs` e o
`~/.tool-versions` do host também não. Não há Node na imagem — é de propósito.

**`java`/`mvn`/`cargo`: command not found.** O bind do asdf não subiu — o host
não tem `~/.asdf` ou `/usr/bin/asdf` onde o `docker-compose.yml` espera. Confira
com `docker compose exec claude asdf current`.

**`asdf install` falha com read-only filesystem.** É o desenhado: ferramenta se
instala no host. Para deixar o container instalar também, troque o bind
`${HOME}/.asdf:/opt/asdf:ro` para `rw` — aí ele passa a poder mexer no toolchain
inteiro do host.

**Versão errada de java em um projeto.** `asdf current` no diretório mostra de
qual `.tool-versions` cada versão veio. Projeto sem arquivo próprio cai no
`~/.tool-versions` do host.

**Hooks do caveman/rtk sumiram.** O entrypoint reprovisiona cada etapa que
faltar no próximo start: `docker compose restart claude` e veja os logs.

## Licença

Unlicense — domínio público. Veja [`LICENSE`](LICENSE).
