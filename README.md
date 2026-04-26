# osc — stale `SSH_TTY` causes silent clipboard leak to other users

`osc copy` (v0.4.8 and earlier) trusts the `SSH_TTY` environment variable
without checking that it matches the caller's controlling terminal.

When `SSH_TTY` is stale — e.g. when an SSH connection is reused by OpenSSH
`ControlMaster auto`, or a tmux session is reattached from a new SSH session,
or a mosh session migrates — the OSC 52 escape sequence is written to a
**different pty than the user's terminal**. On a multi-user host that other
pty often belongs to another logged-in user, who silently receives the
clipboard write in their terminal emulator.

## Reproduction

```bash
./repro.sh
```

The script forces a stale `SSH_TTY` (a real but unrelated pts on the same
host) and shows that `osc copy` writes its OSC 52 sequence to that unrelated
pts instead of the caller's actual tty.

## Expected

`osc copy` writes OSC 52 to the caller's controlling terminal (`/dev/tty`),
or refuses to run when it cannot identify a safe tty. In particular, it
should not write to a pty owned by a different user just because `SSH_TTY`
is stale.

## Actual

`osc copy` writes OSC 52 to whatever path `$SSH_TTY` points at, with no
validation. From `main.go:524-534` (v0.4.8):

```go
func ttyDevice() string {
    if deviceFlag != "" {
        return deviceFlag
    } else if isScreen {
        return "/dev/tty"
    } else if sshtty := os.Getenv("SSH_TTY"); sshtty != "" {
        return sshtty   // <-- trusted blindly
    } else {
        return "/dev/tty"
    }
}
```

## Real-world trigger (how I hit this)

- macOS client with `~/.ssh/config`:
  ```
  Host *
    ControlMaster auto
    ControlPath ~/.ssh/sockets/%r@%h-%p
  ```
- Multi-user Linux dev box with several active SSH sessions.
- Inside an SSH session: `tty` reports `/dev/pts/1543`, but
  `echo $SSH_TTY` reports `/dev/pts/0` (the master session's tty, which now
  belongs to a different user).
- `echo hello | osc copy` silently sends `\x1b]52;c;<base64>\x1b\\` to
  `/dev/pts/0` — the other user's terminal — and the local clipboard is
  never updated.

## Workarounds

- `osc copy -d /dev/tty`
- `SSH_TTY= osc copy`

## Suggested fix

Either drop the `SSH_TTY` branch entirely (controlling terminal `/dev/tty`
is correct in every case I can construct), or `stat()` `SSH_TTY` and only
use it when it matches the caller's controlling terminal / is owned by the
caller.

## Versions

- `osc`: 0.4.8 (also reproduces on `main` as of 2026-04-26)
- OS: NixOS, Linux 6.18, multi-user
- Client: macOS 25.2, OpenSSH with `ControlMaster auto`

## Related

- theimpostor/osc#7 — closed; same root cause via mosh's stale `SSH_TTY`
- theimpostor/osc#17 — open; addresses the tmux-reattach variant only

## Related Issue

https://github.com/theimpostor/osc/issues/19
