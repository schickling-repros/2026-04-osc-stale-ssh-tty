#!/usr/bin/env bash
# Demonstrates that `osc copy` writes OSC 52 to whatever $SSH_TTY points at,
# without checking that it matches the caller's controlling terminal.
#
# Run on a Linux host with at least one other active pty (any other terminal
# session works — the script picks one automatically).
#
# Requires: osc (https://github.com/theimpostor/osc) on PATH.

set -euo pipefail

if ! command -v osc >/dev/null; then
  echo "ERROR: osc not on PATH" >&2
  exit 1
fi

my_tty="$(tty)"
echo "Caller's controlling tty: $my_tty"

# Pick any other existing pts as a stand-in for a stale SSH_TTY.
other=""
for p in /dev/pts/*; do
  [ "$p" = "/dev/pts/ptmx" ] && continue
  [ "$p" = "$my_tty" ] && continue
  [ -c "$p" ] || continue
  other="$p"
  break
done

if [ -z "$other" ]; then
  echo "Need at least one other open pty. Open another terminal and rerun." >&2
  exit 1
fi

echo "Stale SSH_TTY (simulated):   $other"
echo

log="$(mktemp)"
sentinel="osc-ssh-tty-bug-$(date +%s)"
echo "Sentinel: $sentinel"

# Force a stale SSH_TTY and ask osc to copy.
# (Set on the osc invocation, not the printf, so the env reaches osc.)
printf '%s\n' "$sentinel" | SSH_TTY="$other" osc copy -v -l "$log" || true

echo
echo "--- osc verbose log ---"
cat "$log"
echo "-----------------------"
echo

target="$(grep -oE 'Using tty device: [^ ]+' "$log" | tail -1 | awk '{print $4}')"
echo "osc wrote OSC 52 to: $target"

if [ "$target" = "$other" ]; then
  echo
  echo "BUG CONFIRMED: osc wrote to \$SSH_TTY ($other) instead of the"
  echo "caller's controlling terminal ($my_tty). On a multi-user host,"
  echo "$other typically belongs to a different user — their terminal"
  echo "silently receives the clipboard payload."
  exit 0
elif [ "$target" = "$my_tty" ] || [ "$target" = "/dev/tty" ]; then
  echo
  echo "Not reproduced: osc resolved tty correctly. Bug is fixed in this build."
  exit 1
else
  echo
  echo "Unexpected target: $target"
  exit 2
fi
