# Geas

Personal task manager in the spirit of TickTick for Android, macOS and Linux,
plus a small CLI. There is no server: tasks are Markdown files in a separate
private GitHub repo (`drlholloway/geas-data`), and every device syncs through
GitHub's REST API. Named for the Irish *geas*, a binding obligation, in the
same vein as Akashic and Ley Lines.

Read `TODO.md` first; it holds the decisions, the data format, the sync
design and the phased checklist. Tick items off there as they land, and move
anything cut from v1 to its **Later** section.

## Layout (planned)

Pub workspace, mirroring FretboardTrainer and Sightings (DC75Workbench) in
the sibling directories.

- `packages/geas_core/` — pure Dart, no Flutter: task and list models, the
  Markdown + YAML file format, three-way merge, the GitHub sync client and the
  local cache. Everything that matters lives here and is unit tested. Shared
  by the app and the CLI.
- `apps/geas_cli/` — Dart CLI (`geas`), built with `dart compile exe`.
- `apps/geas/` — Flutter app (Android, macOS, Linux). Riverpod for state,
  go_router for navigation. Renders and edits; no sync or merge logic.
- `packaging/` — Linux packaging, built in CI only (no Linux toolchain on the
  dev Mac).

## Commands (once scaffolded)

```sh
just get           # dart pub get for the workspace
just analyze       # dart analyze + flutter analyze
just test          # core tests + CLI tests + app widget tests
just cli           # compile the CLI to build/geas
just run-macos     # macOS is the dev target
just run-android
```

Shell PATH needs `/opt/homebrew/bin` for `flutter` and `just`. Run
`just analyze` and `just test` before finishing a change.

## Conventions

- American spelling in code, UI text, docs and commits.
- App id `dev.laneholloway.geas`. Linux AppImage named
  `Geas-<version>-x86_64.AppImage`, like Sightings and Fretman.
- Code and data repos stay separate. Never commit real task data or tokens
  here; tests use fixtures and an in-memory fake of the GitHub client.
- The task file format is a contract. Files must stay hand-editable, and
  parsing then writing a file must preserve unknown frontmatter keys. Bump
  `format` in `geas.yaml` for breaking changes.
- Sync never does a textual git merge. Merges happen per task in `geas_core`.
