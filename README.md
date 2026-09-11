# isolated-claude-code

Template de ambiente Docker para rodar o **Claude Code** sem dar a ele acesso ao
filesystem do host, já com o ferramental de sessão (`caveman`, `rtk`) e com o
toolchain de build instalado na própria imagem via **asdf**.

**O único requisito da máquina é Docker.** Não é preciso ter asdf, JDK, Maven,
Node ou o próprio Claude Code instalados no host — nada é montado de lá além do
repositório. Quem já tiver `~/.gitconfig` e login do Claude Code no host ganha
uma cópia deles de brinde; quem não tiver sobe o container do mesmo jeito.

## Pré-requisitos

Docker e Docker Compose v2, mais duas variáveis exportadas — o
`docker-compose.yml` falha na hora nomeando a que faltar, em vez de subir um
container que só quebra depois no `mvn`:

```bash
export GITHUB_USERNAME="<user>"     # GitHub Packages (platformbuilders/ppn-shared)
export GITHUB_TOKEN="<pat>"         # idem, scope read:packages
```

O `export` vale só na sessão atual do shell; para não repetir a cada terminal,
coloque as duas linhas no `~/.bashrc`.

`UID`/`GID` são opcionais (default `1000`). Se o seu uid for outro, exporte-os:
o bind do repositório é o único ponto em que o container escreve no host, e
gravaria arquivos com dono errado.

## Uso

```bash
docker compose up -d --build            # primeira vez (~4 min: asdf, Node, Claude Code, caveman)
docker compose exec claude caveman claude
```

`caveman claude` é o comando de entrada: ele sobe o proxy do caveman em
`127.0.0.1:8787` *dentro* do container, que é para onde o `ANTHROPIC_BASE_URL`
do `~/.claude/settings.json` aponta. Chamar `claude` direto pula o caveman.

Shell sem o Claude: `docker compose exec claude bash`.

Na primeira sessão o Claude pede para confiar no diretório — e, se o host não
tinha um login para copiar, pede também para autenticar. As duas coisas ficam
gravadas no volume.

## O que é isolado

| Recurso | Comportamento |
|---|---|
| Filesystem | Só `/workspace/code`. O resto do host não existe para o container. |
| Usuário | `dev`, non-root, uid/gid espelhando o host (`UID`/`GID` como build args). |
| Toolchain (Node, e o que o `.tool-versions` mandar) | Instalado **na imagem** pelo asdf. Nada vem do host, e `asdf install` dentro do container funciona. |
| Cache Maven | Volume nomeado `maven-repo`. **Não** é bind de `~/.m2`: o preço é baixar as dependências uma vez por volume. |
| Configuração do git | `~/.gitconfig` do host montado **read-only** em `/seed/` e copiado **uma vez** pelo entrypoint. Sem o arquivo no host, o container sobe igual e você configura `user.name`/`user.email` aqui dentro. |
| Login do Claude | Mesmo esquema — atalho para quem já usa o Claude Code no host. Sem ele, `claude` pede login na primeira sessão. O arquivo do host nunca é reescrito. |
| Histórico e settings do host | **Não** entram. Os hooks do `settings.json` do host apontam para caminhos do host e quebrariam aqui — o container gera os seus no build. |
| MCPs | Só `caveman` e `caveman-cloud`, registrados no build. MCPs locais do host (IDE, por exemplo) ficam de fora. |
| `settings.xml` | `docker/maven/settings.xml` montado read-only. Sem credencial no arquivo: só `${env.GITHUB_USERNAME}`/`${env.GITHUB_TOKEN}`, resolvidos em runtime. |
| Rede | Livre, sem allowlist de egress. |

O home (`~/.claude`, `~/.caveman`, config do rtk) vive no volume nomeado
`claude-home`, então login, histórico e aprovações sobrevivem a
`docker compose down`.

### Host sem esses arquivos

Os dois mounts de `/seed/` são declarados sem condição, porque o
`required: false` do Compose só existe a partir da v2.32 e quebra a validação
nas versões anteriores. Quando o arquivo não existe no host, o Docker monta um
**diretório vazio** no lugar dele — o entrypoint ignora o que não for arquivo
regular não-vazio, então o container sobe normalmente.

O efeito colateral é do lado do host: o Docker **cria** `~/.gitconfig/` (ou
`~/.claude/.credentials.json/`) como diretório, e aí o `git config --global` da
máquina passa a falhar. Se você não tem esses arquivos, crie-os vazios antes do
primeiro `up` — o entrypoint ignora arquivo vazio do mesmo jeito:

