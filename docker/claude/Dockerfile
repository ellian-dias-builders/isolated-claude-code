# Imagem autocontida para rodar o Claude Code isolado do host. Tudo que a sessão
# precisa — asdf, toolchain, Claude Code, caveman, rtk — é instalado aqui: o
# único requisito do host é Docker. Nada do filesystem do host é montado a não
# ser o próprio repositório e, quando existirem, dois arquivos de configuração
# copiados uma vez (git e login do Claude), ambos opcionais.
#
# O toolchain não é fixado neste arquivo: quem manda é o `.tool-versions` da raiz
# do repositório, copiado no build. Acrescentar `java corretto-21` ali e
# rebuildar basta — nenhuma linha daqui muda.

# Versões fixadas: a imagem é reproduzível e cada bump é deliberado.
ARG ASDF_VERSION=0.20.0
ARG CLAUDE_CODE_VERSION=2.1.267
ARG CAVEMAN_VERSION=1.3.3

FROM ubuntu:26.04

ARG ASDF_VERSION
ARG CLAUDE_CODE_VERSION
ARG CAVEMAN_VERSION

# Espelham o usuário do host para que o bind do repositório não troque o dono
# dos arquivos — é o único ponto em que o container escreve no host.
ARG UID=1000
ARG GID=1000

ENV DEBIAN_FRONTEND=noninteractive
# `gnupg` é do plugin nodejs do asdf, que verifica a assinatura dos tarballs do
# Node; sem ele o install passa, mas sem conferir nada.
#
# Só o necessário para plugins que baixam binário pronto (nodejs, java, maven).
# Plugin que compila da fonte — python, ruby — precisa de `build-essential` e
# dos headers da lib correspondente acrescentados aqui.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates curl git gnupg jq less procps ripgrep unzip xz-utils \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# asdf a partir da release oficial: binário Go estático, sem dependência do
# shell do host (as versões < 0.16 eram um script bash que exigia `source`).
RUN set -eux; \
    case "$(dpkg --print-architecture)" in \
        amd64) asdf_arch=amd64 ;; \
        arm64) asdf_arch=arm64 ;; \
        *) echo "arquitetura não suportada: $(dpkg --print-architecture)" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "https://github.com/asdf-vm/asdf/releases/download/v${ASDF_VERSION}/asdf-v${ASDF_VERSION}-linux-${asdf_arch}.tar.gz" -o /tmp/asdf.tar.gz; \
    tar -xzf /tmp/asdf.tar.gz -C /usr/local/bin asdf; \
    rm /tmp/asdf.tar.gz; \
    asdf --version

# O base image do Ubuntu já ocupa o uid 1000 com o usuário `ubuntu`.
RUN set -eux; \
    if existing="$(getent passwd "${UID}" | cut -d: -f1)" && [ -n "${existing}" ]; then \
        userdel -r "${existing}"; \
    fi; \
    getent group "${GID}" >/dev/null || groupadd -g "${GID}" dev; \
    useradd -m -u "${UID}" -g "${GID}" -s /bin/bash dev

# Pontos de montagem pré-criados com o dono certo: o volume nomeado de /home/dev
# é semeado a partir da imagem, e o volume aninhado de .m2/repository precisa do
# diretório pai já existente para não nascer root.
#
# /opt/asdf fica FORA do home de propósito: o home é semeado uma única vez, na
# criação do volume, enquanto o toolchain precisa ser atualizado por
# `docker compose build` — como já acontece com os binários de /usr/local.
RUN install -d -o "${UID}" -g "${GID}" \
        /home/dev/.claude /home/dev/.m2/repository /opt/asdf /workspace

# Os shims entram antes de /usr/local no PATH para que `node` e qualquer outra
# ferramenta do asdf resolvam pelo `.tool-versions` em vigor.
ENV ASDF_DATA_DIR=/opt/asdf \
    PATH=/opt/asdf/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Fallback de versões para o que roda fora de um projeto com `.tool-versions`
# próprio. Fica em /usr/local (fora do home) e o entrypoint o copia para
# ~/.tool-versions a cada start, senão um rebuild não alcançaria o volume.
COPY .tool-versions /usr/local/share/claude-dev/tool-versions

# O `asdf install` roda como `dev` — é quem é dono de /opt/asdf — e a partir de
# um diretório onde o `.tool-versions` seja visível, porque é assim que o asdf
# descobre o que instalar. Um plugin por linha do arquivo.
USER dev
WORKDIR /home/dev
RUN set -eux; \
    cp /usr/local/share/claude-dev/tool-versions /home/dev/.tool-versions; \
    while read -r tool _version || [ -n "${tool}" ]; do \
        [ -n "${tool}" ] || continue; \
        case "${tool}" in \#*) continue ;; esac; \
        asdf plugin add "${tool}"; \
    done < /home/dev/.tool-versions; \
    asdf install; \
    asdf current

# Os pacotes npm vão para /usr/local (fora do $HOME): rebuild da imagem atualiza
# os binários mesmo com o volume `claude-home` já existente. O `--prefix` mantém
# tudo fora do diretório do Node instalado pelo asdf, para que trocar a versão do
# Node no `.tool-versions` não leve junto o Claude Code e o caveman.
#
# Os `bin/*` são scripts `#!/usr/bin/env node` e resolvem o Node pelo shim em
# runtime, então não há versão de Node embutida neles.
USER root
RUN npm install -g --no-fund --no-audit --prefix /usr/local \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@caveman-ai/cli@${CAVEMAN_VERSION}" \
    && npm cache clean --force

# Binário Rust pronto: não precisa do toolchain de Rust nem no build nem em
# runtime. Sempre a release mais recente — o instalador oficial não aceita
# versão fixa sem RTK_VERSION.
RUN RTK_INSTALL_DIR=/usr/local/bin sh -c 'curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh' \
    && rtk --version

COPY --chmod=755 docker/claude/entrypoint.sh /usr/local/bin/entrypoint.sh

# Maven acha o JDK pelo `java` do PATH, mas ferramenta que exige JAVA_HOME
# (Gradle, Quarkus dev) não — e o valor depende do .tool-versions em vigor,
# então só um shell de login consegue resolvê-lo. Fica pronto para quando
# `java` entrar no .tool-versions; sem o plugin instalado, não faz nada.
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

USER dev
WORKDIR /workspace/code

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
