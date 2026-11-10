# Geas

A personal task manager in the spirit of TickTick, synced across devices
through a private GitHub repository instead of a hosted service.

**Targets:** Android, macOS, Linux.

> In Irish myth, a *geas* (also *geis*) is a binding obligation: something you
> must do, or must never do, with ruin following if you break it.

## Status

The core (task format, merge, sync) and the `geas` CLI work. The app sets
itself up the same way as `geas setup`, syncs, adds, edits and deletes
tasks, manages lists and tags, shows sync conflicts, has an Eisenhower
matrix, and tracks orders and packages; packaging is next. See
`TODO.md` for the plan.

## CLI

```sh
just cli                                # builds build/geas
build/geas setup                        # walks through repo, token, device
build/geas add "Order 1N914s" -l pedals -t tayda -d "fri 5pm" -p high
build/geas ls --today
build/geas matrix                       # Do, Schedule, Delegate, Drop
build/geas order S13H --vendor Tayda --number TE-1234567
build/geas track S13H 9400111899223397846185 --eta fri
build/geas orders                       # by status, with tracking links
build/geas done S13H                    # ids are short suffixes from ls
build/geas edit S13H                    # the Markdown file in $EDITOR
build/geas --help
```

`geas setup` creates the private data repo (using `gh` if it's installed),
opens GitHub's token form with everything filled in except the repo, checks
the token you paste, and stores it in the Keychain or Secret Service. Run it
on each device, and again to replace a token before it expires (Geas
reminds you two weeks ahead).

Every command syncs with GitHub first and pushes what it changed;
`--offline` works on the local copy, and the next sync sends it.
