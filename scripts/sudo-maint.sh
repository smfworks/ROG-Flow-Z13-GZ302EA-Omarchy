#!/usr/bin/env bash
# Root maintenance for Omarchy on the ASUS ROG Flow Z13 GZ302EA.
# Procedure: docs/root-maintenance.md
#
# Idempotent. Safe to re-run. --dry-run writes nothing.
# Does not install packages, change the kernel, the bootloader, the BIOS,
# or the initramfs, and does not reboot.
#
# Every changed file is copied to /root/maint-backup-<date>/ before the
# write. That directory contains a MANIFEST. The run ends with ok / skip /
# FAIL lines and a result line.

set -euo pipefail
umask 022
export LC_ALL=C

DRY_RUN=0
TARGET_USER=""
BACKUP_DIR=""
ENSURE_HAD=0
FAILURES=0
HOME_DIRTY=0
UNIT_RC=0
CHECKS=()
TMPS=()
declare -A BACKED=()

usage() {
  cat <<'EOF'
Usage: sudo-maint.sh [--dry-run] [--user NAME]

Root maintenance for an Omarchy install on the ROG Flow Z13 GZ302EA.
Safe to re-run. --dry-run prints the plan and the closing checks and writes nothing.

  --dry-run   Do not write files, enable units, create snapshots, or reload sshd.
  --user NAME Login account for snapper ALLOW_USERS and the SSH key check.
              When omitted, SUDO_USER is used if it is set and is not root.

Does not install packages. Does not change the kernel, the bootloader, the
BIOS, or the initramfs. Does not reboot. Skips home snapshots when /home is
not its own btrfs subvolume.
EOF
}

die() {
  printf 'sudo-maint.sh: %s\n' "$1" >&2
  exit "${2:-1}"
}

cleanup() {
  if [[ ${#TMPS[@]} -gt 0 ]]; then
    rm -f "${TMPS[@]}"
  fi
}
trap cleanup EXIT

new_tmp() {
  local t
  t=$(mktemp)
  TMPS+=("$t")
  printf '%s\n' "$t"
}

add_check() {
  local status="$1"
  local message="$2"
  CHECKS+=("${status}"$'\t'"${message}")
  if [[ "$status" == "FAIL" ]]; then
    FAILURES=$((FAILURES + 1))
  fi
}

ensure_backup_dir() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ -n "$BACKUP_DIR" ]]; then
    return 0
  fi
  local day
  day=$(date +%Y%m%d)
  BACKUP_DIR="/root/maint-backup-${day}"
  if [[ -e "$BACKUP_DIR" ]]; then
    BACKUP_DIR="/root/maint-backup-${day}-$(date +%H%M%S)"
  fi
  mkdir -p "$BACKUP_DIR"
  {
    printf '# sudo-maint.sh %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '# dry-run: no\n'
    if [[ -n "$TARGET_USER" ]]; then
      printf '# user: %s\n' "$TARGET_USER"
    else
      printf '# user: (none)\n'
    fi
  } >"$BACKUP_DIR/MANIFEST"
}

record_action() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  ensure_backup_dir
  printf 'action %s\n' "$1" >>"$BACKUP_DIR/MANIFEST"
}

backup_once() {
  local src="$1"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if [[ -n "${BACKED[$src]:-}" ]]; then
    return 0
  fi
  BACKED[$src]=1
  ensure_backup_dir
  if [[ -e "$src" ]]; then
    local dest
    dest="${BACKUP_DIR}${src}"
    mkdir -p "$(dirname "$dest")"
    cp -a "$src" "$dest"
    printf 'changed %s\n  backup: %s\n' "$src" "$dest" >>"$BACKUP_DIR/MANIFEST"
  else
    printf 'created %s\n  (no previous file)\n' "$src" >>"$BACKUP_DIR/MANIFEST"
  fi
}

