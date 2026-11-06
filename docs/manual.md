# Manual

Everything the [README](../README.md) leaves out. You only need this to change how the
kit behaves; `bpd-init` sets up a normal backup without it.

- [Commands](#commands)
- [Installing and upgrading](#installing-and-upgrading)
- [Sets](#sets)
- [Settings](#settings)
- [Space on Drive](#space-on-drive)
- [Scheduling](#scheduling)
- [The mirror](#the-mirror)
- [The Dolphin menu (KDE)](#the-dolphin-menu-kde)
- [Details](#details)

## Commands

The README lists the everyday ones. The rest usually come up when a warning names them.
Each answers `-h` with its full options.

| Command | What it does |
|---|---|
| `bpd-drill SET` | tests a restore; `bpd-check` reminds you when one is due |
| `bpd-session` | logs in to Proton Drive again and lists uploads waiting on it |
| `bpd-backup --push-only SET` | finishes a waiting upload now, without a new backup |
| `bpd-prune SET` | removes old backups on Drive; `--dry-run` shows every decision |
| `bpd-mirror` | copies backups to a second disk ([the mirror](#the-mirror)) |
| `bpd-send`, `bpd-send-menu` | send files to a Drive folder; used by the [Dolphin menu](#the-dolphin-menu-kde) |

## Installing and upgrading

The kit needs Linux with GNU tools and systemd. `install.sh` checks for all of these:

- bash 4+, GNU tar, `zstd`, `jq`, `age`, `flock`
- `proton-drive` (the CLI), tested with 0.9.0
- optional: `notify-send`, for desktop notifications
- optional, KDE only: Dolphin and `kdialog`, for the right-click menu

To upgrade the CLI, download the new version and run `bash install.sh /path/to/proton-drive`.
To remove the kit's commands, run `bash install.sh --uninstall`.

## Sets

A set is one folder backed up on its own schedule, described by one file:
`~/.config/bpd-backup/sets/SET.conf`. `bpd-init` writes it; edit it to change anything.
These examples cover the other kinds of set:

| Example | Shows |
|---|---|
| [`home.conf`](../examples/sets/home.conf) | a folder, encrypted, with `exclude =`, `forbid =` and `require =` |
| [`phone.conf`](../examples/sets/phone.conf) | `before =` filling the source over adb, exiting 3 when no phone is attached |
| [`server.conf`](../examples/sets/server.conf) | `mode = file`: takes an archive a server already made, as is |
| [`postgres.conf`](../examples/sets/postgres.conf) | a database dumped into a folder first |
| [`library.conf`](../examples/sets/library.conf) | a big folder that rarely changes: `only_on_change`, `mirror =` to a second disk |

| Key | Meaning |
|---|---|
| `source` | the folder to archive, or (with `mode = file`) where the finished archive appears. The only required key |
| `exclude` | a tar `--exclude` pattern; repeatable |
| `drive` | the Drive folder; default `drive_root/backups/SET` |
| `local` | where local archives are kept; default `local_root/SET` |
| `recipients`, `identity` | the age public key to encrypt with, and the private key that drills and restores decrypt with. Leave both out for no encryption of your own |
| `keep` | retention on Drive: copies per day, week, month, year (default `7 4 6 1`) |
| `keep_local` | local copies to keep (default 3) |
| `stale_days` | `bpd-check` warns after this many days without a run; 0 = never (for sets you run by hand) |
| `drill_days` | days between test restores; 0 = never remind (default: the setting) |
| `drill_pick` | which archive a test restore takes: `oldest` or `newest` (default: the setting) |
| `require`, `forbid` | text that must, or must not, appear in a path inside the archive; repeatable. A `forbid` match stops the upload |
| `before` | a command run first, with `BPD_SET`, `BPD_SOURCE`, `BPD_LOCAL`, `BPD_STATE`, `BPD_PID` set. Exit 3: nothing to do, nothing recorded. Exit 4: incomplete, archived as `PARTIAL`, never pruned behind |
| `scratch` | `yes` when `source` is only a staging folder for `before =`; emptied after every run |
| `check` | a command `bpd-drill` runs inside the fully restored archive; exit 0 passes |
| `mode`, `match` | `mode = file` takes the newest file matching `match =` as the archive |
| `only_on_change` | `yes` skips runs where nothing changed. Always on for `mode = file` |
| `push` | `no` keeps the set off Drive (local and mirror only) |
| `mirror` | a folder on a second disk for `bpd-mirror` |

The scripts also do three things on their own:

- They refuse an empty source, since that usually means a drive that isn't mounted.
- They leave the local archive folder out of the archive.
- They leave any set's `identity =` key out of the archive when it sits inside the source.

## Settings

`~/.config/bpd-backup/settings.conf` holds paths, limits, timeouts and defaults.
Every line is optional. [`examples/settings.conf`](../examples/settings.conf) lists
them all with their defaults. The ones you are most likely to change:

- `notifications = no` turns off desktop notifications. `bpd-check` still prints in the terminal.
- `drill_days = 30`: how often `bpd-check` asks for a test restore; 0 never asks.
- `drill_pick = oldest`: which archive a test restore takes. `newest` is quicker to trust;
  the oldest is the one most likely to have gone bad unnoticed.
- `drive_root` if your Drive files are not under `/my-files`.

A set's own `drill_days` or `drill_pick` line overrides the setting for that set.

A line that doesn't parse, in any config file, stops the scripts with the file and line
number. Set `BPD_CONF_DIR` to keep the config somewhere other than `~/.config/bpd-backup`.

## Space on Drive

Each archive is a full copy. With the default `keep = 7 4 6 1`, a set can hold up
to 18 copies. `bpd-init` shows the estimate and offers a lighter `3 2 1 0` (up to 6).

Removed archives go to the Drive trash and count against your quota until you empty it
with `proton-drive filesystem empty-trash`. If Drive fills up, the upload fails, and
`bpd-check` shows the CLI's reason.

## Scheduling

`bpd-init` sets each backup to run daily. To change that, for example to weekly, run
`systemctl --user edit bpd-backup@home.timer` and add:

```ini
[Timer]
OnCalendar=
OnCalendar=weekly
```

The empty line clears the daily schedule. Then set `stale_days` in that set's config to
a little longer than the gap (8 for weekly), or `bpd-check` warns after 2 days.

To turn on the timers by hand:

```sh
cp examples/systemd/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bpd-backup@home.timer   # one per set
systemctl --user enable --now bpd-check.timer         # daily notification
systemctl --user enable --now bpd-mirror.timer        # only if you use mirror =
```

## The mirror

`bpd-mirror` copies each set's archives into its `mirror =` folder on a second disk,
compares sha256 after each copy, and applies the set's `keep` there (retired
copies go to `.trash` in that folder). Mark the disk once, with it mounted:

```sh
bpd-mirror --init /mnt/backup-disk
```

It writes only below that marker. An unmounted disk is skipped, so its empty mount
point never gets filled. `bpd-drill --mirror SET` and `bpd-restore SET --mirror` use the
mirror copy.

## The Dolphin menu (KDE)

Right-clicking files in Dolphin gives you "Send to Proton Drive", with your Drive folders
as nested menus, plus "Get from Proton Drive…". Every upload is checked on Drive afterwards.
"Get" never overwrites a local file. On other desktops, only this menu is missing.

```sh
cd kde/bpd-send-kio
cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
sudo cmake --install build
kbuildsycoca6
bpd-send-menu
```

Build dependencies (Debian/Ubuntu): `cmake extra-cmake-modules qt6-base-dev
libkf6kio-dev libkf6coreaddons-dev`. Restart Dolphin afterwards. Rebuild after a major
KDE Frameworks upgrade. Without the plugin, `bpd-send-menu` writes a plain service
menu: the same actions, with the folders as one flat list.

`bpd-send-menu` caches your folder list. Run it again when your folders change, or use
"Refresh folder list" in the menu.

## Details

- **One per day.** The daily tier keeps the newest archive of each day.
- **While logged out,** backups keep running locally, and `keep_local` still removes the
  oldest local copies. When you log in again, only the newest archive is pushed.
- **Two computers?** Give each its own set names, so they don't share a Drive folder and
  prune each other's backups. `bpd-init` warns when a name is already in use on Drive.
- **Safety limits.** `bpd-prune` refuses `keep = 0 0 0 0` and stops if one run would
  trash more than `prune_max` files.
- **Upload checks.** Success means Drive reports the right size, not just that the
  upload exited 0.
- **What a drill proves.** It downloads one archive (`drill_pick`), reads it whole
  with your key, checks `require =` and `forbid =`, and restores a few random files.
  For one run, `--oldest` or `--newest` picks the archive, and `--local` or `--mirror`
  drills that copy instead of Drive.
- **Databases.** Dump into a folder first, with `before =` or an `ExecStartPre=` drop-in
  (see `examples/systemd/bpd-backup@.service` and `examples/sets/postgres.conf`).
- **State files.** `~/.local/state/bpd-backup/SET.status`, `.drill`, `.mirror` and `.log`
  are plain `key=value` files that your own scripts can read:

  ```
  local=OK          # OK, PARTIAL or FAIL
  push=OK           # OK, PENDING (not on Drive), UNKNOWN (Drive didn't answer) or OFF
  time=1761364800
  archive=home_2026-10-25_030000.tar.zst.age
  message=pushed and verified
  ```
