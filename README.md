# backup-kit-for-proton-drive

[![shellcheck](https://github.com/green-wanderer/backup-kit-for-proton-drive/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/green-wanderer/backup-kit-for-proton-drive/actions/workflows/shellcheck.yml)

Automatic, encrypted backups of a Linux folder to Proton Drive, using the
[Proton Drive CLI](https://proton.me/download/drive/cli/index.html). It backs up
on a schedule (daily unless you change it), keeps a set of older copies, warns you
when something is wrong, and tests that the backups actually restore.

It's for Linux users with a Proton Drive account who want backups they can set up
once and forget, and who are OK typing a few commands. Every backup is a full copy,
so look elsewhere if you want small incremental backups or use Mac or Windows.

**Unofficial.** A personal project, not made, endorsed or supported by Proton AG.
"Proton" and "Proton Drive" are Proton AG's trademarks.

**Written by AI.** An LLM coding agent wrote this code at my direction. I reviewed it,
but I did not write it by hand. I run it every day on Kubuntu 26.04. Read it before
you trust it with your data.

## Install

1. Download [the latest release](https://github.com/green-wanderer/backup-kit-for-proton-drive/releases/latest)
   (*Source code (zip)*) and unzip it.
2. Download the [Proton Drive CLI](https://proton.me/download/drive/cli/index.html)
   for Linux (`linux-x64` on most computers) and save it anywhere in your home folder.
3. In a terminal, inside the unzipped folder, run:

```sh
bash install.sh
bpd-init
```

If `install.sh` lists something missing, it gives you the command to install it. Run it
again until it says `Next: bpd-init`. Then `bpd-init` asks a few questions, makes your
first backup, tests a restore and turns on the daily timer.

After that you don't need to do anything. You'll get a warning only when a backup
needs attention, and the warning says which command to run.

**Keep a copy of your encryption key off this computer**, on a USB stick or in a password
manager. Without it, an encrypted backup cannot be opened by anyone, including you.

## Everyday commands

`SET` is the name you gave the backup in `bpd-init`, such as `home`.

| Command | What it does |
|---|---|
| `bpd-check` | lists what needs attention; silent when all is well |
| `bpd-backup SET` | backs up now |
| `bpd-restore SET` | restores the newest backup into a new folder |
| `bpd-doctor` | checks the whole setup when something seems wrong |

Add `-h` to any command to see its help.

## Getting files back

`bpd-restore` writes into a new folder and never overwrites anything. Copy back
what you need afterwards.

```sh
bpd-restore home --list                       # see your backups
bpd-restore home                              # newest backup, into ./home-restore-DATE
bpd-restore home --only Documents/taxes       # one folder or file
bpd-restore home 2026-10-01 --into ~/old      # the backup from that day
```

**If this computer is lost, broken or wiped**, restore from any Linux computer:
install the CLI and the kit (`bash install.sh`), run `bpd-session` to log in, then:

```sh
bpd-restore home --key /path/to/home.key --into ~/restored
```

This uses the copy of your key that you kept off the computer.

## Good to know

- **Old backups still use your storage** until you empty the Drive trash. The kit never
  empties it, because that affects your whole account: `proton-drive filesystem empty-trash`
- **If your Proton login expires,** backups carry on locally and you'll be warned. Run
  `bpd-session` to log in again, and the next backup run uploads the newest one.

## More

The [manual](docs/manual.md) covers everything else, including:

- every setting, and how to change the schedule or how many backups are kept
- backing up a phone, a server or a database ([examples](examples/sets))
- a second copy on another disk
- a right-click menu for Dolphin on KDE

**Support:** shared as-is. I fix what affects me. Issues are welcome, but replies may be
slow or never come. Problems with the CLI itself go to Proton.

Changes: [CHANGELOG.md](CHANGELOG.md).

## License

Public domain ([The Unlicense](https://unlicense.org/)).
