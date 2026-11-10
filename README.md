# Geas

A personal task manager in the spirit of TickTick, synced across devices
through a private GitHub repository instead of a hosted service. Your tasks
are plain Markdown files in a repo you own.

**Runs on:** Android, macOS and Linux, plus a `geas` command-line tool.

> In Irish myth, a *geas* (also *geis*) is a binding obligation: something you
> must do, or must never do, with ruin following if you break it.

## What it does

- **Lists, tags, due dates with optional times, priorities, checklists and
  notes.** Inbox, Today and Next 7 days views.
- **Eisenhower matrix:** Do, Schedule, Delegate and Drop, one per priority.
  Drag a task between quadrants to change its priority. Tasks due soon are
  bold amber; overdue ones are red.
- **A home-screen widget on Android** with the four quadrants: tick tasks
  off without opening the app.
- **Order and package tracking:** vendor, order number and status on a task,
  packages with the carrier worked out from the tracking number and a link
  to its tracking page, and packages arriving today in Today.
- **Sync through GitHub** with a per-task merge, so edits on two devices
  combine instead of overwriting each other. When both change the same
  thing, Geas keeps the newer change and shows you the other.
- **No server and no account** beyond GitHub. Each device has its own token
  that can reach only your tasks repo.

## Install

Download the latest build from the
[Releases page](https://github.com/drlholloway/geas/releases/latest):

| Platform | File |
|---|---|
| Android | `geas-android-<version>.apk` |
| macOS (Apple silicon) | `geas-macos-<version>.zip` |
| Linux (x86-64) | `Geas-<version>-x86_64.AppImage` or `geas-linux-x64-<version>.tar.gz` |
| CLI | `geas-cli-linux-x64-<version>` or `geas-cli-macos-arm64-<version>` |

The first run walks you through creating your private tasks repo and a
GitHub token. The [wiki](https://github.com/drlholloway/geas/wiki) explains
installing on each platform, setup, and every feature.

## CLI

```sh
geas setup                        # walks through repo, token, device
geas add "Order 1N914s" -l pedals -t tayda -d "fri 5pm" -p high
geas ls --today
geas matrix                       # Do, Schedule, Delegate, Drop
geas order S13H --vendor Tayda --number TE-1234567
geas track S13H 9400111899223397846185 --eta fri
geas orders                       # by status, with tracking links
geas done S13H                    # ids are short suffixes from ls
geas edit S13H                    # the Markdown file in $EDITOR
geas --help
```

Every command syncs with GitHub first and pushes what it changed;
`--offline` works on the local copy, and the next sync sends it.

## Building from source

Needs Flutter (stable) and [just](https://github.com/casey/just).

```sh
just get          # dependencies for the whole workspace
just test         # core, CLI and app tests
just cli          # builds build/geas
just run-macos    # or run-android, run-linux
```

`TODO.md` holds the design decisions, the file format, the sync design and
the plan; `CHANGELOG.md` the release history.

## License

Copyright © 2026 Cryptid Effects (Lane Holloway). Licensed under the
PolyForm Shield License 1.0.0: you may use, copy, modify and share Geas,
but not to build a competing product. See [LICENSE](LICENSE).
