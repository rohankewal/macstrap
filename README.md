# Macstrap

A single script that sets up a curated macOS dev environment — window
manager, launcher, terminal, editor — and lets you switch color themes
across all of it (terminal, editor, menu bar) from one command.

Inspired by [Omarchy](https://learn.omacom.io)'s "one script, fully themed
machine" idea for Linux/Hyprland, rebuilt around what actually works on
macOS.

## Quickstart

```sh
git clone <this-repo> macstrap && cd macstrap
./install.sh            # add --dry-run to preview every change first
```

The installer asks two questions up front — which **multiplexer** (tmux or
herdr) and which **shell** (Oh My Zsh, fish, Nushell, or none). Skip the
prompts with `./install.sh --multiplexer=herdr --shell=fish`. Non-interactive
runs default to tmux and to leaving your shell alone.

## What gets installed

The default set is intentionally small (`brew/Brewfile.core`) — everything
heavier is a manual `brew install` away, never bundled by default:

- **Window management**: yabai, skhd, Karabiner-Elements (Caps Lock → Hyper key)
- **Bar / launcher**: sketchybar, Raycast
- **Terminal stack**: Ghostty, Neovim, starship, fzf, jq, bat, btop
- **Multiplexer**: tmux *or* herdr, whichever you pick (`brew/Brewfile.tmux`
  / `brew/Brewfile.herdr`) — only the one you choose gets installed
- **Shell**: Oh My Zsh, fish, or Nushell — again, only the one you pick, and
  only if you pick one
- **GUI apps**: Firefox, Visual Studio Code
- **Wallpaper plumbing**: desktoppr

## Multiplexer: tmux or herdr

- **tmux** — the classic. Themed the way everything else here is themed: one
  `source-file` line appended to `~/.tmux.conf`, pointing at a symlink
  Macstrap re-points on every theme switch.
- **[herdr](https://herdr.dev)** — a newer multiplexer built around coding
  agents: tmux-style prefix keys plus mouse, panes that show whether each
  agent is working/blocked/done, sessions that survive detach and restart.

Switch later without reinstalling — this re-applies the current theme to the
new one and stops managing the old one:

```sh
macstrap multiplexer            # print the current choice
macstrap multiplexer set herdr
```

The choice is recorded in `~/.macstrap/multiplexer`; installs that predate
this option keep tmux.

**One difference worth knowing about herdr:** its config is a single TOML
file with no include directive, so Macstrap can't hand it a symlinked theme
file the way it does for tmux and Ghostty. Instead the theme is written into
`~/.config/herdr/config.toml` as a marked block (`# >>> macstrap theme` …
`# <<< macstrap theme`), rewritten in place on every theme switch, removed if
you switch away, and backed up + reversible like everything else. If that
config already has its own `[theme]` table, Macstrap **won't touch it at
all** — a duplicate TOML table makes herdr throw out the whole config, so
you'll get a message asking you to remove yours first.

herdr also exposes a fixed set of overridable color tokens rather than a full
palette, so each theme names the closest herdr built-in as its base (in
`palette.json`'s `herdr_base`) and overrides the tokens on top. Everforest
has no herdr port, so it bases on herdr's `terminal` theme and inherits the
Ghostty palette Macstrap already sets.

## Shell: Oh My Zsh, fish, Nushell — or none

- **omz** — [Oh My Zsh](https://ohmyz.sh) on the zsh macOS already gave you.
  Not a Homebrew package, so it's installed by its own script, and Macstrap
  asks before running it. It runs with `--unattended --keep-zshrc`, so the
  installer won't change your login shell or replace an existing `~/.zshrc`.
- **fish** — [fish](https://fishshell.com), via `brew/Brewfile.fish`.
- **nushell** — [Nushell](https://www.nushell.sh), via `brew/Brewfile.nushell`.
- **none** — the default for non-interactive installs, and for anyone who
  installed Macstrap before this option existed. Your shell is untouched.

Whichever you pick gets the same two things wired up: Homebrew's environment,
and the **starship** prompt that `Brewfile.core` has always installed but
nothing used to actually enable.

```sh
macstrap shell             # print the current choice
macstrap shell set fish
```

The choice lives in `~/.macstrap/shell-choice`. Switching unhooks the old
shell before wiring the new one, so nothing is left sourcing a fragment
Macstrap has stopped maintaining.

### How each one gets hooked up

Macstrap generates one fragment per shell into `~/.macstrap/shell/` — these
are generated rather than kept in `configs/` because they bake in this
machine's Homebrew prefix and starship's own init output. Delivery then uses
whatever mechanism the shell actually offers:

| Shell | Hook |
| --- | --- |
| omz | one `source` line appended to `~/.zshrc` |
| fish | a symlink into fish's `conf.d/` drop-in directory |
| nushell | a marked block in `config.nu` |

Nushell gets the block treatment for the same reason herdr does: its `source`
needs a literal path it can resolve at parse time, and which autoload
directories exist varies by version, so `config.nu` is the one place
guaranteed to be read. Macstrap asks `nu` itself where that file lives rather
than guessing — on macOS it's under `~/Library/Application Support`, not
`~/.config`.

The zsh fragment sources Oh My Zsh only if your own `~/.zshrc` hasn't already
done so, so a config that predates Macstrap keeps working and never loads
Oh My Zsh twice. It also sets `ZSH_THEME=""`, since starship draws the prompt.

### Changing your login shell

Separate, explicit, and always confirmed — installing a shell and living in
it are two different decisions. `chsh` only accepts shells listed in
`/etc/shells`, and adding a line there needs sudo: the one privileged step in
this whole feature. Macstrap asks before doing either, prints the two commands
to run yourself if you decline, and records your previous shell so
`macstrap remove` puts it back.

## Themes

`macstrap theme` opens an fzf picker with a live color-swatch preview; enter
applies it across Ghostty, your multiplexer (tmux or herdr), sketchybar, and
Neovim. Non-interactive: `macstrap theme set nord`.

Shipped in this pass: `catppuccin-mocha`, `nord`, `gruvbox`, `tokyo-night`,
`rose-pine`, `kanagawa`, `everforest` — the themes with mature, existing
ports across this whole toolchain. Omarchy's more original themes (lumon,
hackerman, matte-black, etc.) are a deliberate fast-follow, since those
need their palettes extracted from Omarchy's own theme files rather than
vendored from an existing ecosystem.

Each theme folder's only hand-edited file is `palette.json` — every
per-app config (`ghostty.conf`, `tmux.conf`, `herdr.toml`, `neovim.lua`,
`sketchybar.sh`, `preview.ansi`) is generated from it by
`scripts/gen-theme-configs.sh`. Edit the palette, re-run the generator, never
hand-edit the generated files.

Wallpapers are intentionally not included yet — Omarchy's per-theme
wallpapers are real photography (several explicitly attributed to named
Unsplash photographers), and bundling them needs a license check per image
before redistribution, which hasn't been done.

## Safety model

Every state-changing action goes through `bin/lib/manifest.sh`, which logs
each one to `~/.macstrap/state.jsonl`. This is what makes the following true:

- **Idempotent** — re-running `install.sh` or `theme-set` is always safe;
  already-correct state is a no-op.
- **Non-destructive** — if a target already has a real file (not our
  symlink), it's backed up to `~/.macstrap/backups/` before anything is
  touched, never overwritten in place.
- **Dry-run** — `install.sh --dry-run` / `theme-set <name> --dry-run` print
  every action without doing it.
- **Reversible** — `macstrap remove` walks the manifest backwards and
  restores exactly what was backed up, including your login shell if you let
  Macstrap change it.

One deliberate exception: yabai's scripting addition (full window
border/opacity control) needs a partial SIP disable and a sudoers entry.
That step is never run automatically — `install.sh` only prints the
instructions after an explicit confirmation, because it's the one action
here that isn't cleanly reversible by this tool.

## Keybindings

All bindings live on **Hyper** (Caps Lock, remapped via
`configs/karabiner/macstrap-hyper-key.json` — enable it once in
Karabiner-Elements' Complex Modifications UI after install) plus every
other modifier held together. Nothing is bound to plain Cmd, since that's
already claimed by every app on the system — see `configs/skhd/skhdrc` for
the full list (app launching, yabai focus/swap/float, space switching).

## Commands

```
macstrap install [--dry-run]   run/re-run the installer
                               (--multiplexer=<tmux|herdr>, --shell=<omz|fish|
                                nushell|none> to skip the prompts)
macstrap theme                 interactive theme picker
macstrap theme set <name>      apply a theme directly
macstrap theme list            list available themes
macstrap multiplexer           print the multiplexer in use
macstrap multiplexer set <n>   switch to tmux or herdr, re-theming as it goes
macstrap shell                 print the shell setup in use
macstrap shell set <name>      switch shell setup (offers to chsh)
macstrap doctor                health check (services running, SA loaded, etc.)
macstrap update                git pull + re-run install
macstrap remove                reverse everything Macstrap has done
```

## Known gaps / not yet built

- **The prompt isn't themed per theme.** Every shell gets starship, but
  starship reads a single `~/.config/starship.toml` with no include
  directive, so making its colors follow `macstrap theme` needs the same
  managed-block treatment herdr and Nushell got. Not done yet — the prompt
  uses starship's own defaults.
- Wallpaper-per-theme (blocked on the licensing check above)
- Omarchy-original themes beyond the 7 with existing ecosystem ports
- Raycast extension for the theme picker (the fzf TUI is the v1 path)
- CI (GitHub Actions macOS runner running `install.sh` end-to-end + shellcheck)
- Ghostty's exact `-e` launch flag and `config-file` include directive are
  written against current docs but not yet confirmed against your installed
  Ghostty version — check these first if either integration misbehaves.
