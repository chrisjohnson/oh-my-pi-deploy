# Contributing

Direct pushes to `main` are the established workflow for this repo — no PR
requirement. CI (`.github/workflows/build.yml`) builds and publishes the
image to GHCR on every push.

See `AGENTS.md` for what does and doesn't need Chris's confirmation before
you act (in short: routine work proceeds and gets recorded; deviating from
the standard deploy mechanism needs a flag + confirm first).

## Fleet board

This repo has a `.fleet/board/` (backlog/now/blocked/done), following
`local-ai-machine`'s own fleet conventions for claim/signal/decision-log
discipline. If you're an agent picking up work here, check the board first.
