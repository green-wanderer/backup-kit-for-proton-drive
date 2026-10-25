# Changelog

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
