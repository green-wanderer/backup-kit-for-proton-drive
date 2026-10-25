# proton-drive-backup-kit

Automatic, encrypted backups of a Linux folder to Proton Drive, using the
[Proton Drive CLI](https://proton.me/download/drive/cli/index.html). It backs up
daily, keeps a set of older copies, warns you when something is wrong, and tests
that the backups actually restore.

> **Written by AI.** An LLM coding agent wrote this code at my direction. It is a
> generic version of the setup I run every day. I reviewed it, but I did not write
> it by hand. Read it before you trust it with your data.

**Download:** [the latest release](https://github.com/green-wanderer/proton-drive-backup-kit/releases/latest),
then *Source code (zip)*. **Support:** shared as-is. I run it every day and fix what
affects me; issues are welcome, but replies may be slow or never come.

## Quick start

Download the [Proton Drive CLI](https://proton.me/download/drive/cli/index.html)
for Linux (`linux-x64` on most computers). Save it anywhere in your home folder;
`install.sh` finds it and installs it. Then, in a terminal, inside the unzipped folder:

```sh
bash install.sh
pd-init
```

`install.sh` installs the CLI, puts the commands on your PATH, and lists anything
else you need to install, with the command for it. Run it again until it says
`Next: pd-init`. `pd-init` asks a few questions and sets up your
first backup: what to back up, the encryption key, how many copies to keep, a
first backup and test restore, and a daily timer.

After that you don't need to do anything. You'll get a warning (a notification,
and a line in your terminal) only when a backup needs attention, and the warning
says which command to run.

## Day to day

| Command | What it does |
|---|---|
| `pd-check` | lists what needs attention; silent when all is well |
| `pd-restore SET --list` | lists your backups |
| `pd-restore SET` | restores the newest backup into a new folder |
| `pd-backup SET` | backs up now |
| `pd-drill SET` | tests a restore; `pd-check` reminds you when one is due (every 30 days unless you change `drill_days`) |
| `pd-session` | logs in to Proton Drive again when the session has expired |
| `pd-doctor` | checks the whole setup when something seems wrong |

Add `-h` to any command to see its help, e.g. `pd-restore -h`.

## Getting files back

`pd-restore` writes into a new folder and never overwrites anything. Copy back
what you need afterwards.

```sh
pd-restore home                              # newest backup, into ./home-restore-DATE
pd-restore home --only Documents/taxes       # one folder or file
pd-restore home 2026-10-01 --into ~/old      # the backup from that day
```

**If this computer is lost, broken or wiped**, restore from any Linux computer:
install the CLI and the kit (`bash install.sh`), run `pd-session` to log in, then:

```sh
pd-restore home --key /path/to/home.key --into ~/restored
```

You need that key file. `pd-init` asks you to keep a copy off the computer
(a USB stick or a password manager). Without it, an encrypted backup cannot be opened.

## Requirements

Linux with GNU tools and systemd. `install.sh` checks for all of these:

- bash 4+, GNU tar, `zstd`, `jq`, `age`
- `proton-drive` (the CLI), tested with 0.9.0. To upgrade it, download the new version and
  run `bash install.sh /path/to/proton-drive`
- optional: `flock` (stops two runs of the same set overlapping), `notify-send`
  (notifications)
- optional, KDE only: Dolphin and `kdialog` for the right-click menu. On GNOME and other
  desktops everything else works the same; only the file manager menu is missing.

## What's in it

| Script | What it does |
|---|---|
| `install.sh` | links the commands into `~/.local/bin` and checks the tools; `--uninstall` |
| `pd-init` | guided setup of one backup set |
| `pd-doctor` | checks tools, login, keys and timers, and says how to fix each problem |
| `pd-backup SET` | tar + zstd a folder, encrypt it with [age](https://age-encryption.org), upload it, check the size on Drive, then prune |
| `pd-prune SET` | retention on Drive (daily, weekly, monthly, yearly); trashes, never deletes |
| `pd-restore SET` | downloads, decrypts and unpacks into a new folder |
| `pd-drill [SET]` | test restore: reads a backup end to end, restores a sample of files |
| `pd-check` | what needs attention: failed runs, pushes that didn't land, stale sets, overdue drills |
| `pd-session` | logs in, checks the session works, lists pushes waiting on it |
| `pd-mirror` | copies archives to a second disk, checks them, applies the same retention |
| `pd-send`, `pd-send-menu` | send files to a Drive folder and confirm they arrived (used by the Dolphin menu) |
| `kde/pd-send-kio` | KDE plugin: Dolphin's right-click menu shows your Drive folders as nested menus |

## How it works

```
systemd timer -> pd-backup home
                   archive -> encrypt -> upload -> size matches on Drive? -> pd-prune
                   writes ~/.local/state/pd-backup/home.status
                                     |
         new terminal -> pd-check ---+--- pd-session (after you log in again)

every 30 days:  pd-check says a drill is due -> pd-drill home
```

The CLI cannot report whether you are logged in, so every script checks by listing
`/my-files` with a timeout. If the session has expired, `pd-backup` keeps the
local archive, marks the push as pending and notifies you. After `pd-session`,
`pd-backup --push-only SET` finishes the push. The next daily run also retries it.

## Sets

A set is one folder backed up on its own schedule, described by one file:
`~/.config/pd-backup/sets/SET.conf`. `pd-init` writes it. Edit it to change
anything. These examples cover the other kinds of set:

| Example | Shows |
|---|---|
| [`home.conf`](examples/sets/home.conf) | a folder, encrypted, with `exclude =`, `forbid =` and `require =` |
| [`phone.conf`](examples/sets/phone.conf) | `before =` filling the source over adb, exiting 3 when no phone is attached |
| [`server.conf`](examples/sets/server.conf) | `mode = file`: takes an archive a server already made, as is |
| [`postgres.conf`](examples/sets/postgres.conf) | a database dumped into a folder first |
| [`library.conf`](examples/sets/library.conf) | a big folder that rarely changes: `only_on_change`, `mirror =` to a second disk |

| Key | Meaning |
|---|---|
| `source` | the folder to archive, or (with `mode = file`) where the finished archive appears. The only required key |
| `exclude` | a tar `--exclude` pattern; repeatable |
| `drive` | the Drive folder; default `drive_root/backups/SET` |
| `local` | where local archives are kept; default `local_root/SET` |
| `recipients`, `identity` | the age public key to encrypt with, and the private key that drills and restores decrypt with. Leave both out for no encryption of your own |
| `keep` | retention on Drive: copies per day, week, month, year (default `7 4 6 1`) |
| `keep_local` | local copies to keep (default 3) |
| `stale_days` | `pd-check` warns after this many days without a run; 0 = never (for sets you run by hand) |
| `drill_days` | days between test restores; 0 = never remind (default: the setting) |
| `drill_pick` | which archive a test restore takes: `oldest` or `newest` (default: the setting) |
| `require`, `forbid` | text that must, or must not, appear in a path inside the archive; repeatable. A `forbid` match stops the upload |
| `before` | a command run first, with `PD_SET`, `PD_SOURCE`, `PD_LOCAL`, `PD_STATE`, `PD_PID` set. Exit 3: nothing to do, nothing recorded. Exit 4: incomplete, archived as `PARTIAL`, never pruned behind |
| `scratch` | `yes` when `source` is only a staging folder for `before =`; emptied after every run |
| `check` | a command `pd-drill` runs inside the fully restored archive; exit 0 passes |
| `mode`, `match` | `mode = file` takes the newest file matching `match =` as the archive |
| `only_on_change` | `yes` skips runs where nothing changed. Always on for `mode = file` |
| `push` | `no` keeps the set off Drive (local and mirror only) |
| `mirror` | a folder on a second disk for `pd-mirror` |

Things the scripts do on their own:
- An empty source is refused, since that usually means a drive that isn't mounted.
- The local archive folder is left out of the archive.
- Any set's `identity =` key inside the source is left out of the archive.

## Settings

`~/.config/pd-backup/settings.conf` holds paths, limits, timeouts and defaults.
Every line is optional. [`examples/settings.conf`](examples/settings.conf) lists
them all with their defaults. The ones you are most likely to change:

- `notifications = no` turns off desktop notifications. `pd-check` still prints in the terminal.
- `drill_days = 30`: how often `pd-check` asks for a test restore; 0 never asks.
- `drill_pick = oldest`: which archive a test restore takes. The oldest is the one
  most likely to have gone bad unnoticed; `newest` is quicker to trust.
- `drive_root` if your Drive files are not under `/my-files`.

A set's own `drill_days` or `drill_pick` line overrides the setting for that set.

A line that doesn't parse, in any config file, stops the scripts with the file and
line number. They never quietly fall back to a default. Set `PD_CONF_DIR` to keep
the config somewhere other than `~/.config/pd-backup`.

## Space on Drive

Each archive is a full copy. With the default `keep = 7 4 6 1`, a set can hold up
to 18 copies. `pd-init` shows the estimate and offers a lighter `3 2 1 0` (up to 6).

Pruned archives go to the Drive trash and still count against your quota until you
empty it. Emptying the trash affects your whole account, so the scripts never do it:

```sh
proton-drive filesystem empty-trash
```

If Drive fills up, the upload fails, and `pd-check` shows the CLI's reason.

## Scheduling

`pd-init` turns on the timers. To do it by hand:

```sh
cp examples/systemd/* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now pd-backup@home.timer   # one per set
systemctl --user enable --now pd-check.timer         # daily notification
systemctl --user enable --now pd-mirror.timer        # only if you use mirror =
```

## The mirror

`pd-mirror` copies each set's archives into its `mirror =` folder on a second disk,
compares sha256 after each copy, and applies the set's `keep` there (retired
copies go to `.trash` in that folder). Mark the disk once, with it mounted:

```sh
pd-mirror --init /mnt/backup-disk
```

It writes only below that marker. An unmounted disk is skipped, so its empty mount
point never gets filled. `pd-drill --mirror SET` and `pd-restore SET --mirror` use the
mirror copy.

## The Dolphin menu (KDE)

Right-clicking files in Dolphin gives you "Send to Proton Drive", with your Drive folders
as nested menus, plus "Get from Proton Drive…". Every upload is checked on Drive afterwards.
"Get" never overwrites a local file.

```sh
cd kde/pd-send-kio
cmake -B build -DCMAKE_BUILD_TYPE=Release && cmake --build build
sudo cmake --install build
kbuildsycoca6
pd-send-menu
```

Build dependencies (Debian/Ubuntu): `cmake extra-cmake-modules qt6-base-dev
libkf6kio-dev libkf6coreaddons-dev`. Restart Dolphin afterwards. Rebuild after a major
KDE Frameworks upgrade. Without the plugin, `pd-send-menu` writes a plain service
menu: the same actions, with the folders as one flat list.

`pd-send-menu` caches your folder list. Run it again when your folders change, or use
"Refresh folder list" in the menu.

## Details

- **One per day.** The daily tier keeps the newest archive of each day.
- **Safety limits.** `pd-prune` refuses `keep = 0 0 0 0` and stops if one run would
  trash more than `prune_max` files. `pd-prune --dry-run SET` shows every decision.
- **Upload checks.** Success means Drive reports the right size, not just that the
  upload exited 0. The push is marked pending before it starts.
- **What a drill proves.** It downloads one archive (`drill_pick`), reads it whole
  with your key, checks `require =` and `forbid =`, and restores a few random files.
  For one run, `--oldest` or `--newest` picks the archive, and `--local` or `--mirror`
  drills that copy instead of Drive.
- **Databases.** Dump into a folder first, with `before =` or an `ExecStartPre=` drop-in
  (see `examples/systemd/pd-backup@.service` and `examples/sets/postgres.conf`).
- **State files.** `~/.local/state/pd-backup/SET.status`, `.drill`, `.mirror` and `.log`
  are plain `key=value` files that your own scripts can read:

  ```
  local=OK          # OK, PARTIAL or FAIL
  push=OK           # OK, PENDING (not on Drive), UNKNOWN (Drive didn't answer) or OFF
  time=1761364800
  archive=home_2026-10-25_030000.tar.zst.age
  message=pushed and verified
  ```

Version: see [`VERSION`](VERSION) and [`CHANGELOG.md`](CHANGELOG.md).

## License

Public domain ([The Unlicense](https://unlicense.org/)).