```bash
mkdir -p ~/.claude && touch ~/.gitconfig ~/.claude/.credentials.json
```

Alternativa: apagar as duas linhas `- ${HOME}/...:/seed/...:ro` do
`docker-compose.yml`. Elas são conveniência, não requisito.

#### Se o seu Compose for v2.32+

Confira com `docker compose version`. A partir da v2.32 existe a forma longa
com `required: false` (pula o mount quando o arquivo não existe) e
`create_host_path: false` (proíbe o Docker de criar o diretório no host) —
que resolve o efeito colateral acima em vez de contorná-lo. Ela está
**comentada** no `docker-compose.yml`, logo abaixo das duas linhas em uso:
descomente os dois blocos `type: bind` e apague as duas linhas curtas.

Ficou comentada, e não como padrão, porque **versão anterior à v2.32 não a
ignora** — reprova a validação do arquivo inteiro com `additional properties
'required' not allowed` e o container não sobe. Como o template se propõe a
rodar em qualquer máquina com Docker, o default é o que funciona em todas.

## Toolchain: `.tool-versions` manda na imagem

O `.tool-versions` da raiz do repositório é a **única** declaração do toolchain.
O build o copia, instala um plugin do asdf por linha e roda `asdf install`:

```
nodejs 24.19.0
```

Node está aí porque `caveman` e `cave` são JS — e `caveman claude` é o comando de
entrada, então sem Node não há sessão. (O `claude` em si é binário nativo e o
`rtk` é um binário Rust pronto; nenhum dos dois precisa de Node.)

Para um projeto Java, acrescente as linhas e rebuilde — **nenhum arquivo do
Docker muda**:

```
nodejs 24.19.0
java corretto-21.0.12.9.1
maven 3.9.9
```

```bash
docker compose up -d --build
```

Cada JDK custa ~300 MB de imagem. Plugins que baixam binário pronto (nodejs,
java, maven) funcionam direto; plugin que **compila da fonte** (python, ruby)
precisa de `build-essential` e dos headers da lib acrescentados ao `apt-get
install` do `Dockerfile`.

Dentro do container o asdf continua utilizável: `/opt/asdf` pertence ao usuário
`dev`, então `asdf install java corretto-17.0.20.10.1` funciona para um teste
rápido. Só que `/opt/asdf` é camada de imagem, não volume — o que for instalado
assim **some quando o container é recriado**. O caminho durável é o
`.tool-versions` + rebuild.

Subprojetos com `.tool-versions` próprio continuam mandando no seu diretório; o
da raiz é o fallback, e o entrypoint o copia para `~/.tool-versions` a cada
start para que valha também fora de `/workspace`.

### `JAVA_HOME`

Não pode ser fixo na imagem porque depende do `.tool-versions` em vigor:
`/etc/profile.d/asdf-java-home.sh` o exporta via `asdf where java`, então
**shell de login** (`bash -l`, o que `docker compose exec claude bash` dá) tem
`JAVA_HOME`; `docker compose exec claude <cmd>` direto não tem. O `mvn` não
precisa dele (acha o JDK pelo `PATH`); Gradle e `quarkus dev` precisam.

## Estrutura

| Caminho | Papel |
|---|---|
| `docker-compose.yml` | Serviço `claude`: binds, volumes nomeados, variáveis obrigatórias. |
| `.tool-versions` | Toolchain da imagem e fallback de versões em runtime. |
| `docker/claude/Dockerfile` | Imagem `code/claude-dev` — asdf, toolchain, Claude Code, caveman, rtk. |
| `docker/claude/entrypoint.sh` | Provisionamento idempotente do home a cada start. |
| `docker/maven/settings.xml` | `settings.xml` do Maven, montado read-only. |
| `.mvn/maven.config`, `.mvn/rrf/` | Remote Repository Filter do Maven. |
| `.dockerignore` | O contexto de build é a raiz do repo (por causa do `.tool-versions`). |

## Adaptando o template

**Nomes.** Imagem `code/claude-dev`, container `code`, volumes
`claude-home` e `maven-repo`, e o par `working_dir` (compose) / `WORKDIR`
(Dockerfile) — estes dois são `/workspace/code` e **precisam concordar**,
assim como o bind do repositório. Rodar dois projetos em paralelo exige renomear
imagem, container e volumes.

