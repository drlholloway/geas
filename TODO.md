# Geas TODO

Plan and status. Check items off as they land; move anything cut from v1 to
**Later**.

## Decisions (2026-11-08)

- **Platforms:** Android, macOS, Linux from one Flutter codebase, plus a
  simple Dart CLI.
- **v1 scope:** lists, categorization (tags), due dates, priorities,
  checklists, an Eisenhower matrix view, and order and package tracking
  (added 2026-11-09; these two matter most). No reminders or recurrence
  yet.
- **Data:** separate private repo `drlholloway/geas-data`, one Markdown file
  per task.
- **Sync:** GitHub's REST Git Data API on every platform, no git client.
  Merges are done per task in `geas_core`, never by git.
- **Local cache:** plain files mirroring the data repo, plus an in-memory
  index. Move to SQLite only if this gets slow.
- **Auth:** fine-grained personal access token limited to `geas-data`, with
  Contents read/write.
- **Eisenhower matrix (2026-11-09):** each quadrant is one priority level,
  as in TickTick: high is Do, medium is Schedule, low is Delegate and none
  is Drop. Dragging a task to another quadrant sets its priority. Due dates
  don't move tasks between quadrants, but a task close to its due date is
  shown bold and in a warning color, and an overdue task in the error
  color.
- **Package tracking (2026-11-09):** status is set by hand. The app and CLI
  link to each carrier's tracking page; live lookups are in Later.
- **Setup (2026-11-09):** a guided wizard, the same in the CLI
  (`geas setup`) and the app's first run. It creates the private data repo
  (with `gh` if installed, otherwise a filled-in github.com/new form), then
  opens GitHub's fine-grained token form filled in with the name,
  Contents read and write, and a 366-day expiry. GitHub has no API for
  creating these tokens and can't pre-select the repo, so picking the repo
  and clicking Generate stay manual. Each device gets its own token, which
  is checked before it's saved; Geas warns two weeks before it expires.
  Signing in through a registered GitHub App is in Later.

- **Categorization (2026-11-20):** tags, plus folders. A folder groups
  lists, saved filters and Health trackers; a thing is in at most one
  folder. Folders nest (2026-11-22): a folder's optional `parent` names
  the folder it's inside. Membership is an optional `folder` key
  on each member, so moving one thing edits one file and two devices
  filing different things never collide. Something filed in a folder that
  no longer exists counts as in none.

## Data format

```
geas-data/
  geas.yaml                 format: 1
  dismissed.yaml            reminders acknowledged on any device
  lists/<id>.yaml           id, name, color, order; optional folder, and
                            sort: manual
  filters/<id>.yaml         a saved search: id, name, query, order
  folders/<id>.yaml         a folder: id, name, order; optional parent
  trackers/<id>.md          a medication or sensor and every time it was logged
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
repeat: weekly                 # optional: daily | weekdays | weekly |
                               # monthly | yearly | 2w, 10d, 3m...
position: 2048                 # optional: its place in a list sorted by
                               # hand, lowest first
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

Order tracking is an optional `order` map in the task frontmatter. It is a
new optional key, not a breaking change, so `format` stays 1 and older
builds keep it as an unknown key:

```yaml
order:
  vendor: Tayda
  number: TE-1234567
  url: https://www.taydaelectronics.com/sales/order/view/order_id/1234567/
  status: shipped              # ordered | shipped | out-for-delivery |
                               # delivered | problem | returned
  packages:
    - carrier: usps            # usps | ups | fedex | dhl | gofo |
                               # amazon | other
      tracking: 9400111899223397846185
      eta: 2026-11-14
      status: in-transit       # optional, per package
