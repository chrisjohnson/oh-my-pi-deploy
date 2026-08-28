# oh-my-pi-deploy

CI-built OCI image that runs `oh-my-pi` (`omp`), packaged as a Docker Compose
service fragment for [`local-ai-machine`](https://github.com/chrisjohnson/local-ai-machine).

## What this is

`omp` is a coding-agent CLI (`@oh-my-pi/pi-coding-agent`, installed globally
via Bun). Unlike the shared-workspace agent tools in this same family (`dsh`,
`pi-web`), `omp` is deliberately scoped to **one specific project workspace**
per container: the compose service mounts `${OMP_WORK_DIR}` — e.g.
`/home/chris/turnstone-workspace/printer-dashboard` — to `/work`, not the
whole shared workspace tree. `OMP_HOME_DIR` is mounted to `/home/node/.omp`
for the agent's persistent config/state (`PI_CONFIG_DIR=.omp`, resolved as
`path.join(os.homedir(), PI_CONFIG_DIR)` by `@oh-my-pi/pi-utils/dirs`).

On first boot, `docker-entrypoint.sh` seeds (once, never overwriting a file
the user already has) two files under `$OMP_HOME_DIR/agent/`:

- `models.yml` — provider/model registry pointing at the local litellm
  instance (`http://host.docker.internal:4000/v1`), substituting the real
  `LITELLM_MASTER_KEY` into the committed `models.seed.yml.tmpl` placeholder
  at startup. Refuses to seed (exits nonzero) if `LITELLM_MASTER_KEY` isn't
  set.
- `config.yml` — model role routing, mapping omp's built-in roles (default,
  plan, commit, advisor, etc.) onto two litellm-backed roles: a fast
  `medium-moe` for interactive/fan-out work and a `big-moe` for deep
  reasoning/planning.

The entrypoint also configures git's `credential.helper` (see Credentials,
below) and an `insteadOf` rewrite so SSH-style `git@github.com:` /
`ssh://git@github.com/` remotes resolve through HTTPS, then execs the
container's real command (`omp`).

The image itself (`Dockerfile`) is `node:22-bookworm-slim` plus Bun, `git`,
`docker.io` (the container is added to the `docker` group so `omp` can drive
the host's Docker socket), and the `omp` CLI installed globally via
`bun install -g @oh-my-pi/pi-coding-agent`.

## How it's deployed

This repo publishes to `ghcr.io/chrisjohnson/oh-my-pi-deploy` on every push
(`.github/workflows/build.yml` — `docker/build-push-action`, tagged `latest`
on the default branch plus a long-sha tag on every push). It is **not** a Nix
flake itself; it's an ordinary git repo whose compose-fragment text gets
vendored into `local-ai-machine` via a Nix flake input, while the actual
container image is pulled from GHCR at the ordinary OCI layer — Nix's only
job here is pinning/copying the compose YAML.

The chain, end to end:

1. `local-ai-machine`'s `flake.nix` pins an `oh-my-pi-deploy` input to a
   specific commit of this repo.
2. `configuration.nix`'s `linkComponentCompose` activation script maintains a
   stable symlink, `/etc/local-ai-machine-components/oh-my-pi-deploy/`, that
   always points at whatever Nix store path is currently pinned.
3. `local-ai-machine`'s `docker/docker-compose.yml` pulls this repo's
   `docker-compose.yml` in via
   `include: - path: /etc/local-ai-machine-components/oh-my-pi-deploy/docker-compose.yml`.
4. The included fragment defines the `omp` service's structure (image,
   volumes, environment) but supplies no machine-specific values itself —
   those come from `local-ai-machine`'s own `docker/.env`
   (`OH_MY_PI_DEPLOY_TAG`, `OMP_WORK_DIR`, `OMP_HOME_DIR`, and the shared
   GitHub App vars below). `OH_MY_PI_DEPLOY_TAG` empty defaults to `:latest`.

To bump the pinned commit of this repo: `deploy.sh --update-input
oh-my-pi-deploy` in `local-ai-machine`, followed by a normal deploy switch.
To bump the running image tag without touching the pin: set
`OH_MY_PI_DEPLOY_TAG` in `local-ai-machine`'s `docker/.env`.

## Credentials

`dsh`, `oh-my-pi`, and `pi-web` all share **one** GitHub App installation for
git write operations performed by the tool itself while it's running (e.g.
`omp` committing/pushing code it wrote to a repo). This is a separate
credential from whatever a human or agent session uses to push changes to
*this* repo's own source (that's ordinary `gh auth`/git push, from wherever
that session is working).

The shared App's `GITHUB_APP_ID` / `GITHUB_APP_INSTALLATION_ID` are non-secret
values recorded on `local-ai-machine`'s board. The private key is
a file on the host (`GITHUB_APP_PRIVATE_KEY_HOST_PATH`, conventionally
`/home/chris/.secrets/github-app-agent-key.pem`), mounted read-only into the
container at `/run/secrets/github-app-agent-key.pem` — never committed here.
Permissions on the App installation: Contents/PRs/Actions/Workflows/Pages
read-write, Metadata read-only (GitHub's mandatory baseline).

`credential-helper/` (this repo) mints a fresh ~1h installation token on
every git operation, rather than storing a long-lived token:

- `github-app-token.mjs` — calls `@octokit/auth-app` with the App ID,
  installation ID, and private key path (all from env), returns a token.
  Never caches to disk.
- `github-app-git-credential-helper.mjs` — implements git's
  `credential.helper` protocol (`get`/`store`/`erase`); on `get`, mints a
  token via the above and prints `username=x-access-token` /
  `password=<token>`. `store`/`erase` are no-ops, since nothing is ever
  written to disk.

Unlike `dsh-deploy`, this image has no `gh` CLI at all, so there's no
background gh-auth refresh loop — only the git `credential.helper` +
`insteadOf` URL rewrite applies here.

## Relation to `local-ai-machine`

This repo is one of several extracted from `local-ai-machine`'s former
monolithic repo (alongside `dsh-deploy`, `pi-web-deploy`, and
`strix-halo-r9700-llm-builds`). `local-ai-machine` owns the machine-level
orchestration (Nix flake pin, `docker/.env` values, `deploy.sh`); this repo
owns the `omp` image and its compose-service structure. See
`local-ai-machine`'s own `AGENTS.md` for the general "component deploy
mechanism" pattern shared across all of these.
