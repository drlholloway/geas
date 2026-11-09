# Geas TODO

Plan and status. Check items off as they land; move anything cut from v1 to
**Later**.

## Decisions (2026-11-08)

- **Platforms:** Android, macOS, Linux from one Flutter codebase, plus a
  simple Dart CLI.
- **v1 scope:** lists, categorization (tags), due dates, priorities,
  checklists. No reminders or recurrence yet.
- **Data:** separate private repo `drlholloway/geas-data`, one Markdown file
  per task.
- **Sync:** GitHub's REST Git Data API on every platform, no git client.
  Merges are done per task in `geas_core`, never by git.
- **Local cache:** plain files mirroring the data repo, plus an in-memory
  index. Move to SQLite only if this gets slow.
- **Auth:** fine-grained personal access token limited to `geas-data`, with
  Contents read/write.

## Data format

```
geas-data/
  geas.yaml                 format: 1
  lists/<id>.yaml           id, name, color, order
  tasks/<id>.md             open and recently completed tasks
  archive/<yyyy>/<id>.md    tasks completed more than 30 days ago
```

Task file:

```markdown
---
id: 01JC8ZQ4R7ME2X5Y9V3T6N0B4K
title: Order 1N914s
list: inbox                    # list id; inbox is built in
tags: [tayda, pedals]
due: 2026-11-12                # or 2026-11-12T09:00-06:00 with a time
priority: high                 # none | low | medium | high
created: 2026-11-08T23:41:02Z
updated: 2026-11-08T23:41:02Z
completed: null                # UTC timestamp once done
---
Notes go here as Markdown.

- [ ] check Tayda stock
- [x] pick pots
```

Rules:

- IDs are ULIDs and double as the filename. Merging and lookups key on the
  id, never the path, because archiving moves files.
- Short IDs in the CLI and UI come from the end of the ULID. The leading
  characters are a timestamp, so tasks created together share them.
- Unknown frontmatter keys survive a parse and rewrite, so hand edits and
  newer app versions don't lose data.
- The checklist is the Markdown checkboxes in the body.

## Merge and sync