```

Health tracking is one file per thing tracked, `trackers/<id>.md`:
frontmatter, then a list item for each time it was taken or replaced. A new
directory that older builds leave alone, so `format` stays 1:

```markdown
---
id: cgm-sensor                 # a slug, like a list id
name: CGM sensor
kind: sensor                   # med (the default) | sensor
every: 10d                     # optional: 12h, 10d, 2w; next is due this
order: 2                       # long after the last
unit: mg                       # optional: what doses are measured in
dose: 500                      # optional: the usual amount, in that unit
---
- 2026-10-26T09:05:00-05:00
- 2026-11-04T09:05:00-06:00 the old one fell off early
- 2026-11-15T08:02:11-06:00 500mg with dinner
```

Each entry is a local time with its offset, then an optional note. With a
`unit`, a first word that is a number followed by that unit (`500mg`) is
the entry's amount. Seconds
and the offset may be left out when writing one by hand. Lines that aren't
entries are kept as notes.

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
- Trackers: the frontmatter merges key by key (the remote wins a collision)
  and the log merges as a set of lines, so times logged on two devices are
  all kept and never conflict.

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
- [x] Fine-grained token: only `geas-data`, Contents read/write (checked
      on GitHub, 2026-11-20)
- [x] Pub workspace mirroring FretboardTrainer: root `pubspec.yaml`
      workspace, `packages/geas_core`, `apps/geas_cli`
- [x] `apps/geas` via
      `flutter create --org dev.laneholloway --platforms=android,macos,linux`,
      added to the workspace and to `just analyze` / `just test`
- [x] `analysis_options.yaml`, `justfile`, Dart entries in `.gitignore`
- [x] Install `just` (`brew install just`)
- [x] GitHub Actions: analyze and test on push to main and on PRs, plus
      Linux release and Android debug builds

## Phase 1: Core model and format (`geas_core`)

- [x] ULID generation and short-ID resolution
- [x] `Task`, `TaskList`, `Priority` and `Due` (date or date-time) models
- [x] Markdown + YAML frontmatter parse and write, with round-trip tests that
      cover unknown keys and hand-edited files. Rewrites go through
      `yaml_edit` and touch only changed fields, so comments, key order and
      unknown keys survive and git diffs stay minimal
- [x] Checklist parsing and toggling in the body
- [x] Built-in `inbox` list
- [x] Queries: by list, by tag, today, overdue, next 7 days, completed.
      Default sort is due date, then priority.
- [x] Archive step: tasks completed more than 30 days ago move to
      `archive/<yyyy>/` (`taskPath`, `archiveMoves`; the store applies them
      in Phase 2)

## Phase 2: Sync (`geas_core`)

- [x] Local store: `working/` and `base/` directories, base SHA, in-memory
      index, atomic writes (`DirectoryStore`, `Workspace`; `MemoryStore` for
      tests)
- [x] Three-way task merge, line merge for the body, conflict records, with
      thorough unit tests. Frontmatter merges key by key, unknown keys
      included. One-for-one line changes merge line by line, so checking
      off neighboring checklist items on two devices doesn't conflict
- [x] Repo bootstrap: `initDataRepo` writes `geas.yaml` (`format: 1`) through
      the Contents API, leaves an initialized repo alone, tolerates another
      device initializing first, and refuses a newer format
- [x] GitHub client on `package:http` for refs, trees, blobs and commits,
      behind the `GitHubClient` interface. `FakeGitHubClient` is an
      in-memory git server (blobs, trees, commits, fast-forward-only branch)
- [x] Sync loop with retry on non-fast-forward, tested by simulating two
      devices against the fake. Only blobs whose SHA differs from base are
      downloaded; edits made during a sync are kept for the next one
- [x] Try sync against the real `geas-data` repo (2026-11-09, with the `gh`
      login token): init, two simulated devices merging concurrent edits,
      a delete, and a stale push refused as non-fast-forward
- [x] Token storage interface (`TokenStore`); the per-platform
      implementations land with the CLI (Keychain, `secret-tool`) and the
      app (`flutter_secure_storage`)

## Phase 3: CLI (`apps/geas_cli`)

The CLI comes first because it is the quickest way to exercise core and sync
end to end.

- [x] `geas init <owner/repo>` bootstraps the data repo (token from
      `GEAS_TOKEN` or a hidden prompt)
- [x] `geas init` remembers the repo and device in
      `~/.config/geas/config.yaml` and stores an entered token; the local
      copy lives in `~/.local/share/geas/<owner>/<repo>` (XDG overrides
      honored)
- [x] `geas add "title" [-l list] [-t tag]... [-d due] [-p priority]`
- [x] `geas ls [-l list] [-t tag] [--today|--overdue|--week] [--done]`
      (`--today` and `--week` include overdue)
- [x] `geas show <id>`, `geas done <id>... [--undo]`, `geas rm <id>...`
- [x] `geas edit <id>`: opens the task file in `$VISUAL`/`$EDITOR` and
      validates it on save; an invalid edit can be retried or is kept
- [x] `geas lists` (add, rename, rm, which moves its tasks to the inbox) and
      `geas tags`
- [x] `geas sync`; other commands sync automatically, and `--offline` skips
      it. Unreachable GitHub only warns; the local copy is used and changes
      go out with the next sync
- [x] Due parsing (`parseDueInput` in core, for the app too): `today`,
      `tomorrow`, weekday names, `YYYY-MM-DD`, optional `HH:MM` or `5pm`.
      Times are stored with the device's offset
- [x] Token from `GEAS_TOKEN`, otherwise the macOS Keychain (`security -i`,
      so the token never appears in the process list) or Linux `secret-tool`
- [x] Tried live against `geas-data` (2026-11-09): init, add, ls, show,
      edit, done, rm, sync
- [x] `geas setup`: the guided wizard (see Decisions). Links come from
      `newRepoUrl` and `newTokenUrl` in core, and the token check from
      `GitHubClient.checkAccess`, so the app reuses them. `geas init` stays
      for scripts with `GEAS_TOKEN`
- [x] Token expiry reminder two weeks ahead, from GitHub's
      `GitHub-Authentication-Token-Expiration` header
- [x] `just cli` builds `build/geas` with `dart compile exe`

## Phase 4: App (`apps/geas`)

- [x] First run and settings: the same three steps as `geas setup` (device
      name, data repo, token), opening the `newRepoUrl` and `newTokenUrl`
      forms, checking the token with `checkTokenAccess`, storing it with
      `flutter_secure_storage`, then `initDataRepo`. Replacing an expiring
      token and disconnecting from settings. On macOS the token goes in the
      legacy Keychain (`usesDataProtectionKeychain: false`), so the app
      needs no Keychain Sharing entitlement or provisioning profile
- [x] Sidebar: Inbox, Today, Next 7 days, lists, tags
- [x] Task list grouped into Overdue, Today, Upcoming and No date, with
      priority marks, a quick-add field and a collapsed Completed section
- [x] Task detail: title, list, tags, due date with optional time, priority,
      checklist (tick, add, remove), notes (the whole body as Markdown), and
      delete; every change saves as it's made
- [x] List and tag management: add a list from the sidebar (name and
      color), edit or delete it from its screen (its tasks move to the
      Inbox; the Inbox can be renamed but not deleted), and rename or
      remove a tag across every task. `newList` and `replaceTag` are in core,
      and `geas lists add` uses `newList`
- [x] Conflicts view: each conflict sync resolved, with the kept and
      set-aside values of the fields that collided and the full set-aside
      file. Use the set-aside version (or, for an edit that beat a deletion,
      delete it after all), or keep what sync kept. Reached from the sidebar
      and settings
- [x] Sync on launch, on resume, 5 seconds after edits, and on demand;
      the last sync status, conflicts and an expiring token show at the
      foot of the sidebar
- [x] Background sync on Android (2026-11-18): WorkManager, through the
      `workmanager` plugin, runs a sync about every 30 minutes while
      there's a network, with the app closed, and redraws the home-screen
      widget. A running app is asked to sync itself instead, so two syncs
      never work on the same files. Scheduled on every launch
- [x] A sync lock (`SyncLock`): the app, the widget's background work
      and the periodic sync run in separate isolates, so each takes a
      named port before syncing and the others wait. A lock left by an
      isolate Android killed is taken over
- [x] macOS `com.apple.security.network.client` entitlement in both Debug
      and Release; Android `INTERNET` permission in the main manifest
- [x] Phone layout on Android, sidebar layout at desktop widths (drawer
      below 720 px)

## Phase 5: Eisenhower matrix and order tracking

Matrix:

- [x] Core: quadrant for a priority and back (high: Do, medium: Schedule,
      low: Delegate, none: Drop), and a due-date warning level for each open
      task (none, approaching, overdue), with tests
- [x] Warning window: a task is approaching when it's due within 2 days,
      the number of days set by an optional `warn_days` in `geas.yaml`
- [x] App: a Matrix view in the sidebar with the four quadrants, in a 2x2
      grid at desktop widths and stacked or paged on a phone. Dragging a
      task to another quadrant sets its priority
- [x] App: approaching tasks are bold and in a warning color, overdue ones in
      the error color, in the matrix and in every other task list
- [x] Matrix layout switch: all four quadrants on one screen, or one at a
      time as tabs, at any width (it starts from the width; the choice
      lasts while the app runs)
- [x] Matrix filters: by list and tag, and whether to include tasks with no
      due date
- [x] CLI: `geas matrix` prints the four quadrants (`-l`, `-t`,
      `--no-undated`)
- [x] Android home-screen widget: the four quadrants with counts and
      their tasks, due-date colors worked out on the device each half hour.
      A quadrant title opens the Matrix, a task opens its sheet, and a
      checkbox finishes it: handed to the app if it's running, else done in
      a background Dart isolate that syncs (Glance, through home_widget)

Orders and packages:

- [x] Core: `Order` and `Package` models parsed from and written to the
      `order` frontmatter map, round-tripping like the other fields
- [x] Core: carrier detection from the tracking number's shape (USPS, UPS
      `1Z…`, FedEx, DHL) and a tracking-page URL for each carrier.
      International postal numbers such as `LA…CN` go to USPS, and
      YunExpress `YT…` numbers to GOFO, which delivers them (2026-11-17).
      Amazon's `TBA…` numbers open on track.amazon.com (2026-11-20)
- [x] Core: queries for open orders grouped by status, and arriving today
      or this week by `eta`
- [x] App: an Orders view in the sidebar grouped into Ordered, Shipped, Out
      for delivery, Problem and Delivered (collapsed), with vendor, order
      number, carrier, ETA and buttons that open the tracking pages
- [x] App: add an order from the Orders view (a button when there are
      none, a + when there are): what's coming, vendor, order number and an
      optional tracking number make a new inbox task, which opens
- [x] App: an order section in task detail to set the vendor, order number
      and status, and to add or remove packages (paste a tracking number to
      add one)
- [x] Marking an order delivered offers to complete the task. A task with
      packages still in transit shows that on its row
- [x] CLI: `geas order <id> --vendor --number --status`,
      `geas track <id> <tracking-number> [--carrier]` and `geas orders`
- [x] Packages arriving today show in the Today view

## Phase 6: Packaging

- [x] App icon: a check pressed into an amber wax seal, drawn by
      `packaging/icon/make_icon.py`; `just icons` regenerates the Android
      and macOS icon sets
- [x] Android: release APK for sideloading, signed with the key in the
      `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
      `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` secrets (debug-signed
      until they're set; locally, `android/key.properties`)
- [x] macOS: release `.app`, ad hoc signed and zipped
- [x] Linux: `Geas-<version>-x86_64.AppImage` plus `.zsync` and a tarball,
      built in CI like Sightings and Fretman. The token store needs
      `libsecret-1-0` and a keyring at run time (CI builds with
      `libsecret-1-dev`)
- [x] CLI binaries for Linux x86-64 and macOS arm64 on each release
- [x] `CHANGELOG.md` and `.github/workflows/release.yml`: a `vX.Y.Z` tag
      matching `apps/geas/pubspec.yaml` builds everything and publishes a
      GitHub Release with the version's CHANGELOG section; pull requests
      that touch packaging build without publishing
- [x] Android release key and its four repository secrets (the keystore
      and its passwords are in `~/Documents/Geas-android-signing/`)
- [x] Public repo, PolyForm Shield license, and a wiki on installing and
      using Geas
- [x] Tag `v0.1.0`
- [x] Tag `v0.2.0`: the Android matrix widget, About, the new icon
- [x] Tag `v0.3.0`: Health tracking, international postal and GOFO
      tracking numbers
- [x] Tag `v0.4.0`: recurring tasks, quick add, search and filters,
      reminders, dose amounts, the Health widget, background sync
- [x] Tag `v0.5.0`: folders, Amazon tracking numbers
- [x] Tag `v0.6.0`: hand-sorted lists, nested folders, desktop sync
      while closed, reminder time and dismissals

## Phase 7: Health tracking (2026-11-15)

Logging each time a medication is taken or a CGM sensor is replaced, to see
how often.

- [x] Core: `Tracker` and `TrackerEntry`, the `trackers/<id>.md` format
      (round-tripping unknown keys like tasks and lists), `newTracker`, and
      a set merge of the log in `mergeTrees`
- [x] Core: `TrackerStats` (last logged, today, per day over 7 and 30 days,
      average time between, next due from `every`), `dailyCounts`,
      `entryGaps` and `parseLogTime`
- [x] App: a Health view in the sidebar with a card per tracker: when it
      was last logged, how often, a bar for each of the last 14 days for a
      medication or the day of wear for a sensor, and a Take or Replace
      button that logs now, with undo. The sidebar counts trackers past due
- [x] App: a tracker's own screen with a bar per day (30 for a medication,
      90 for a sensor), every time logged with the time since the one
      before, removing a time, logging an earlier time, editing and
      stopping tracking
