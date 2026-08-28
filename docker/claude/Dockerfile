# Imagem própria para rodar o Claude Code isolado do host, com o toolchain de
# build do projeto Java montado no container (JDK + Maven) e o ferramental de
# sessão (caveman, rtk).

FROM eclipse-temurin:21-jdk-noble

# Versões fixadas: a imagem é reproduzível e cada bump é deliberado.
ARG MAVEN_VERSION=3.9.9
ARG NODE_VERSION=24.19.0
ARG CLAUDE_CODE_VERSION=2.1.250
ARG CAVEMAN_VERSION=1.2.5

# Espelham o usuário do host para que o bind rw de ~/.m2/repository não troque
# o dono dos arquivos.
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git jq less procps ripgrep unzip xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Node oficial em tarball: sem repo de terceiros e com a versão exata do host.
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) node_arch=x64 ;; \
        arm64) node_arch=arm64 ;; \
        *) echo "arquitetura não suportada: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" -o /tmp/node.tar.xz; \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 --no-same-owner \
        --exclude=CHANGELOG.md --exclude=LICENSE --exclude=README.md; \
    rm /tmp/node.tar.xz; \
    node --version

# Maven do archive.apache.org (o dlcdn só mantém a release corrente).
ENV MAVEN_HOME=/opt/maven
RUN set -eux; \
    curl -fsSL "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -o /tmp/maven.tar.gz; \
    mkdir -p "${MAVEN_HOME}"; \
    tar -xzf /tmp/maven.tar.gz -C "${MAVEN_HOME}" --strip-components=1; \
    ln -s "${MAVEN_HOME}/bin/mvn" /usr/local/bin/mvn; \
    rm /tmp/maven.tar.gz; \
    mvn -v

# CLIs em /usr/local (fora do $HOME): rebuild da imagem atualiza os binários
# mesmo com o volume de home já existente.
RUN npm install -g --no-fund --no-audit \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@caveman-ai/cli@${CAVEMAN_VERSION}" \
    && npm cache clean --force

RUN RTK_INSTALL_DIR=/usr/local/bin sh -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh' \
    && rtk --version

# O base image do Ubuntu 24.04 já ocupa o uid 1000 com o usuário `ubuntu`.
RUN set -eux; \
    if existing="$(getent passwd "${UID}" | cut -d: -f1)" && [ -n "${existing}" ]; then \
        userdel -r "${existing}"; \
    fi; \
    getent group "${GID}" >/dev/null || groupadd -g "${GID}" dev; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev

# Pontos de montagem pré-criados com o dono certo: o volume nomeado de /home/dev
# é semeado a partir da imagem, e o bind aninhado de .m2/repository precisa do
# diretório pai já existente para não nascer root.
RUN install -d -o "${UID}" -g "${GID}" /home/dev/.claude /home/dev/.m2/repository /workspace

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV TZ=America/Sao_Paulo \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

USER dev
WORKDIR /workspace/pnb

# Provisiona caveman e rtk no build (o download do proxy nativo é o passo caro);
# o entrypoint só refaz cada etapa que estiver faltando.
#
# A ordem importa: `--install` só baixa os binários, `--agent-native` é quem
# escreve ~/.claude/settings.json e registra o MCP em ~/.claude.json. O rtk vem
# depois para acrescentar o hook dele ao settings.json já existente — e precisa
# de um TTY, senão o prompt de patch cai no default N e o hook não é gravado.
RUN set -eux; \
    caveman setup --install; \
    caveman setup --agent-native claude; \
    printf 'y\n' | script -qec 'rtk init -g' /dev/null; \
    rtk telemetry disable; \
    grep -q 'rtk hook claude' "${HOME}/.claude/settings.json"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