**Toolchain.** Só o `.tool-versions`. Veja a seção acima.

**Maven.** `docker/maven/settings.xml` declara o GitHub Packages
`platformbuilders/ppn-shared`. O `.mvn/maven.config` liga o *Remote Repository
Filter* por `groupId` e `.mvn/rrf/groupId-github.txt` restringe esse repositório
aos groupIds listados (por padrão só `io.platformbuilders`), mandando o resto
direto para o Maven Central sem 404 a cada build. O filtro casa groupId
**exato**, então cada projeto acrescenta ali os seus — subgrupos como
`io.platformbuilders.<projeto>` não são cobertos pelo pai. Para levantar a lista
real de um reator, rode uma vez com
`-Daether.remoteRepositoryFilter.groupId.record=true`.

Projeto sem GitHub Packages: remova o bloco `environment` do compose, o mount do
`settings.xml` e o `.mvn/`.

## Configurações não óbvias

- **`ANTHROPIC_BASE_URL`** não está no compose: é escrito em
  `~/.claude/settings.json` pelo `caveman setup --agent-native claude` no build.
- **Fixado na imagem**: `TZ=America/Sao_Paulo`, `DISABLE_AUTOUPDATER=1` e
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`.
- **`init: true`** evita que `sleep infinity` como PID 1 deixe zumbis dos
  processos disparados pelo Claude e pelo caveman.
- **O entrypoint testa os seeds com `-s`**, e não com `-r`: o diretório vazio
  que o Docker monta quando o arquivo não existe no host passaria por `-r`.
- **O hook do rtk exige TTY**: sem ele o prompt de patch cai no default `N` e o
  hook não é gravado — daí o `script -qec` no `Dockerfile` e no entrypoint.
- **Os pacotes npm vão para `/usr/local`**, fora tanto do home quanto do
  diretório do Node instalado pelo asdf: trocar a versão do Node no
  `.tool-versions` não leva junto o Claude Code e o caveman.

## Manutenção

asdf, Claude Code e caveman têm versão fixada como `ARG` no `Dockerfile` — cada
bump é deliberado. `rtk` é a exceção: o instalador oficial não aceita versão fixa
sem `RTK_VERSION`. O toolchain dos projetos fica no `.tool-versions`.

Toolchain e binários ficam em `/opt/asdf` e `/usr/local`, fora do home, então
`docker compose build` atualiza todos eles mesmo com o volume `claude-home`
existente. O que mora no home (proxy nativo do caveman, `settings.json`) é
semeado da imagem na criação do volume. Para reprovisionar do zero, incluindo
novo login:

```bash
docker compose down -v && docker compose up -d --build
```

`down -v` também apaga o `maven-repo` — o próximo build Maven rebaixa tudo.

## Troubleshooting

**`git config --global` passou a falhar no host, dizendo que `~/.gitconfig` é um
diretório.** Você não tinha o arquivo e o Docker o criou como diretório ao
montar. `rmdir ~/.gitconfig && touch ~/.gitconfig` — veja "Host sem esses
arquivos".

**`claude` pede login.** Não havia token no host para copiar, ou o que foi
copiado expirou. Rode `claude login` *dentro* do container; fica gravado no
volume.

**`git commit` reclama de `user.email`.** O host não tinha `~/.gitconfig` para
copiar. Configure aqui dentro: `git config --global user.email ...`.

**`mvn` falha com 401 em `maven.pkg.github.com`.** `GITHUB_TOKEN` sem scope
`read:packages`, ou o container subiu antes de você exportar a variável —
`docker compose up -d --force-recreate`.

**`java`/`mvn`: command not found.** A ferramenta não está no `.tool-versions`.
Acrescente e `docker compose up -d --build`.

**Versão errada de uma ferramenta.** `asdf current` no diretório mostra de qual
`.tool-versions` cada versão veio. Diretório sem arquivo próprio cai no
`~/.tool-versions`, que o entrypoint copia da imagem a cada start.

**`asdf install` de um plugin novo falha na compilação.** O plugin compila da
fonte e faltam headers. Acrescente as dependências ao `apt-get install` do
`Dockerfile`.

**Hooks do caveman/rtk sumiram.** O entrypoint reprovisiona cada etapa que
faltar no próximo start: `docker compose restart claude` e veja os logs.

## Licença

Unlicense — domínio público. Veja [`LICENSE`](LICENSE).
