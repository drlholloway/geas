# Changelog

All notable changes to Geas. The section for a tagged version becomes the
GitHub Release notes.

## Unreleased

## 0.1.0

The first release: the app on Android, macOS and Linux, and the `geas` CLI,
syncing through a private GitHub repo.

### Added
- **Tasks** as Markdown files with YAML frontmatter, one per task, in your
  own private repo. Files stay hand-editable; unknown keys survive.
- **Sync** through GitHub's REST API with a per-task three-way merge, never
  a textual git merge. Conflicts keep the newer change and set the other
  aside; the app's Conflicts view shows both and lets you swap them.
- **Setup** that does as much as GitHub allows: it creates the private data
  repo, opens GitHub's token form filled in (one year, Contents read and
  write, a name for this device), checks the token you paste, and stores
  it in the Keychain, the Android Keystore or the Secret Service. Geas
  warns two weeks before a token expires.
- **The app:** Inbox, Today, Next 7 days, lists and tags; quick add; a task
  sheet to edit the title, list, tags, due date and time, priority,
  checklist and notes; list and tag management. Syncs on launch, on
  resume, after edits and on demand.
- **Eisenhower matrix:** Do, Schedule, Delegate and Drop, one per priority.
  Drag a task to another quadrant to set its priority. Tasks due within two
  days (or `warn_days` in `geas.yaml`) are bold amber everywhere; overdue
  ones are red.
- **Orders and packages:** vendor, order number, status and packages on a
  task, with the carrier detected from the tracking number and a link to
  its tracking page. An Orders view, packages arriving today in Today, and
  an offer to finish the task when the order is delivered.
- **The CLI:** `geas setup`, `add`, `ls`, `show`, `done`, `edit`, `rm`,
  `lists`, `tags`, `matrix`, `order`, `track`, `orders` and `sync`, each
  syncing on its own unless given `--offline`.
