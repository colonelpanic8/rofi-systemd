#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(CDPATH=; cd -- "$(dirname -- "$0")/.." && pwd)
SCRIPT_UNDER_TEST="$REPO_ROOT/rofi-systemd"
TEST_SHELL=$(command -v sh)
TMPDIR=$(mktemp -d)
BIN_DIR="$TMPDIR/bin"
LOG_DIR="$TMPDIR/logs"
STATE_DIR="$TMPDIR/state"

mkdir -p "$BIN_DIR" "$LOG_DIR" "$STATE_DIR"

cleanup() {
  rm -rf "$TMPDIR"
}

trap cleanup EXIT

cat >"$BIN_DIR/busctl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/busctl.log"

scope=$1
shift

maybe_block() {
  if [ -z "${TEST_BUSCTL_BLOCK_SCOPE-}" ] || [ "$scope" != "$TEST_BUSCTL_BLOCK_SCOPE" ]; then
    return
  fi

  if [ -n "${TEST_BUSCTL_BLOCK_STARTED_FILE-}" ]; then
    : >"$TEST_BUSCTL_BLOCK_STARTED_FILE"
  fi

  while [ -n "${TEST_BUSCTL_RELEASE_FILE-}" ] && [ ! -f "$TEST_BUSCTL_RELEASE_FILE" ]; do
    sleep 0.01
  done
}

print_json() {
  value=$1
  fallback=$2

  if [ -n "$value" ]; then
    printf '%s\n' "$value"
  else
    printf '%s\n' "$fallback"
  fi
}

case "$*" in
  *" ListUnitFiles "*)
    maybe_block
    case "$scope" in
      --user)
        print_json "${TEST_BUSCTL_USER_UNIT_FILES_JSON-}" '{"type":"a(ss)","data":[[]]}'
        ;;
      --system)
        print_json "${TEST_BUSCTL_SYSTEM_UNIT_FILES_JSON-}" '{"type":"a(ss)","data":[[]]}'
        ;;
    esac
    ;;
  *" ListUnits "*)
    maybe_block
    case "$scope" in
      --user)
        print_json "${TEST_BUSCTL_USER_UNITS_JSON-}" '{"type":"a(ssssssouso)","data":[[]]}'
        ;;
      --system)
        print_json "${TEST_BUSCTL_SYSTEM_UNITS_JSON-}" '{"type":"a(ssssssouso)","data":[[]]}'
        ;;
    esac
    ;;
  *)
    echo "unexpected busctl invocation: $*" >&2
    exit 1
    ;;
esac
EOF

cat >"$BIN_DIR/rofi" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/rofi.log"
count_file="$TEST_STATE_DIR/rofi-count"
count=0
if [ -f "$count_file" ]; then
  count=$(cat "$count_file")
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"

response_var="TEST_ROFI_RESPONSE_$count"
exit_code_var="TEST_ROFI_EXIT_CODE_$count"

eval "response=\${$response_var-}"
eval "exit_code=\${$exit_code_var-0}"

cat >/dev/null

printf '%s' "$response"
exit "$exit_code"
EOF

cat >"$BIN_DIR/systemctl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/systemctl.log"

case " $* " in
  *" status "*)
    printf 'status for %s\n' "$*"
    ;;
  *)
    printf 'ok\n'
    ;;
esac
EOF

cat >"$BIN_DIR/journalctl" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/journalctl.log"
printf 'journal for %s\n' "$*"
EOF

cat >"$BIN_DIR/sudo" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/sudo.log"
exec "$@"
EOF

cat >"$BIN_DIR/less" <<'EOF'
#!/bin/sh
cat >/dev/null
EOF

cat >"$BIN_DIR/fake-term" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >>"$TEST_LOG_DIR/term.log"
exit 0
EOF

