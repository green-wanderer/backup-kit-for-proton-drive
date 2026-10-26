# Changelog

## 2.1.0 (2026-10-26)

- `flock` is required: `bpd-backup` refuses to run without it (a failed status and a
  notification), and `bpd-doctor` and `install.sh` report it as a FIX. It was optional, and
  missing it silently dropped the lock that stops two runs of one set overlapping.
- CHANGELOG: 2.0.0's upgrade note now includes the mirror marker step, as its release notes did.

## 2.0.0 (2026-10-26)

- Renamed: the repo is now `backup-kit-for-proton-drive` (the old URL redirects), and every
  command `pd-X` is now `bpd-X`. Config, state and cache move from `pd-backup` to `bpd-backup`
  under `~/.config`, `~/.local/state` and `~/.cache`; `BPD_CONF_DIR` replaces `PD_CONF_DIR`.
  Upgrading: `bash install.sh --uninstall` from 1.x, move those three folders, rename a mirror
  drive's `.pd-mirror` marker to `.bpd-mirror`, then install.
- `bpd-init` warns when a new set's Drive folder already has backups (another computer?).
- README: two computers need their own set names.

## 1.0.1 (2026-10-25)

- README: states that this is an unofficial project, not affiliated with Proton, and
  how it was tested; notes that only the newest archive is pushed after a logout.
- `pd-drill` works with older `mawk` (Debian 12 and others), which lacks `{5}` in regexes.
- `pd-init` and the example home set leave out the CLI's saved login.

## 1.0.0 (2026-10-25)

- `install.sh`, `pd-init` (guided setup), `pd-doctor` (what is missing and how to fix it),
  `pd-restore` (files back into a new folder; never overwrites).
- `drive =` defaults to `drive_root/backups/SET`.
- Any set's private key inside a source is left out of the archive automatically.
- A paused push names the actual cause (CLI missing, `jq` missing, logged out);
  a failed upload shows the CLI's last line (a full Drive, say).
- `drill_pick = oldest|newest` (setting and per set); `pd-drill --oldest` beside `--newest`.
- `notifications = no` turns off desktop notifications.
- `install.sh` finds and installs the downloaded CLI (anywhere in home, or a given path).
- `pd-drill`: works with Kubuntu 26.04's stock coreutils; failures name the failing layer.
- `pd-init`: retries the check after login, offers to show the key, stops on a failed drill.
- `pd-doctor` reports the backups' health too (`pd-check`'s warnings).
- Example units for `pd-check --notify` and `pd-mirror`.