- [x] CLI: `geas health` (`show`, `add`, `rm`) and `geas log <name>
      [--at] [--note] [--undo]`, also as `geas take`
- [x] Reordering: drag a card by its handle in the Health view, or
      `geas health move <name> <position>`; `moveTracker` in core
      renumbers `order`
- [x] Wiki: a Health page, its commands and file format, and redrawn
      screenshots (`just screenshots` draws `health`, `health-tracker`
      and `phone-health`)

## Phase 8: 0.4.0

- [x] Recurring tasks: an optional `repeat` key (`Repeat` in core).
      Finishing one (`completeTask`) completes it and adds a new task with
      the same title, list, tags, priority and notes, the checklist
      unticked, due on the next date after today, counted from the due
      date. The finished one stops repeating. A Repeat chip in the task
      sheet, the repeat on each row, and `geas add -r`

- [x] Quick-add syntax, shared by the app and CLI (`parseQuickAdd` in
      core): `#tag`, `^list`, `!high` / `!med` / `!low` (or `!!!`, `!!`,
      `!`), and a date at the very end (`tomorrow`, `fri 5pm`). Anything
      it doesn't recognize stays in the title. The app's add field uses it
      over the view's defaults; `geas add` does unless given `--plain`,
      and its options win

- [x] Search and saved filters. `TaskQuery` in core reads one line:
      words (in the title or notes), `#tag`, `^list`, `!high`,
      `due:today|week|overdue|none|any` and `is:done|all`. A Search view in
      the app; a search saved as a filter is `filters/<id>.yaml`
      (`SavedFilter`), merges key by key like a list, and gets a sidebar
      entry with its count. `geas find` (`--save`, `-f`) and
      `geas filters`

