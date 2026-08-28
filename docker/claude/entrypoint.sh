#!/usr/bin/env bash
# Prepara o home do container a cada start. Idempotente: as etapas caras já
# rodaram no build, aqui só se refaz o que estiver faltando (volume de home
# recriado vazio, por exemplo).
set -euo pipefail

readonly SEED_CREDENTIALS=/seed/claude-credentials.json
readonly CLAUDE_DIR="${HOME}/.claude"
readonly SETTINGS="${CLAUDE_DIR}/settings.json"

mkdir -p "${CLAUDE_DIR}"

# Login do Claude: cópia única a partir de um mount read-only. O ~/.claude do
# host nunca é escrito, e nem o histórico nem os hooks dele (que apontam para
# caminhos do host) entram no container.
if [[ ! -f "${CLAUDE_DIR}/.credentials.json" && -r "${SEED_CREDENTIALS}" ]]; then
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
