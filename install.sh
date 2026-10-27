#!/usr/bin/env bash
# install.sh - put bpd-kit's commands on your PATH, then check what else is needed.
#
# Usage: bash install.sh [CLI]         link bin/bpd-* into ~/.local/bin
#        bash install.sh --uninstall   remove those links (config and backups stay)
#
# CLI is the downloaded proton-drive file; without it, your home folder is searched.
#
# Next step after this: bpd-init

[[ $1 == -h || $1 == --help ]] && { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; exit 0; }
KIT=$(dirname "$(readlink -f "$0")")
BIN="$HOME/.local/bin"

if [[ $1 == --uninstall ]]; then
    for f in "$KIT"/bin/bpd-*; do
        l="$BIN/${f##*/}"
        [[ -L $l && $(readlink -f "$l") == "$f" ]] && rm -f -- "$l" && echo "removed $l"
    done
    echo "Config (~/.config/bpd-backup) and backups (~/backups, Proton Drive) are untouched."
    exit 0
fi
CLI_FILE=""
if [[ -n $1 ]]; then
    [[ -f $1 ]] || { echo "no such file: $1 (try -h)" >&2; exit 2; }
    CLI_FILE=$(readlink -f -- "$1")
fi

chmod +x "$KIT"/bin/bpd-*    # an unzip can drop the execute bit
mkdir -p "$BIN"
for f in "$KIT"/bin/bpd-*; do
    l="$BIN/${f##*/}"
    if [[ -e $l && ! -L $l ]]; then
        echo "skipped $l: a file that is not a link is already there" >&2
        continue
    fi
    ln -sfn "$f" "$l"
done
echo "Linked the bpd-* commands into $BIN"

case ":$PATH:" in
    *":$BIN:"*) ;;
    *)  rc=""
        case ${SHELL##*/} in zsh) rc=~/.zshrc ;; bash) rc=~/.bashrc ;; esac
        if [[ -n $rc ]] && ! grep -qs '\.local/bin' "$rc"; then
            # shellcheck disable=SC2016  # $HOME and $PATH must reach the rc file unexpanded
            printf '\n# bpd-kit: commands in ~/.local/bin\nexport PATH="$HOME/.local/bin:$PATH"\n' >>"$rc"
            echo "Added ~/.local/bin to your PATH in $rc"
        fi
        export PATH="$BIN:$PATH"
        echo "Open a new terminal for the bpd-* commands to be found." ;;
esac

# The Proton Drive CLI is one file, downloaded from Proton's page. Find it and install it.
case $(uname -m) in
    x86_64)  ARCH=linux-x64 ;;
    aarch64) ARCH=linux-arm64 ;;
    *)       ARCH="linux for $(uname -m)" ;;
esac
if [[ -n $CLI_FILE ]] || ! command -v proton-drive >/dev/null; then
    # The given file, or any match in home a few folders deep (Downloads, Documents,
    # Desktop...), hidden folders skipped. Newest first; the first one that runs wins.
    if [[ -n $CLI_FILE ]]; then
        cands=("$CLI_FILE")
    else
        mapfile -t cands < <(find "$HOME" "$KIT" -maxdepth 3 -name '.*' -prune -o -type f \
            -name 'proton-drive*' ! -name '*.zip' ! -name '*.exe' -printf '%T@\t%p\n' 2>/dev/null |
            sort -rn | cut -f2-)
    fi
    found="" tmp="$BIN/.proton-drive.new"
    for c in "${cands[@]}"; do
        install -m 755 "$c" "$tmp" && "$tmp" --version >/dev/null 2>&1 && { found=$c; break; }
    done
    echo
    if [[ -n $found ]]; then
        read -rp "Found the Proton Drive CLI at $found. Install it? [Y/n] " r
        if [[ ${r:-y} == [yY]* ]]; then
            mv -f -- "$tmp" "$BIN/proton-drive" && echo "Installed it as $BIN/proton-drive"
        fi
    elif (( ${#cands[@]} )); then
        echo "Found ${cands[0]}, but it does not run on this computer."
        echo "Download the $ARCH version from https://proton.me/download/drive/cli/index.html"
    else
        echo "The Proton Drive CLI is not installed. Download the $ARCH version from"
        echo "  https://proton.me/download/drive/cli/index.html"
        echo "then run bash install.sh again. It finds the file anywhere in your home folder,"
        echo "or give it the path: bash install.sh /path/to/proton-drive"
    fi
    rm -f -- "$tmp"
fi

echo
"$KIT/bin/bpd-doctor" --tools || { echo; echo "Fix what is marked FIX, then run bash install.sh again."; exit 1; }
echo
echo "Next: bpd-init"