read_key() {
  local file="$1"
  local key="$2"
  [[ -f "$file" ]] || return 1
  awk -v k="$key" '
    index($0, k "=") == 1 {
      val = substr($0, length(k) + 2)
      sub(/[[:space:]]+$/, "", val)
      sub(/^[[:space:]]+/, "", val)
      sub(/^"/, "", val)
      sub(/"$/, "", val)
      print val
      found = 1
      exit
    }
    END { if (!found) exit 1 }
  ' "$file"
}

# Returns 0 if the key was changed (or would be), 1 if it already matched.
write_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  local current rendered
  current=$(read_key "$file" "$key" || true)
  if [[ "$current" == "$value" ]]; then
    return 1
  fi
  rendered=$(new_tmp)
  awk -v k="$key" -v v="$value" '
    BEGIN { found = 0 }
    index($0, k "=") == 1 {
      print k "=\"" v "\""
      found = 1
      next
    }
    { print }
    END { if (!found) print k "=\"" v "\"" }
  ' "$file" >"$rendered"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$key" == "ALLOW_USERS" ]]; then
      printf 'would set ALLOW_USERS in %s\n' "$file"
    else
      printf 'would set %s=%s in %s\n' "$key" "$value" "$file"
    fi
    return 0
  fi
  backup_once "$file"
  cat "$rendered" >"$file"
  return 0
}

word_in_list() {
  local word="$1"
  local list="$2"
  case " ${list} " in
    *" ${word} "*) return 0 ;;
    *) return 1 ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --user)
        [[ $# -ge 2 ]] || die "--user needs a name" 2
        TARGET_USER=$2
        shift 2
        ;;
      --user=*)
        TARGET_USER=${1#--user=}
        [[ -n "$TARGET_USER" ]] || die "--user needs a name" 2
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1" 2
        ;;
    esac
  done
}

resolve_user() {
  if [[ -z "$TARGET_USER" && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    TARGET_USER=$SUDO_USER
  fi
  if [[ -z "$TARGET_USER" ]]; then
    return 0
  fi
  if [[ ! "$TARGET_USER" =~ ^[a-z_][a-z0-9_-]{0,31}\$?$ ]]; then
    die "--user must be a login name, not a path or a flag" 2
  fi
  if [[ "$TARGET_USER" == "root" ]]; then
    die "--user must be the login account, not root" 2
  fi
  if ! id "$TARGET_USER" >/dev/null 2>&1; then
    die "no such account: ${TARGET_USER}" 2
  fi
}

note_root_timeline() {
  local file="/etc/snapper/configs/root"
  local value
  if [[ ! -f "$file" ]]; then
    add_check ok "root snapper timeline: no root config; left unchanged (limine-snapper-sync only acts on /)"
    return 0
  fi
  value=$(read_key "$file" TIMELINE_CREATE || true)
  if [[ -z "$value" ]]; then
    value="unset"
  fi
  add_check ok "root snapper timeline: TIMELINE_CREATE=${value}; left unchanged (limine-snapper-sync only acts on /)"
}

ensure_snapper_configs_has_home() {
  local file="/etc/conf.d/snapper"
  local current updated
  if [[ ! -f "$file" ]]; then
    add_check FAIL "home snapshots: /etc/conf.d/snapper is missing; this script does not install packages"
    return 1
  fi
  current=$(read_key "$file" SNAPPER_CONFIGS || true)
  if word_in_list home "$current"; then
    return 0
  fi
  if [[ -z "$current" ]]; then
    updated="home"
  else
    updated="${current} home"
  fi
  if write_key "$file" SNAPPER_CONFIGS "$updated"; then
    HOME_DIRTY=1
  fi
  return 0
}

# 0 = enabled now or would enable, 1 = already enabled and active, 2 = failed.
enable_unit() {
  local unit="$1"
  if systemctl is-enabled --quiet "$unit" && systemctl is-active --quiet "$unit"; then
    return 1
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would run: systemctl enable --now %s\n' "$unit"
    return 0
  fi
  if ! systemctl enable --now "$unit"; then
    return 2
  fi
  record_action "systemctl enable --now ${unit}"
  if ! systemctl is-enabled --quiet "$unit"; then
    return 2
  fi
  return 0
}

# Reads enable_unit's status into UNIT_RC. set -e treats a bare non-zero as fatal.
run_enable() {
  local unit="$1"
  if enable_unit "$unit"; then
    UNIT_RC=0
  else
    UNIT_RC=$?
  fi
}

has_baseline_snapshot() {
  local out
  # Prefer JSON when this snapper has it. The table layout has gained columns
  # over time, so a fixed field number is not a safe check.
  if out=$(snapper --jsonout -c home list 2>/dev/null) && [[ "$out" =~ ^[[:space:]]*\{ ]]; then
    grep -Eq '"description"[[:space:]]*:[[:space:]]*"baseline"' <<<"$out"
    return
  fi
  snapper -c home list | grep -Eq '\|[[:space:]]*baseline[[:space:]]*\|'
}

apply_home_keys() {
  local file="/etc/snapper/configs/home"
  local key value current allow
  local -a snap_keys=(
    TIMELINE_CREATE yes
    TIMELINE_CLEANUP yes
    TIMELINE_LIMIT_HOURLY 6
    TIMELINE_LIMIT_DAILY 7
    TIMELINE_LIMIT_WEEKLY 4
    TIMELINE_LIMIT_MONTHLY 2
    TIMELINE_LIMIT_YEARLY 0
    NUMBER_LIMIT 10
    FREE_LIMIT 0.25
    SYNC_ACL yes
  )
  local i=0
  while [[ $i -lt ${#snap_keys[@]} ]]; do
    key=${snap_keys[$i]}
    value=${snap_keys[$((i + 1))]}
    if write_key "$file" "$key" "$value"; then
      HOME_DIRTY=1
    fi
    i=$((i + 2))
  done

  allow=$(read_key "$file" ALLOW_USERS || true)
  if [[ -n "$TARGET_USER" ]]; then
    if ! word_in_list "$TARGET_USER" "$allow"; then
      if [[ -z "$allow" ]]; then
        write_key "$file" ALLOW_USERS "$TARGET_USER" || true
      else
        write_key "$file" ALLOW_USERS "${allow} ${TARGET_USER}" || true
      fi
      HOME_DIRTY=1
    fi
  elif [[ -z "$allow" ]]; then
    add_check FAIL "home snapshots: ALLOW_USERS is empty; pass --user NAME or run via sudo from the login account"
    return 1
  fi
  return 0
}

verify_home_keys() {
  local file="/etc/snapper/configs/home"
  local key value got allow
  local -a snap_keys=(
    TIMELINE_CREATE yes
    TIMELINE_CLEANUP yes
    TIMELINE_LIMIT_HOURLY 6
    TIMELINE_LIMIT_DAILY 7
    TIMELINE_LIMIT_WEEKLY 4
    TIMELINE_LIMIT_MONTHLY 2
    TIMELINE_LIMIT_YEARLY 0
    NUMBER_LIMIT 10
    FREE_LIMIT 0.25
    SYNC_ACL yes
  )
  local i=0
  while [[ $i -lt ${#snap_keys[@]} ]]; do
    key=${snap_keys[$i]}
    value=${snap_keys[$((i + 1))]}
    got=$(read_key "$file" "$key" || true)
    if [[ "$got" != "$value" ]]; then
      add_check FAIL "home snapshots: ${key} is '${got}', wanted '${value}'"
      return 1
    fi
    i=$((i + 2))
  done
  allow=$(read_key "$file" ALLOW_USERS || true)
  if [[ -n "$TARGET_USER" ]]; then
    if ! word_in_list "$TARGET_USER" "$allow"; then
      add_check FAIL "home snapshots: ALLOW_USERS does not include the login account"
      return 1
    fi
  elif [[ -z "$allow" ]]; then
    add_check FAIL "home snapshots: ALLOW_USERS is empty"
    return 1
  fi
  return 0
}

home_snapshots_apply() {
  local fs ino config
  HOME_DIRTY=0
  fs=$(stat -f -c %T /home 2>/dev/null || true)
  ino=$(stat -c %i /home 2>/dev/null || true)
  if [[ "$fs" != "btrfs" || "$ino" != "256" ]]; then
    add_check skip "home snapshots: /home is not its own btrfs subvolume (fstype=${fs:-unknown}, inode=${ino:-unknown}); left unchanged"
    return 0
  fi
  if ! command -v snapper >/dev/null 2>&1; then
    add_check FAIL "home snapshots: snapper is not installed; this script does not install packages"
    return 0
  fi

  config="/etc/snapper/configs/home"
  if [[ ! -f "$config" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      printf 'would run: snapper -c home create-config /home\n'
      printf 'would set timeline limits, NUMBER_LIMIT, FREE_LIMIT, SYNC_ACL, ALLOW_USERS\n'
      printf 'would enable snapper-timeline.timer and snapper-cleanup.timer\n'
      printf 'would create a baseline snapshot when none exists\n'
      if [[ -z "$TARGET_USER" ]]; then
        add_check FAIL "home snapshots: dry-run would create the home config, but no login account was given; pass --user NAME"
      else
        add_check ok "home snapshots: dry-run, would create the home config"
      fi
      return 0
    fi
    if ! snapper -c home create-config /home; then
      add_check FAIL "home snapshots: snapper -c home create-config /home failed"
      return 0
    fi
    record_action "snapper -c home create-config /home"
  fi

  if ! ensure_snapper_configs_has_home; then
    return 0
  fi
  if ! apply_home_keys; then
    return 0
  fi

  local unit
  for unit in snapper-timeline.timer snapper-cleanup.timer; do
    if ! systemctl cat "$unit" >/dev/null 2>&1; then
      add_check FAIL "home snapshots: ${unit} is not installed; this script does not install packages"
      return 0
    fi
    run_enable "$unit"
    if [[ "$UNIT_RC" -eq 2 ]]; then
      add_check FAIL "home snapshots: could not enable ${unit}"
      return 0
    fi
    if [[ "$UNIT_RC" -eq 0 ]]; then
      HOME_DIRTY=1
    fi
  done

  if has_baseline_snapshot; then
    :
  elif [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would run: snapper -c home create --description baseline\n'
    HOME_DIRTY=1
  else
    if ! snapper -c home create --description baseline; then
      add_check FAIL "home snapshots: could not create the baseline snapshot"
      return 0
    fi
    record_action "snapper -c home create --description baseline"
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ "$HOME_DIRTY" -eq 0 ]]; then
      add_check ok "home snapshots: already configured (timeline on, hourly 6, daily 7, weekly 4, monthly 2, yearly 0, NUMBER_LIMIT 10, FREE_LIMIT 0.25, timers enabled, baseline present)"
    else
      add_check ok "home snapshots: dry-run, would set the limits, timers, and a baseline snapshot if it is missing"
    fi
    return 0
  fi
  if ! verify_home_keys; then
    return 0
  fi
  if ! has_baseline_snapshot; then
    add_check FAIL "home snapshots: baseline snapshot is missing after create"
    return 0
  fi
  for unit in snapper-timeline.timer snapper-cleanup.timer; do
    if ! systemctl is-enabled --quiet "$unit"; then
      add_check FAIL "home snapshots: ${unit} is not enabled"
      return 0
    fi
  done
  add_check ok "home snapshots: timeline on, hourly 6, daily 7, weekly 4, monthly 2, yearly 0, NUMBER_LIMIT 10, FREE_LIMIT 0.25, timers enabled, baseline present"
}

home_snapshots() {
  printf '== home snapshots ==\n'
  home_snapshots_apply
  note_root_timeline
}

coredump_caps() {
  printf '== coredump caps ==\n'
  local path="/etc/systemd/coredump.conf.d/50-caps.conf"
  local tmp
  tmp=$(new_tmp)
  cat >"$tmp" <<'EOF'
# Cap systemd-coredump so one large process cannot fill the disk.
[Coredump]
ProcessSizeMax=2G
ExternalSizeMax=2G
MaxUse=5G
EOF
  if [[ -f "$path" ]] && cmp -s "$path" "$tmp"; then
    add_check ok "coredump caps: ProcessSizeMax=2G ExternalSizeMax=2G MaxUse=5G"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would write %s and run systemctl daemon-reload\n' "$path"
    add_check ok "coredump caps: dry-run, would write 50-caps.conf"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  backup_once "$path"
  install -m 644 "$tmp" "$path"
  if ! systemctl daemon-reload; then
    add_check FAIL "coredump caps: systemctl daemon-reload failed"
    return 0
  fi
  record_action "systemctl daemon-reload after coredump caps"
  if ! cmp -s "$path" "$tmp"; then
    add_check FAIL "coredump caps: 50-caps.conf does not match after write"
    return 0
  fi
  add_check ok "coredump caps: ProcessSizeMax=2G ExternalSizeMax=2G MaxUse=5G"
}

paccache_step() {
  printf '== paccache ==\n'
  local out
  if [[ -e /var/lib/pacman/db.lck ]]; then
    add_check skip "paccache: skipped because /var/lib/pacman/db.lck exists; re-run when pacman is finished"
    return 0
  fi
  if ! command -v paccache >/dev/null 2>&1; then
    add_check skip "paccache: not installed (package pacman-contrib); this script does not install packages"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    if ! out=$(paccache -rk2 -d 2>&1); then
      printf '%s\n' "$out"
      add_check FAIL "paccache: paccache -rk2 -d failed"
      return 0
    fi
    printf '%s\n' "$out"
  else
    if ! out=$(paccache -rk2 2>&1); then
      printf '%s\n' "$out"
      add_check FAIL "paccache: paccache -rk2 failed"
      return 0
    fi
    printf '%s\n' "$out"
    if grep -q 'removing ' <<<"$out"; then
      record_action "paccache -rk2 removed cached packages (not restorable from this backup)"
    fi
  fi
  if ! systemctl cat paccache.timer >/dev/null 2>&1; then
    add_check skip "paccache: paccache.timer is not installed; this script does not install packages"
    return 0
  fi
  run_enable paccache.timer
  if [[ "$UNIT_RC" -eq 2 ]]; then
    add_check FAIL "paccache: could not enable paccache.timer"
    return 0
  fi
  if [[ "$UNIT_RC" -eq 1 ]]; then
    add_check ok "paccache: kept 2 package versions; paccache.timer already enabled"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    add_check ok "paccache: dry-run, would keep 2 package versions and enable paccache.timer"
    return 0
  fi
  add_check ok "paccache: kept 2 package versions; paccache.timer enabled"
}

scrub_step() {
  printf '== btrfs scrub ==\n'
  local fs unit
  unit="btrfs-scrub@-.timer"
  fs=$(stat -f -c %T / 2>/dev/null || true)
  if [[ "$fs" != "btrfs" ]]; then
    add_check skip "btrfs scrub: / is ${fs:-unknown}, not btrfs; left unchanged"
    return 0
  fi
  if ! systemctl cat "btrfs-scrub@.timer" >/dev/null 2>&1 && ! systemctl cat "$unit" >/dev/null 2>&1; then
    add_check skip "btrfs scrub: btrfs-scrub@.timer is not installed; this script does not install packages"
    return 0
  fi
  run_enable "$unit"
  if [[ "$UNIT_RC" -eq 2 ]]; then
    add_check FAIL "btrfs scrub: could not enable btrfs-scrub@-.timer"
    return 0
  fi
  if [[ "$UNIT_RC" -eq 1 ]]; then
    add_check ok "btrfs scrub: btrfs-scrub@-.timer already enabled (one monthly scrub of / covers every subvolume)"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    add_check ok "btrfs scrub: dry-run, would enable btrfs-scrub@-.timer"
    return 0
  fi
  add_check ok "btrfs scrub: btrfs-scrub@-.timer enabled (one monthly scrub of / covers every subvolume)"
}

group_or_world_writable() {
  local path="$1"
  local mode
  mode=$(stat -c %a "$path")
  mode=${mode: -3}
  (( (8#$mode & 8#022) != 0 ))
}

ssh_key_problem() {
  local home="$1"
  local ssh_dir="${home}/.ssh"
  local key_file="${ssh_dir}/authorized_keys"
  local owner count
  if [[ -z "$home" || ! -d "$home" ]]; then
    printf 'home directory missing'
    return 1
  fi
  if [[ -L "$home" || -L "$ssh_dir" || -L "$key_file" ]]; then
    printf 'home, .ssh, or authorized_keys is a symlink'
    return 1
  fi
  if [[ ! -d "$ssh_dir" || ! -f "$key_file" ]]; then
    printf 'no authorized_keys file'
    return 1
  fi
  count=$(ssh-keygen -l -f "$key_file" 2>/dev/null | wc -l | tr -d ' ' || true)
  if [[ "${count:-0}" -lt 1 ]]; then
    printf 'ssh-keygen found no key'
    return 1
  fi
  owner=$(stat -c %U "$home")
  if [[ "$owner" != "$TARGET_USER" ]] || group_or_world_writable "$home"; then
    printf 'home ownership or mode is not safe for sshd'
    return 1
  fi
  owner=$(stat -c %U "$ssh_dir")
  if [[ "$owner" != "$TARGET_USER" ]] || group_or_world_writable "$ssh_dir"; then
    printf '.ssh ownership or mode is not safe for sshd'
    return 1
  fi
  owner=$(stat -c %U "$key_file")
  if [[ "$owner" != "$TARGET_USER" ]] || group_or_world_writable "$key_file"; then
    printf 'authorized_keys ownership or mode is not safe for sshd'
    return 1
  fi
  printf 'ok'
  return 0
}

reload_sshd() {
  if systemctl cat sshd.service >/dev/null 2>&1; then
    systemctl reload sshd
    return 0
  fi
  if systemctl cat ssh.service >/dev/null 2>&1; then
    systemctl reload ssh
    return 0
  fi
  return 1
}

ssh_step() {
  printf '== ssh key-only ==\n'
  local path="/etc/ssh/sshd_config.d/50-no-password.conf"
  local tmp home problem
  if ! command -v sshd >/dev/null 2>&1; then
    add_check skip "ssh key-only: sshd is not installed; left unchanged"
    return 0
  fi
  if [[ ! -f /etc/ssh/sshd_config ]]; then
    add_check skip "ssh key-only: /etc/ssh/sshd_config is missing; left unchanged"
    return 0
  fi
  if ! grep -Eq '^[[:space:]]*Include[[:space:]]+"?/etc/ssh/sshd_config\.d/\*\.conf"?' /etc/ssh/sshd_config; then
    add_check FAIL "ssh key-only: sshd_config does not include /etc/ssh/sshd_config.d/*.conf; not writing a drop-in"
    return 0
  fi
  if [[ -z "$TARGET_USER" ]]; then
    add_check skip "ssh key-only: no login account (pass --user NAME or use sudo); left unchanged"
    return 0
  fi
  home=$(getent passwd "$TARGET_USER" | cut -d: -f6)
  problem=$(ssh_key_problem "$home" || true)
  tmp=$(new_tmp)
  cat >"$tmp" <<'EOF'
# Key-only SSH for OpenSSH. Tailscale SSH is a separate path and is not changed here.
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF
  if [[ -f "$path" ]] && ! cmp -s "$path" "$tmp"; then
    add_check FAIL "ssh key-only: ${path} exists and differs; not overwriting"
    return 0
  fi
  if [[ "$problem" != "ok" ]]; then
    if [[ -f "$path" ]]; then
      add_check FAIL "ssh key-only: drop-in is already in place but the login account's keys are not usable (${problem})"
    else
      add_check skip "ssh key-only: not enabled (${problem})"
    fi
    return 0
  fi
  if [[ -f "$path" ]] && cmp -s "$path" "$tmp"; then
    if ! sshd -t; then
      add_check FAIL "ssh key-only: sshd -t failed; the existing drop-in was left in place and sshd was not reloaded"
      return 0
    fi
    add_check ok "ssh key-only: PasswordAuthentication no, KbdInteractiveAuthentication no. Test a new key login before you close this session. Tailscale SSH is not affected."
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'would write %s, run sshd -t, and reload sshd only if the test passes\n' "$path"
    add_check ok "ssh key-only: dry-run, would install the drop-in after sshd -t"
    return 0
  fi
  ENSURE_HAD=0
  if [[ -f "$path" ]]; then
    ENSURE_HAD=1
  fi
  mkdir -p "$(dirname "$path")"
  backup_once "$path"
  install -m 644 "$tmp" "$path"
  if ! sshd -t; then
    if [[ "$ENSURE_HAD" -eq 1 ]]; then
      cp -a "${BACKUP_DIR}${path}" "$path"
      printf 'rolled back %s after sshd -t failed\n' "$path" >>"$BACKUP_DIR/MANIFEST"
    else
      rm -f "$path"
      printf 'removed %s after sshd -t failed (it was new)\n' "$path" >>"$BACKUP_DIR/MANIFEST"
    fi
    add_check FAIL "ssh key-only: sshd -t failed; the drop-in was rolled back and sshd was not reloaded"
    return 0
  fi
  if ! reload_sshd; then
    add_check FAIL "ssh key-only: drop-in installed and sshd -t passed, but reload failed. Test a new key login before you close this session."
    return 0
  fi
  record_action "reloaded sshd after key-only drop-in"
  add_check ok "ssh key-only: PasswordAuthentication no, KbdInteractiveAuthentication no. Test a new key login before you close this session. Tailscale SSH is not affected."
}

print_checks() {
  local line status message
  printf '\n-- checks --\n'
  for line in "${CHECKS[@]}"; do
    status=${line%%$'\t'*}
    message=${line#*$'\t'}
    printf '%-4s  %s\n' "$status" "$message"
  done
  if [[ -n "$BACKUP_DIR" ]]; then
    printf 'backup: %s\n' "$BACKUP_DIR"
  fi
  if [[ "$FAILURES" -eq 0 ]]; then
    printf 'result: ok\n'
    exit 0
  fi
  printf 'result: FAIL\n'
  exit 1
}

main() {
  parse_args "$@"
  if [[ "$(id -u)" -ne 0 ]]; then
    die "run as root: sudo scripts/sudo-maint.sh --dry-run" 1
  fi
  resolve_user
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run: no files will be written\n'
  fi
  home_snapshots
  coredump_caps
  paccache_step
  scrub_step
  ssh_step
  print_checks
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