- [x] Background sync settings: a per-device switch and interval
      (15 minutes to 4 hours) in Settings, kept in the device's
      `config.json`. Android reschedules or cancels its WorkManager job
      (`BackgroundScheduler`). On every platform the open app also syncs
      on a timer at that interval, which is what macOS and Linux get:
      nothing there syncs while Geas is closed

- [x] Reminders as local notifications (`flutter_local_notifications`),
      off until turned on in Settings, which asks the system's permission;
      the switch is per device (`config.json`). `upcomingReminders` in
      core picks the next 48: each open task at its due time, or at 9:00
      on its due date, and each tracker with an `every` when its next is
      due. The app sets them again whenever tasks or trackers change, and
      so do background sync and the widget's checkbox. Android and macOS
      hold the schedule, so they arrive with Geas closed; Android's are
      inexact (within a few minutes) to avoid the exact-alarm permission.
      Linux has no scheduler, so there they show only while Geas is open

- [x] Health: dose amounts. A tracker can have a `unit` and a usual
      `dose`; each entry then carries an amount (`500mg`), the usual one
      unless another is given. Cards, the chart and `geas health` total the
      amount per day in place of counting times; "A different amount" in
      the app and `geas log --amount`
- [x] Health on the Android home screen: a second widget (`HealthWidget`,
      Glance) with each tracker's last time and next due, by the clock so
      they don't go stale, overdue in amber, and a Take or Replace button
      that logs now: handed to the app if it's running, else logged and
      synced in a background isolate (`logFromWidget`)

