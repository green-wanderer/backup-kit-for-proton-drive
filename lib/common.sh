# common.sh - helpers shared by the bpd-* scripts. Sourced, not run.
# shellcheck shell=bash
# shellcheck disable=SC2034  # its settings and parsed fields are read by the scripts that source it

CONF_DIR="${BPD_CONF_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/bpd-backup}"

# Settings and their defaults. Override any of them in $CONF_DIR/settings.conf;
# examples/settings.conf lists every one.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/bpd-backup"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/bpd-backup"
LOCAL_ROOT="$HOME/backups"
DRIVE_ROOT=/my-files
MENU_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/kio/servicemenus/bpd-send.desktop"
MENU_MODE=auto
MENU_DEPTH=3
MENU_MAX=200
MENU_PER_LEVEL=60
DEFAULT_STALE_DAYS=2
DEFAULT_KEEP="7 4 6 1"
DEFAULT_KEEP_LOCAL=3
ZSTD_LEVEL=3
LOG_MAX_KB=1024
PRUNE_MAX=30
DRILL_DAYS=30
DRILL_SAMPLE=5
DRILL_PICK=oldest
DRILL_CONFIRM_MB=1024
DRILL_SPARE_MB=256
SEND_CONFLICT=skip
PROBE_TIMEOUT=30
LIST_TIMEOUT=120
CALL_TIMEOUT=60
PUSH_TIMEOUT=3h
SEND_TIMEOUT=1h
DRILL_TIMEOUT=4h
BEFORE_TIMEOUT=4h
MIRROR_STALE_DAYS=7
NOTIFICATIONS=yes

CLI_URL=https://proton.me/download/drive/cli/index.html

