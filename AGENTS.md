# AGENTS.md — oh-my-pi-deploy

## What this repo is

The Docker image and Compose service fragment for `omp` (`oh-my-pi`), one of
`local-ai-machine`'s coding-agent tools — the one deliberately scoped to a
single project workspace rather than the shared workspace `dsh`/`pi-web` use.
See `README.md` for the full picture of what the image does and how the
pieces (`Dockerfile`, `docker-compose.yml`, `docker-entrypoint.sh`,
`credential-helper/`) fit together.

## Deploy mechanism

This repo is vendored into `local-ai-machine` as a read-only Nix flake input
— `local-ai-machine` pins a commit of this repo, and a `configuration.nix`
activation script (`linkComponentCompose`) maintains a stable symlink at
`/etc/local-ai-machine-components/oh-my-pi-deploy/` pointing at whatever Nix
store path is currently pinned. `local-ai-machine`'s own
`docker/docker-compose.yml` pulls this repo's `docker-compose.yml` in via
`include:`. Nix's role is limited to vendoring the compose YAML text — the
actual container image is an ordinary OCI pull from GHCR
(`ghcr.io/chrisjohnson/oh-my-pi-deploy`), published by this repo's own CI
(`.github/workflows/build.yml`) on every push.

To bump the pinned commit: `deploy.sh --update-input oh-my-pi-deploy` in
`local-ai-machine`, then a normal deploy switch. To bump the running image
tag without touching the pin: `OH_MY_PI_DEPLOY_TAG` in `local-ai-machine`'s
`docker/.env` (empty defaults to `:latest`). See `local-ai-machine`'s own
`AGENTS.md` "component deploy mechanism" section for the pattern shared
across all of these vendored-component repos.

## Credentials

`dsh`, `oh-my-pi`, and `pi-web` share one GitHub App installation for git
write operations the tool itself performs while running (e.g. `omp`
committing/pushing code it wrote). `GITHUB_APP_ID` /
`GITHUB_APP_INSTALLATION_ID` are non-secret (real values recorded on
`local-ai-machine`'s board); the private key is a host file
(`GITHUB_APP_PRIVATE_KEY_HOST_PATH`, `/home/chris/.secrets/github-app-agent-key.pem`
by convention), mounted read-only, never committed. Permissions:
Contents/PRs/Actions/Workflows/Pages read-write, Metadata read-only.

`credential-helper/` in this repo mints a fresh ~1h installation token per
git operation (see `README.md` Credentials section for the two-file
breakdown). This is a separate credential from whatever a human/agent
session pushing changes to *this* repo's own source uses — that's normal
`gh auth`/git push from wherever the session is working.

## Git workflow

**Direct pushes to `main` are explicitly authorized in this repo** — no PR
workflow, no worktree-branch requirement, same as `local-ai-machine` itself.
CI (`.github/workflows/build.yml`) builds and publishes the image to GHCR on
every push to any branch, tagging `latest` on the default branch.

## If the standard deploy path itself is broken, or is repeatedly getting in the way

Sidestepping it is a legitimate thing to do — but flag it and confirm with
Chris first rather than silently improvising a different mechanism, same as
`local-ai-machine`'s own rule.
