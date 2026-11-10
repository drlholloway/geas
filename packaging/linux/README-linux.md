# Geas for Linux (x86-64)

A personal task manager: lists, tags, due dates, priorities, checklists, an
Eisenhower matrix and order tracking, synced through a private GitHub repo.

This is the plain tarball build. The Releases page also has an AppImage
(`Geas-<version>-x86_64.AppImage`: make it executable and run it).

## Requirements

- A 64-bit Intel/AMD Linux with GTK 3
  (Debian/Ubuntu: `sudo apt install libgtk-3-0`; Fedora: `sudo dnf install gtk3`).
- libsecret and a Secret Service (GNOME Keyring or KWallet), where Geas
  keeps its GitHub token (Debian/Ubuntu: `sudo apt install libsecret-1-0
  gnome-keyring`; Fedora: `sudo dnf install libsecret gnome-keyring`).

## Install

1. Extract the archive anywhere, e.g. `~/Apps/geas`.
2. Run `./geas`.

The first run walks you through the data repo and a GitHub token. The
local copy of your tasks lives in `~/.local/share/dev.laneholloway.geas/`.
