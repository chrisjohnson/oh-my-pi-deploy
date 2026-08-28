#!/bin/sh
# Seed oh-my-pi's model config ONCE, only if it doesn't already exist — same
# non-stomping convention as pi-web/docker-entrypoint.sh (which seeds pi-web's
# models.json at $PI_CODING_AGENT_DIR). omp reads its provider registry from
# $PI_CONFIG_DIR/agent/models.yml (YAML preferred; .yaml fallback; a legacy
# models.json at the same path is auto-migrated to YAML on first load), so this
# seeds the native YAML path. Unlike pi-web, omp has no in-session Models panel
# that writes this same file, but the seed-once convention is kept anyway: omp's
# /models and plugin flows both mutate config under the agent dir, and a config
# the user deliberately edited should not be resurrected on every restart.
#
# Guard is deliberately stricter than "does models.yml exist": seeding a fresh
# models.yml when the user already has models.yaml (the fallback) or a legacy
# models.json would create a higher-precedence file that silently shadows what
# they configured. Skip seeding if any of the three exists.
set -e

# PI_CONFIG_DIR is a directory NAME joined under $HOME (default ".omp"), per
# omp's own resolution (path.join(os.homedir(), PI_CONFIG_DIR) in
# @oh-my-pi/pi-utils/dirs). An absolute value is honored as-is for completeness.
if [ -z "$PI_CONFIG_DIR" ]; then
  CONFIG_ROOT="$HOME/.omp"
elif [ "${PI_CONFIG_DIR#/}" != "$PI_CONFIG_DIR" ]; then
  CONFIG_ROOT="$PI_CONFIG_DIR"
else
  CONFIG_ROOT="$HOME/$PI_CONFIG_DIR"
fi
MODELS_DIR="$CONFIG_ROOT/agent"

mkdir -p "$MODELS_DIR"

if [ ! -f "$MODELS_DIR/models.yml" ] && [ ! -f "$MODELS_DIR/models.yaml" ] && [ ! -f "$MODELS_DIR/models.json" ]; then
  if [ -z "$LITELLM_MASTER_KEY" ]; then
    echo "LITELLM_MASTER_KEY is not set - refusing to seed models.yml with no way to authenticate to litellm." >&2
    exit 1
  fi
  # Substitute the real key at startup - the committed template has a
  # placeholder, never a real secret (docker/.env, read at runtime only).
  sed "s/__LITELLM_MASTER_KEY__/$LITELLM_MASTER_KEY/" /app/.omp/agent/models.seed.yml.tmpl > "$MODELS_DIR/models.yml"
fi

# Same seed-once convention for settings (model role routing). config.yml is
# plain (no secret substitution needed). If the user already has one, leave it —
# omp itself may have written or been pointed at a customized version.
if [ ! -f "$MODELS_DIR/config.yml" ]; then
  cp /app/.omp/agent/config.yml "$MODELS_DIR/config.yml"
fi

# GitHub App credential (replaces the raw chris_github_key SSH
# mount) — same mechanism as dsh-deploy's entrypoint: a git
# credential.helper mints a fresh installation token per operation, and
# an insteadOf rule rewrites SSH-style GitHub URLs to HTTPS first (the
# helper only ever applies to HTTPS remotes). Unlike dsh-deploy, there's
# no gh CLI in this image at all, so no gh-auth background refresh loop —
# nothing to authenticate.
if [ -n "$GITHUB_APP_ID" ]; then
  git config --global credential.helper "/app/credential-helper/github-app-git-credential-helper.mjs"
  # url.<base>.insteadOf is multi-valued in git, and this whole block runs
  # on EVERY container start against a git config that PERSISTS across
  # restarts (bind-mounted home dir) — a plain (non---add) `git config`
  # call only overwrites cleanly the very first time; once the key holds
  # more than one value (exactly what the two lines below produce), a
  # later plain call refuses outright ("cannot overwrite multiple values
  # with a single value"), and blind --add on every restart would pile up
  # a fresh duplicate pair each time instead. Confirmed live: this
  # crash-looped the container after its second-ever restart. --unset-all
  # first guarantees a clean slate before either --add, regardless of how
  # many times this has already run.
  git config --global --unset-all url."https://github.com/".insteadOf 2>/dev/null || true
  git config --global --add url."https://github.com/".insteadOf "git@github.com:"
  git config --global --add url."https://github.com/".insteadOf "ssh://git@github.com/"
fi

exec "$@"