chmod +x "$BIN_DIR"/*

export PATH="$BIN_DIR:$PATH"
export TEST_LOG_DIR="$LOG_DIR"
export TEST_STATE_DIR="$STATE_DIR"

reset_state() {
  : >"$LOG_DIR/busctl.log"
  : >"$LOG_DIR/rofi.log"
  : >"$LOG_DIR/systemctl.log"
  : >"$LOG_DIR/journalctl.log"
  : >"$LOG_DIR/sudo.log"
  : >"$LOG_DIR/term.log"
  rm -f "$STATE_DIR/rofi-count"
  rm -f "$STATE_DIR"/busctl-* "$STATE_DIR"/release-*
  unset TEST_ROFI_RESPONSE_1 TEST_ROFI_RESPONSE_2 TEST_ROFI_EXIT_CODE_1 TEST_ROFI_EXIT_CODE_2
  unset TEST_BUSCTL_USER_UNIT_FILES_JSON TEST_BUSCTL_SYSTEM_UNIT_FILES_JSON
  unset TEST_BUSCTL_USER_UNITS_JSON TEST_BUSCTL_SYSTEM_UNITS_JSON
  unset TEST_BUSCTL_BLOCK_SCOPE TEST_BUSCTL_BLOCK_STARTED_FILE TEST_BUSCTL_RELEASE_FILE
  unset ROFI_SYSTEMD_DEFAULT_ACTION ROFI_SYSTEMD_FORCE_INLINE ROFI_SYSTEMD_GET_UNITS_STRATEGY
  unset ROFI_SYSTEMD_MANAGER_COLUMN_WIDTH ROFI_SYSTEMD_STATUS_COLUMN_WIDTH ROFI_SYSTEMD_TERM
  unset ROFI_SYSTEMD_TRUNCATE_LENGTH ROFI_SYSTEMD_UNIT_COLUMN_WIDTH
}

assert_contains() {
  local file=$1
  local needle=$2
  if ! grep -F -- "$needle" "$file" >/dev/null; then
    echo "expected to find in $file: $needle" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_empty() {
  local file=$1
  if [ -s "$file" ]; then
    echo "expected $file to be empty" >&2
    echo "--- $file ---" >&2
    cat "$file" >&2
    exit 1
  fi
}

wait_for_file() {
  local file=$1
  local attempts=0
  while [ "$attempts" -lt 200 ]; do
    if [ -f "$file" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.01
  done

  echo "timed out waiting for $file" >&2
  exit 1
}

wait_for_nonempty_file() {
  local file=$1
  local attempts=0
  while [ "$attempts" -lt 200 ]; do
    if [ -s "$file" ]; then
      return 0
    fi
    attempts=$((attempts + 1))
    sleep 0.01
  done

  echo "timed out waiting for content in $file" >&2
  exit 1
}

run_inline() {
  ROFI_SYSTEMD_FORCE_INLINE=1 "$TEST_SHELL" "$SCRIPT_UNDER_TEST" "$@" >/dev/null
}

test_selection_uses_full_unit_name() {
  reset_state
  export ROFI_SYSTEMD_GET_UNITS_STRATEGY=files
  export TEST_BUSCTL_USER_UNIT_FILES_JSON='{"type":"a(ss)","data":[[]]}'
  export TEST_BUSCTL_SYSTEM_UNIT_FILES_JSON='{"type":"a(ss)","data":[[["very-long-unit-name-that-would-have-been-truncated-by-the-old-script.service","enabled"]]]}'
  export TEST_ROFI_RESPONSE_1=0
  export TEST_ROFI_EXIT_CODE_1=0
  export TEST_ROFI_RESPONSE_2=status
  export TEST_ROFI_EXIT_CODE_2=0

  run_inline

  assert_contains "$LOG_DIR/systemctl.log" "--system status --no-pager -- very-long-unit-name-that-would-have-been-truncated-by-the-old-script.service"
}

test_system_status_avoids_sudo() {
  reset_state
  run_inline --run-action status demo.service system

  assert_contains "$LOG_DIR/systemctl.log" "--system status --no-pager -- demo.service"
  assert_empty "$LOG_DIR/sudo.log"
}

test_restart_uses_sudo_then_status() {
  reset_state
  run_inline --run-action restart demo.service system

  assert_contains "$LOG_DIR/sudo.log" "systemctl --system restart -- demo.service"
  assert_contains "$LOG_DIR/systemctl.log" "--system status --no-pager -- demo.service"
}

test_user_tail_uses_user_unit_flag() {
  reset_state
  run_inline --run-action tail demo.service user

  assert_contains "$LOG_DIR/journalctl.log" "--user-unit=demo.service -f"
}

test_non_tty_relaunches_through_terminal_command() {
  reset_state
  export ROFI_SYSTEMD_TERM=fake-term
  "$TEST_SHELL" "$SCRIPT_UNDER_TEST" --run-action status demo.service system >/dev/null

  assert_contains "$LOG_DIR/term.log" "$SCRIPT_UNDER_TEST --run-action status demo.service system"
}

test_rofi_starts_before_unit_enumeration_finishes() {
  local blocked_file="$STATE_DIR/busctl-blocked"
  local release_file="$STATE_DIR/release-busctl"

  reset_state
  export ROFI_SYSTEMD_DEFAULT_ACTION=status
  export ROFI_SYSTEMD_FORCE_INLINE=1
  export ROFI_SYSTEMD_GET_UNITS_STRATEGY=files
  export TEST_BUSCTL_USER_UNIT_FILES_JSON='{"type":"a(ss)","data":[[["user-demo.service","enabled"]]]}'
  export TEST_BUSCTL_SYSTEM_UNIT_FILES_JSON='{"type":"a(ss)","data":[[["system-demo.service","enabled"]]]}'
  export TEST_BUSCTL_BLOCK_SCOPE=--system
  export TEST_BUSCTL_BLOCK_STARTED_FILE="$blocked_file"
  export TEST_BUSCTL_RELEASE_FILE="$release_file"
  export TEST_ROFI_RESPONSE_1=0
  export TEST_ROFI_EXIT_CODE_1=0

  "$TEST_SHELL" "$SCRIPT_UNDER_TEST" >/dev/null 2>&1 &
  local script_pid=$!

  wait_for_file "$blocked_file"
  wait_for_nonempty_file "$LOG_DIR/rofi.log"
  assert_contains "$LOG_DIR/rofi.log" "-dmenu -i -p systemd unit:"

  : >"$release_file"
  wait "$script_pid"
}

test_selection_uses_full_unit_name
test_system_status_avoids_sudo
test_restart_uses_sudo_then_status
test_user_tail_uses_user_unit_flag
test_non_tty_relaunches_through_terminal_command
test_rofi_starts_before_unit_enumeration_finishes

echo "ok"