# load_settings: "key = value" lines from $CONF_DIR/settings.conf, checked by
# type. Nothing is eval'd. Returns 1 with the reason in LOAD_ERR.
load_settings() {
    local file="$CONF_DIR/settings.conf" n=0 line key val var
    LOAD_ERR=""
    [[ -e $file ]] || return 0
    [[ -r $file ]] || { LOAD_ERR="cannot read $file"; return 1; }
    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || { LOAD_ERR="$file:$n: expected key = value"; return 1; }
        key=${line%%=*}; key=${key%"${key##*[![:space:]]}"}
        val=${line#*=};  val=${val#"${val%%[![:space:]]*}"}
        # shellcheck disable=SC2088  # a literal ~ typed in the conf, expanded here
        [[ $val == "~" || $val == "~/"* ]] && val="$HOME${val#\~}"
        case $key in
            state_dir|cache_dir|local_root|menu_file)
                [[ $val == /* ]] || { LOAD_ERR="$file:$n: $key must be an absolute path"; return 1; }
                val=${val%/} ;;
            drive_root)
                [[ $val == /* ]] || { LOAD_ERR="$file:$n: drive_root must start with /"; return 1; }
                val=${val%/} ;;
            menu_mode)
                [[ $val =~ ^(auto|plugin|flat)$ ]] || { LOAD_ERR="$file:$n: menu_mode is auto, plugin or flat"; return 1; } ;;
            notifications)
                [[ $val =~ ^(yes|no)$ ]] || { LOAD_ERR="$file:$n: notifications is yes or no"; return 1; } ;;
            drill_pick)
                [[ $val =~ ^(oldest|newest)$ ]] || { LOAD_ERR="$file:$n: $key is oldest or newest"; return 1; } ;;
            send_conflict)
                [[ $val =~ ^(skip|replace)$ ]] || { LOAD_ERR="$file:$n: send_conflict is skip or replace"; return 1; } ;;
            default_keep)
                [[ $val =~ ^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]] ||
                    { LOAD_ERR="$file:$n: default_keep needs four whole numbers"; return 1; } ;;
            zstd_level)
                [[ $val =~ ^([1-9]|1[0-9])$ ]] || { LOAD_ERR="$file:$n: zstd_level is 1-19"; return 1; } ;;
            probe_timeout|list_timeout|call_timeout|push_timeout|send_timeout|drill_timeout|before_timeout)
                [[ $val =~ ^[1-9][0-9]*[smhd]?$ ]] || { LOAD_ERR="$file:$n: $key is a duration like 90s, 30m or 2h"; return 1; } ;;
            menu_depth|menu_max|menu_per_level|default_keep_local|prune_max|drill_sample|log_max_kb)
                [[ $val =~ ^[1-9][0-9]*$ ]] || { LOAD_ERR="$file:$n: $key must be a whole number above 0"; return 1; } ;;
            default_stale_days|drill_days|drill_confirm_mb|drill_spare_mb|mirror_stale_days)
                [[ $val =~ ^[0-9]+$ ]] || { LOAD_ERR="$file:$n: $key must be a whole number"; return 1; } ;;
            *) LOAD_ERR="$file:$n: unknown setting '$key'"; return 1 ;;
        esac
        var=${key^^}
        printf -v "$var" '%s' "$val"
    done <"$file"
    return 0
}

# A desktop (Dolphin, a menu) launches these without a login shell's PATH, so the
# usual home of the CLI, ~/.local/bin, is added when proton-drive is not found.
command -v proton-drive >/dev/null 2>&1 || {
    [[ -x $HOME/.local/bin/proton-drive ]] && PATH="$HOME/.local/bin:$PATH"
}

say()  { printf '%s\n' "$*"; }
warn() { printf '%s: %s\n' "$PROG" "$*" >&2; }
die()  { warn "$*"; exit 2; }

notify() { # <low|normal|critical> <title> <body>; off with notifications = no
    [[ $NOTIFICATIONS == yes ]] || return 0
    command -v notify-send >/dev/null 2>&1 &&
        notify-send -u "$1" -a "$PROG" "$2" "$3" 2>/dev/null
    return 0
}

# --- Proton Drive ------------------------------------------------------------

# The CLI has no "am I logged in?" command, and `auth login` opens a browser.
# So: list the drive root with stdin closed and a timeout. Fails fast, never prompts,
# safe to call from a timer.
drive_ready() {
    command -v proton-drive >/dev/null 2>&1 || return 1
    timeout "$PROBE_TIMEOUT" proton-drive filesystem list "$DRIVE_ROOT" </dev/null >/dev/null 2>&1
}

# drive_ls FOLDER -> one "type<TAB>size<TAB>name" line per entry; size is "-"
# for folders, since read would merge an empty column into the next one.
# Returns 1 if the folder could not be listed (offline, expired, missing).
drive_ls() {
    local out
    out=$(timeout "$LIST_TIMEOUT" proton-drive filesystem list -j "$1" </dev/null 2>/dev/null) || return 1
    [[ -n $out ]] || return 1
    jq -r '.[] | [.type,
                  (((.activeRevision // {}) | (.value? // .) | .claimedSize) // "-"),
                  .name.value] | @tsv' <<<"$out"
}

# drive_size FOLDER NAME -> prints the file's size in bytes.
# Returns 1 if the folder listed fine and the file is not in it, 2 if Drive
# could not be asked. Keep those apart: no answer is not proof of absence.
drive_size() {
    local listing type size name
    listing=$(drive_ls "$1") || return 2
    while IFS=$'\t' read -r type size name; do
        [[ $type == file && $name == "$2" ]] || continue
        [[ $size =~ ^[0-9]+$ ]] || return 2
        printf '%s\n' "$size"
        return 0
    done <<<"$listing"
    return 1
}

# drive_problem -> why Drive cannot be used now, as a fix the user can follow.
# Returns 1 (and prints nothing) when Drive is usable.
drive_problem() {
    command -v proton-drive >/dev/null 2>&1 ||
        { say "the Proton Drive CLI is not installed: $CLI_URL"; return 0; }
    command -v jq >/dev/null 2>&1 || { say "jq is not installed"; return 0; }
    drive_ready && return 1
    say "logged out of Proton Drive, or offline (bpd-session logs in)"
}

drive_mkdir_p() { # /my-files/a/b/c - errors ignored; the upload after it will say
    local path=${1#/} parent="" part
    IFS=/ read -ra parts <<<"$path"
    for part in "${parts[@]}"; do
        [[ -n $parent ]] && timeout "$CALL_TIMEOUT" proton-drive filesystem create-folder "$parent" "$part" \
            </dev/null >/dev/null 2>&1
        parent="$parent/$part"
    done
    return 0
}

# --- set config --------------------------------------------------------------

# load_set NAME reads $CONF_DIR/sets/NAME.conf: "key = value" lines, full-line
# comments with #, ~ expanded. Nothing is eval'd; before = and check = are run
# as commands, by bpd-backup and bpd-drill, and nothing else. Any line it cannot use is an error, never a
# silent default: keep= decides what gets deleted.
# Returns 1 with the reason in LOAD_ERR.
load_set() {
    local file="$CONF_DIR/sets/$1.conf" n=0 line key val
    LOAD_ERR=""
    [[ $1 =~ ^[A-Za-z0-9-]+$ ]] || { LOAD_ERR="bad set name '$1' (letters, digits, -)"; return 1; }
    [[ -r $file ]] || { LOAD_ERR="no set called $1 ($file). Make one with bpd-init"; return 1; }

    SET_NAME=$1 SET_SOURCE="" SET_DRIVE="" SET_RECIPIENTS="" SET_IDENTITY=""
    SET_LOCAL="$LOCAL_ROOT/$1" SET_STALE_DAYS=$DEFAULT_STALE_DAYS SET_KEEP_LOCAL=$DEFAULT_KEEP_LOCAL
    read -ra SET_KEEP <<<"$DEFAULT_KEEP"; SET_EXCLUDE=()
    SET_BEFORE="" SET_MODE=tar SET_MATCH="" SET_ON_CHANGE=no SET_PUSH=yes SET_MIRROR="" SET_SCRATCH=no
    SET_REQUIRE=() SET_FORBID=() SET_CHECK="" SET_DRILL_DAYS=$DRILL_DAYS SET_DRILL_PICK=$DRILL_PICK

    while IFS= read -r line || [[ -n $line ]]; do
        n=$((n + 1))
        line=${line#"${line%%[![:space:]]*}"}
        line=${line%"${line##*[![:space:]]}"}
        [[ -z $line || $line == \#* ]] && continue
        [[ $line == *=* ]] || { LOAD_ERR="$file:$n: expected key = value"; return 1; }
        key=${line%%=*}; key=${key%"${key##*[![:space:]]}"}
        val=${line#*=};  val=${val#"${val%%[![:space:]]*}"}
        # shellcheck disable=SC2088  # a literal ~ typed in the conf, expanded here
        [[ $val == "~" || $val == "~/"* ]] && val="$HOME${val#\~}"
        case $key in
            source)     SET_SOURCE=${val%/} ;;
            exclude)    SET_EXCLUDE+=("$val") ;;
            drive)      SET_DRIVE=${val%/} ;;
            local)      SET_LOCAL=${val%/} ;;
            recipients) SET_RECIPIENTS=$val ;;
            identity)   SET_IDENTITY=$val ;;
            before)     SET_BEFORE=$val ;;
            match)      SET_MATCH=$val ;;
            require)    SET_REQUIRE+=("$val") ;;
            forbid)     SET_FORBID+=("$val") ;;
            check)      SET_CHECK=$val ;;
            mirror)
                [[ $val == /* ]] || { LOAD_ERR="$file:$n: mirror must be an absolute path"; return 1; }
                SET_MIRROR=${val%/} ;;
            mode)
                [[ $val =~ ^(tar|file)$ ]] || { LOAD_ERR="$file:$n: mode is tar or file"; return 1; }
                SET_MODE=$val ;;
            only_on_change|push|scratch)
                [[ $val =~ ^(yes|no)$ ]] || { LOAD_ERR="$file:$n: $key is yes or no"; return 1; }
                case $key in push) SET_PUSH=$val ;; scratch) SET_SCRATCH=$val ;; *) SET_ON_CHANGE=$val ;; esac ;;
            stale_days)
                [[ $val =~ ^[0-9]+$ ]] || { LOAD_ERR="$file:$n: stale_days must be a whole number"; return 1; }
                SET_STALE_DAYS=$val ;;
            keep_local)
                [[ $val =~ ^[0-9]+$ ]] || { LOAD_ERR="$file:$n: keep_local must be a whole number"; return 1; }
                SET_KEEP_LOCAL=$val ;;
            drill_days)
                [[ $val =~ ^[0-9]+$ ]] || { LOAD_ERR="$file:$n: drill_days must be a whole number"; return 1; }
                SET_DRILL_DAYS=$val ;;
            drill_pick)
                [[ $val =~ ^(oldest|newest)$ ]] || { LOAD_ERR="$file:$n: drill_pick is oldest or newest"; return 1; }
                SET_DRILL_PICK=$val ;;
            keep)
                [[ $val =~ ^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]] ||
                    { LOAD_ERR="$file:$n: keep needs four whole numbers: daily weekly monthly yearly"; return 1; }
                read -ra SET_KEEP <<<"$val" ;;
            *) LOAD_ERR="$file:$n: unknown key '$key'"; return 1 ;;
        esac
    done <"$file"

    [[ -n $SET_SOURCE ]] || { LOAD_ERR="$file: source is not set"; return 1; }
    [[ $SET_PUSH == yes && -z $SET_DRIVE ]] && SET_DRIVE="$DRIVE_ROOT/backups/$1"
    [[ $SET_PUSH == no || $SET_DRIVE == /* ]] ||
        { LOAD_ERR="$file: drive must be a Drive path like $DRIVE_ROOT/backups/$1"; return 1; }
    [[ $SET_MODE == tar || -n $SET_MATCH ]] || { LOAD_ERR="$file: mode = file needs match = (a file pattern)"; return 1; }
    [[ $SET_SCRATCH == no || ( $SET_ON_CHANGE == no && $SET_MODE == tar ) ]] ||
        { LOAD_ERR="$file: scratch = yes empties the source, so it cannot go with only_on_change or mode = file"; return 1; }
    [[ $SET_SCRATCH == no || ( $SET_SOURCE != "$HOME" && $SET_SOURCE != / ) ]] ||
        { LOAD_ERR="$file: scratch = yes would empty $SET_SOURCE"; return 1; }
    (( SET_KEEP_LOCAL >= 1 )) || { LOAD_ERR="$file: keep_local must be at least 1"; return 1; }
    return 0
}

# mirror_root DIR -> the nearest folder at or above DIR holding a .bpd-mirror
# marker (made by bpd-mirror --init). An unmounted drive's mount point has none.
mirror_root() {
    local d=$1
    while [[ -n $d ]]; do
        [[ -f $d/.bpd-mirror ]] && { printf '%s\n' "$d"; return 0; }
        d=${d%/*}
    done
    return 1
}

list_sets() {
    local f
    for f in "$CONF_DIR"/sets/*.conf; do
        [[ -e $f ]] && basename "$f" .conf
    done
}

# Archives are SET_YYYY-MM-DD_HHMMSS plus their extensions (.tar.zst, .tar.zst.age,
# or whatever a mode = file set produces).
archive_re() { printf '^%s_([0-9]{4})-([0-9]{2})-([0-9]{2})_[0-9]{6}\\.[A-Za-z0-9.]+$' "$1"; }

local_archives() { # DIR SET -> archive names, oldest first
    find "$1" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | grep -E "$(archive_re "$2")" | sort
}

# --- state files -------------------------------------------------------------

# SET.status holds the last run: local=OK|PARTIAL|FAIL, push=OK|PENDING|UNKNOWN|OFF.
# Two fields because "archived fine, not on Drive" is the state worth catching.
write_status() { # SET LOCAL PUSH ARCHIVE MESSAGE
    mkdir -p "$STATE_DIR"
    printf 'local=%s\npush=%s\ntime=%s\narchive=%s\nmessage=%s\n' \
        "$2" "$3" "$(date +%s)" "$4" "$5" >"$STATE_DIR/$1.status.tmp" &&
        mv -f "$STATE_DIR/$1.status.tmp" "$STATE_DIR/$1.status"
}

# read_kv FILE PREFIX: each key=value line becomes PREFIX_key (no eval).
read_kv() {
    local line key
    [[ -r $1 ]] || return 1
    while IFS= read -r line; do
        key=${line%%=*}
        [[ $key =~ ^[a-z_]+$ ]] && printf -v "$2_$key" '%s' "${line#*=}"
    done <"$1"
}

read_status() { # SET -> ST_local ST_push ST_time ST_archive ST_message
    ST_local="" ST_push="" ST_time="" ST_archive="" ST_message=""
    read_kv "$STATE_DIR/$1.status" ST
}

read_drill() { # SET -> DR_result DR_time DR_passed DR_archive DR_message DR_source
    DR_result="" DR_time="" DR_passed="" DR_archive="" DR_message="" DR_source=""
    read_kv "$STATE_DIR/$1.drill" DR
}

read_mirror() { # SET -> MR_result MR_time MR_message
    MR_result="" MR_time="" MR_message=""
    read_kv "$STATE_DIR/$1.mirror" MR
}

days_since() { # EPOCH -> whole days, or empty for an empty input
    [[ $1 =~ ^[0-9]+$ ]] && printf '%s' $(( ($(date +%s) - $1) / 86400 ))
}

if ! load_settings; then
    [[ $PROG == bpd-check ]] && { printf '! %s\n' "$LOAD_ERR"; exit 2; }
    die "$LOAD_ERR"
fi