- [x] Undo on the Health widget: for two minutes after a log made there,
      its button reads Undo and takes that log back (`geas://unlog/<id>`,
      `Tracker.withoutRecent`). An Undo still showing after that only
      redraws
- [x] Reopening a finished repeating task (`reopenTask`) deletes the next
      one it made, if that's still open under the same title, and gives the
      repeat back

- [x] Folders (`Folder` in core, `folders/<id>.yaml`): a `folder` key on
      lists, saved filters and trackers. The sidebar shows each folder as
      a collapsible section with its lists and filters; Health groups its
      trackers under folder headings, and dragging reorders within a
      folder. "Move to folder" on a list's, filter's and tracker's menu
      (with a new folder made on the spot); rename and delete on the
      folder's. Deleting a folder frees what was in it. `geas folders`
      (`add`, `rename`, `rm`, `put`, `take`)

## Phase 9: after 0.5.0

- [x] Manual ordering within a list: a list with `sort: manual` shows its
      open tasks in one flat list, ordered by each task's `position`, and
      dragging a row reorders it. Positions are handed out 1024 apart, so
      a move usually rewrites one task file (`moveInManualOrder`); when
      there's no room it renumbers the list. New tasks go on top; tasks
      with no position yet follow the placed ones in due order. "Sort by
      hand" in the list's menu, `geas lists sort` and `geas move`

