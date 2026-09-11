#!/usr/bin/env bash
# Prepara o home do container a cada start. Idempotente: as etapas caras já
# rodaram no build, aqui só se refaz o que estiver faltando (volume de home
# recriado vazio, por exemplo).
set -euo pipefail

readonly SEED_CREDENTIALS=/seed/claude-credentials.json
readonly SEED_GITCONFIG=/seed/gitconfig
readonly SEED_TOOL_VERSIONS=/usr/local/share/claude-dev/tool-versions
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS="${CLAUDE_DIR}/settings.json"

mkdir -p "${CLAUDE_DIR}"

# Fallback de versões do asdf para o que roda fora de um projeto com
# `.tool-versions` próprio. Reescrito a cada start, e não copiado só quando
# falta: mora no volume de home, que é semeado uma única vez, então sem isto um
# `docker compose build` com o .tool-versions alterado não teria efeito.
install -m 644 "${SEED_TOOL_VERSIONS}" "${HOME}/.tool-versions"

# Configuração do git: cópia única a partir de um mount read-only, quando o
# host tiver um ~/.gitconfig. O arquivo do host nunca é escrito, e sem ele o
# container sobe igual — basta configurar `user.name`/`user.email` aqui dentro.
#
# `-s` (arquivo regular não-vazio) e não `-r`: quando o arquivo não existe no
# host, o Docker monta um *diretório* vazio no lugar, que passaria por `-r`.
if [[ ! -f "${HOME}/.gitconfig" && -s "${SEED_GITCONFIG}" ]]; then
    install -m 600 "${SEED_GITCONFIG}" "${HOME}/.gitconfig"
    echo "entrypoint: .gitconfig semeado a partir do host"
fi

# Login do Claude: mesmo esquema, e igualmente opcional. Sem o arquivo do host,
# `claude` pede login na primeira sessão e grava o token no volume.
if [[ ! -f "${CLAUDE_DIR}/.credentials.json" && -s "${SEED_CREDENTIALS}" ]]; then
    install -m 600 "${SEED_CREDENTIALS}" "${CLAUDE_DIR}/.credentials.json"
    echo "entrypoint: login do Claude semeado a partir do host"
fi

if [[ ! -x "${HOME}/.caveman/bin/caveman-proxy" ]]; then
    echo "entrypoint: baixando os binários do caveman..."
    caveman setup --install
fi

if ! grep -qs 'caveman-proxy' "${SETTINGS}"; then
    echo "entrypoint: registrando os hooks do caveman..."
    caveman setup --agent-native claude
fi

# Precisa de TTY: sem ele o prompt de patch do rtk cai no default N.
if ! grep -qs 'rtk hook claude' "${SETTINGS}"; then
    echo "entrypoint: registrando o hook do rtk..."
    printf 'y\n' | script -qec 'rtk init -g' /dev/null
    rtk telemetry disable
fi

exec "$@"
