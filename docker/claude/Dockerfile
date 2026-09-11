# Imagem para rodar o Claude Code isolado do host. O toolchain dos projetos
# (JDK, Maven, Node, Rust) *não* é instalado aqui: vem do asdf do host, montado
# read-only pelo docker-compose.yml. Na imagem ficam só a base do sistema e o
# ferramental de sessão (Claude Code, caveman, rtk).
#
# A base espelha a distro do host (Ubuntu 26.04, glibc 2.43) para que qualquer
# binário vindo do asdf rode sem surpresa — inclusive um compilado localmente,
# que exigiria a glibc do host.

# Versões fixadas: a imagem é reproduzível e cada bump é deliberado.
ARG NODE_VERSION=24.19.0
ARG CLAUDE_CODE_VERSION=2.1.267
ARG CAVEMAN_VERSION=1.3.3

# Estágio só de build: o Claude Code e o caveman são pacotes npm, então instalar
# um precisa de Node — mas *rodar* um também, e esse Node vem dos shims do asdf.
# Aqui o Node serve apenas ao `npm install` e ao download do proxy nativo do
# caveman; nada deste estágio além dos artefatos abaixo entra na imagem final.
#
# O `--prefix` isola os dois pacotes do `npm`/`corepack` que já vêm na imagem
# do Node, então a imagem final copia `/opt/cli` inteiro e não herda nenhum
# deles. `HOME` tem de ser o mesmo da imagem final: `caveman setup
# --agent-native` grava caminhos absolutos no settings.json.
FROM node:${NODE_VERSION}-slim AS cli
ARG CLAUDE_CODE_VERSION
ARG CAVEMAN_VERSION
ENV HOME=/home/dev \
    PATH=/opt/cli/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN mkdir -p "${HOME}"

RUN npm install -g --no-fund --no-audit --prefix /opt/cli \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@caveman-ai/cli@${CAVEMAN_VERSION}" \
    && npm cache clean --force

# `--install` baixa os binários (o passo caro); `--agent-native` escreve
# ~/.claude/settings.json e registra o MCP em ~/.claude.json.
RUN caveman setup --install \
    && caveman setup --agent-native claude

FROM ubuntu:26.04

# Espelham o usuário do host para que os binds rw (~/.m2/repository) não troquem
# o dono dos arquivos.
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq less procps ripgrep unzip xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# O base image do Ubuntu já ocupa o uid 1000 com o usuário `ubuntu`.
RUN set -eux; \
    if existing="$(getent passwd "${UID}" | cut -d: -f1)" && [ -n "${existing}" ]; then \
        userdel -r "${existing}"; \
    fi; \
    getent group "${GID}" >/dev/null || groupadd -g "${GID}" dev; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev

# Pontos de montagem pré-criados com o dono certo: o volume nomeado de /home/dev
# é semeado a partir da imagem, e o bind aninhado de .m2/repository precisa do
# diretório pai já existente para não nascer root. /opt/asdf recebe o bind
# read-only do asdf do host.
RUN install -d -o "${UID}" -g "${GID}" /home/dev/.claude /home/dev/.m2/repository /workspace /opt/asdf

# Os pacotes npm em /usr/local (fora do $HOME): rebuild da imagem atualiza os
# binários mesmo com o volume de home já existente. Sem o `node`/`npm` do
# estágio anterior — os `bin/*` são scripts `#!/usr/bin/env node` e resolvem o
# Node pelo shim do asdf em runtime.
#
# Copiar os diretórios (e não cada `bin/*`) preserva os symlinks relativos que
# o npm cria de `bin/` para `lib/node_modules/`; apontar para o arquivo faz o
# COPY desreferenciar o link e duplicar 200 MB.
COPY --from=cli /opt/cli/lib/node_modules /usr/local/lib/node_modules
COPY --from=cli /opt/cli/bin /usr/local/bin
# O proxy nativo do caveman e o settings.json semeados no estágio de build.
COPY --from=cli --chown=${UID}:${GID} /home/dev/ /home/dev/

# Binário Rust: não precisa de Node nem no build nem em runtime.
RUN RTK_INSTALL_DIR=/usr/local/bin sh -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh' \
    && rtk --version

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

# Maven acha o JDK pelo `java` do PATH, mas ferramenta que exige JAVA_HOME
# (Gradle, Quarkus dev) não — e o valor depende do .tool-versions em vigor,
# então só um shell de login consegue resolvê-lo.
RUN printf '%s\n' \
    '# JAVA_HOME conforme o .tool-versions do diretório atual (asdf).' \
    'if command -v asdf >/dev/null 2>&1; then' \
    '    _asdf_java_home="$(asdf where java 2>/dev/null)" \' \
    '        && export JAVA_HOME="${_asdf_java_home}"' \
    '    unset _asdf_java_home' \
    'fi' \
    > /etc/profile.d/asdf-java-home.sh

ENV TZ=America/Sao_Paulo \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

# ASDF_DATA_DIR aponta para o bind read-only declarado no docker-compose.yml
# (mudar um exige mudar o outro). Os shims entram antes de /usr/local no PATH
# para que `node`, `java`, `mvn` e `cargo` resolvam pelas versões do
# .tool-versions em vez das da imagem.
ENV ASDF_DATA_DIR=/opt/asdf \
    PATH=/opt/asdf/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

USER dev
WORKDIR /workspace/pnb-code

# O hook do rtk é acrescentado ao settings.json que veio do estágio de build —
# e precisa de um TTY, senão o prompt de patch cai no default N e o hook não é
# gravado. O entrypoint refaz esta etapa se ela faltar.
RUN set -eux; \
    printf 'y\n' | script -qec 'rtk init -g' /dev/null; \
    rtk telemetry disable; \
    grep -q 'rtk hook claude' "${HOME}/.claude/settings.json"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