- [x] Folders, the rest. Nesting: an optional `parent` key; `folderTree`
      flattens the tree, and a parent that's missing or would make a loop
      leaves the folder at the top. Deleting a folder moves what was in
      it, folders included, up one level. "Move into folder" on a folder's
      menu. Reordering: "Reorder folders" opens the folders at that level
      to drag into order. Collapsed folders are remembered per device in
      `config.json`. `geas folders nest`, `unnest` and `move`

- [x] Syncing on macOS and Linux while Geas is closed. Geas started
      with `--background-sync` shows no window, syncs once and quits
      (`runDesktopBackgroundSync`): unless a window is open (it holds
      `app.lock`), syncing on its own is off, or the last run was within
      the device's interval; it gives up after 90 seconds. macOS: a launch
      agent inside the app bundle, turned on through SMAppService, which
      works for the sandboxed, ad hoc signed app (tried 2026-11-22); it
      fires every 15 minutes and needs macOS 13. Linux: a systemd user
      timer whose units are rewritten on each launch
      (`LinuxSystemdScheduler`), not yet tried on a real Linux desktop.
      Only release builds schedule themselves

- [x] Reminders, the rest. A per-device time for tasks with no time
      (`reminder_minutes` in `config.json`, a time picker in Settings).
      Dismissals: tapping a reminder records it in `dismissed.yaml`
      (`Dismissals`: reminder key to the time of the latest one
      dismissed; sync pools both sides, the later winning) and opens the
      task or tracker; each device, when it next sets its reminders, takes
      down notifications that no longer stand (`standingReminders`): the
      task was finished, the dose logged, or another device dismissed it.
      Linux while closed: the app asks systemd to start it with no window
      when the next reminder is due (`LinuxReminderWake`, a one-off
      `geas-reminder` timer), and each start shows what came due since the
      last; not yet tried on a real Linux desktop

## Later

- GitLab, and self-hosted servers for both (asked for 2026-11-23). The
  data repo can live on any of four: github.com, a GitHub Enterprise
  Server, gitlab.com, or a self-hosted GitLab.
  - Setup asks which host, and for a self-hosted one its address. The
    config keeps the kind (`github` | `gitlab`) and the base URL beside
    the repo; devices already set up read as github.com.
  - GitHub Enterprise Server is the smaller half: `HttpGitHubClient`
    already takes an `apiBase` (`https://<host>/api/v3` there), and
    `newRepoUrl` and `newTokenUrl` need the host. Older servers have no
    fine-grained tokens, so setup has to accept a classic one and say
    which scope it needs.
  - GitLab needs its own client behind the same interface, which wants a
    more neutral name than `GitHubClient`. Reading maps across: the
    branch head, the recursive tree (paged) and blobs by SHA, which are
    the same git hashes. Writing doesn't: GitLab has no blob, tree and
    commit calls, only one commit call that takes a list of file actions,
    so the sync loop's push step has to go through the interface as "this
    commit on top of that head", not as three calls.
  - To settle first: how to refuse a push when another device got there
    first. GitHub does it with a non-forced ref update; GitLab's commit
    call has to be checked for an equivalent before the design is fixed,
    since sync depends on it.
  - Tokens: a GitLab project access token (or a personal one) with the
    `api` scope, or `read_repository` and `write_repository` if those
    turn out to be enough. The setup links and the expiry warning need
    GitLab's forms and its way of reporting expiry.
  - The CLI's `geas setup` and `geas init` take the same host choice, and
    `gh` is only offered for GitHub hosts.

- Reminders: a Dismiss button on the notification itself (today only a
  tap counts; swiping one away isn't reported to apps), and clearing
  notifications on Linux
- Calendar view
- Sign in through a registered Geas GitHub App (device flow): no token to
  copy, but an app to register and tokens to refresh every 8 hours
- Habits and Pomodoro
- OAuth device flow instead of a pasted token
- Live package status pulled from carriers or a tracking aggregator,
  filling in `status` and `eta` automatically. With no server, each device
  would call the APIs itself: UPS, FedEx and USPS each need a developer
  account and OAuth keys, and an aggregator such as 17TRACK or AfterShip
  needs one key but costs money above a free tier. The key would be stored
  like the GitHub token
- Adding orders from shipping-confirmation emails