Each device keeps `base/` (the data as of the last successful sync, plus that
commit's SHA) and `working/` (base plus local edits).

Merge per task, three-way against base:

- Changed on one side only: take that side.
- Same field changed on both sides to different values: conflict. Keep the
  version with the newer `updated` as the live value, and record the other
  for the conflicts view.
- Body (notes and checklist): line-based three-way merge. Overlapping edits
  are a conflict, handled as above.
- Edited on one side, deleted on the other: keep the edited version and flag
  it.

Sync loop:

1. `GET /repos/{owner}/{repo}/git/ref/heads/main`.
2. If the remote head differs from the base SHA, fetch the remote tree
   (`?recursive=1`), compare blob SHAs with base, fetch the changed blobs and
   merge them into working.
3. If there is anything to push, create blobs, then a tree on top of the
   remote tree (deletions are entries with `sha: null`), then a commit whose
   parent is the remote head, then `PATCH` the ref with `force: false`.
   Commit message: `sync(<device>): 2 updated, 1 added`.
4. A 422 on the ref update means another device pushed first. Go back to
   step 1, retry a few times, then report the failure.
5. On success, working becomes the new base.

The Git Data API refuses writes to an empty repo, so `geas init` creates
`geas.yaml` with the Contents API first.

## Phase 0: Setup

- [x] Private code repo `drlholloway/geas` with an initial commit
- [x] Private data repo `drlholloway/geas-data`, left empty (`geas init`
      bootstraps it)
- [ ] Fine-grained token: only `geas-data`, Contents read/write
- [x] Pub workspace mirroring FretboardTrainer: root `pubspec.yaml`
      workspace, `packages/geas_core`, `apps/geas_cli`
- [ ] `apps/geas` via
      `flutter create --org dev.laneholloway --platforms=android,macos,linux`,
      added to the workspace and to `just analyze` / `just test`
- [x] `analysis_options.yaml`, `justfile`, Dart entries in `.gitignore`
- [x] Install `just` (`brew install just`)
- [ ] GitHub Actions: analyze and test on push

## Phase 1: Core model and format (`geas_core`)

- [ ] ULID generation and short-ID resolution
- [ ] `Task`, `TaskList`, `Priority` and `Due` (date or date-time) models
- [ ] Markdown + YAML frontmatter parse and write, with round-trip tests that
      cover unknown keys and hand-edited files
- [ ] Checklist parsing and toggling in the body
- [ ] Built-in `inbox` list
- [ ] Queries: by list, by tag, today, overdue, next 7 days, completed.
      Default sort is due date, then priority.
- [ ] Archive step: tasks completed more than 30 days ago move to
      `archive/<yyyy>/`

## Phase 2: Sync (`geas_core`)

- [ ] Local store: `working/` and `base/` directories, base SHA, in-memory
      index, atomic writes
- [ ] Three-way task merge, line merge for the body, conflict records, with
      thorough unit tests
- [x] Repo bootstrap: `initDataRepo` writes `geas.yaml` (`format: 1`) through
      the Contents API, leaves an initialized repo alone, tolerates another
      device initializing first, and refuses a newer format
- [ ] GitHub client on `package:http` for refs, trees, blobs and commits
      (Contents read and create are done), behind the `GitHubClient`
      interface with `FakeGitHubClient` for tests
- [ ] Sync loop with retry on non-fast-forward, tested by simulating two
      devices against the fake
- [ ] Token storage interface, implemented per platform by the app and CLI

## Phase 3: CLI (`apps/geas_cli`)

The CLI comes first because it is the quickest way to exercise core and sync
end to end.

- [x] `geas init <owner/repo>` bootstraps the data repo (token from
      `GEAS_TOKEN` or a hidden prompt)
- [ ] `geas init` remembers the repo and stores the token
- [ ] `geas add "title" [-l list] [-t tag]... [-d due] [-p priority]`
- [ ] `geas ls [-l list] [-t tag] [--today|--overdue|--week] [--done]`
- [ ] `geas show <id>`, `geas done <id>`, `geas rm <id>`
- [ ] `geas edit <id>`: opens the task file in `$EDITOR` and validates it on
      save
- [ ] `geas lists` (add, rename, remove) and `geas tags`
- [ ] `geas sync`; other commands sync automatically, and `--offline` skips it
- [ ] Due parsing: `today`, `tomorrow`, weekday names, `YYYY-MM-DD`, optional
      `HH:MM`
- [ ] Token from `GEAS_TOKEN`, otherwise the macOS Keychain (`security`) or
      Linux `secret-tool`
- [ ] `just cli` builds `build/geas` with `dart compile exe`

## Phase 4: App (`apps/geas`)

- [ ] First run and settings: data repo, token (`flutter_secure_storage`),
      device name. Calls `initDataRepo` once the repo and token are entered,
      like `geas init`
- [ ] Sidebar: Inbox, Today, Next 7 days, lists, tags
- [ ] Task list grouped into Overdue, Today, Upcoming and No date, with
      priority marks, a quick-add field and a collapsed Completed section
- [ ] Task detail: title, list, tags, due date with optional time, priority,
      checklist, notes
- [ ] List and tag management
- [ ] Conflicts view
- [ ] Sync on launch, on resume, about 5 seconds after edits, and on demand;
      show the last sync status
- [ ] macOS `com.apple.security.network.client` entitlement in both Debug
      and Release; Android `INTERNET` permission in the main manifest
- [ ] Phone layout on Android, sidebar layout at desktop widths

## Phase 5: Packaging

- [ ] Android: signed release APK for sideloading
- [ ] macOS: release `.app`
- [ ] Linux: `Geas-<version>-x86_64.AppImage` plus `.zsync`, built in CI like
      Sightings and Fretman
- [ ] `CHANGELOG.md` and tagged releases

## Later

- Reminders as local notifications on each device. Dismissals sync, so a
  device that hasn't synced yet may still fire one.
- Recurring tasks (RRULE)
- Background sync on Android (WorkManager)
- Quick-add syntax shared by app and CLI (`#tag`, `^list`, `!high`,
  `tomorrow`)
- Calendar view
- Habits and Pomodoro
- Search and saved filters
- Folders that group lists
- Manual ordering within a list
- OAuth device flow instead of a pasted token

## Open questions

- "Categorization" is planned as tags. If it should mean folders that group
  lists, pull that up from Later.
