# pty-protocol

CLOS pseudo-terminal protocol for [cl-stack](https://github.com/egao1980/cl-stack). It runs a program attached to a pty, then reads and writes octets, resizes, signals and waits. Brief: [`cl-stack/docs/capabilities/pty.md`](https://github.com/egao1980/cl-stack/blob/main/docs/capabilities/pty.md) ([#270](https://github.com/egao1980/cl-stack/issues/270)).

| System | Role | Repo |
|--------|------|------|
| `pty-protocol` (`stack-pty`) | GFs, conditions, `spawn-pty` / `with-pty` | this repo |
| `pty-backend-native` | forkpty-style spawn on Unix, ConPTY on Windows (C, cross-built with Zig) | [`egao1980/pty-backend-native`](https://github.com/egao1980/pty-backend-native) |

```lisp
(asdf:load-system "pty-backend-native")

(stack-pty:with-pty (p '("sh" "-c" "stty size; exit 3") :cols 100 :rows 30)
  (list (stack-pty:pty-read p :timeout 2)   ; ⇒ octets of "30 100\r\n"
        (stack-pty:pty-wait p)))           ; ⇒ 3
```

- **Command:** a list of strings. `argv[0]` is searched in `PATH` unless it has a slash. There's no shell unless you ask for one.
- **Environment:** an alist merged over the parent's. `TERM` defaults to `xterm-256color`. Pass `:inherit-environment nil` for a clean slate.
- **`pty-read`:** returns octets, an empty vector on timeout, or `NIL` at EOF.
- **`pty-wait`:** returns `(values code signal)`, or `NIL` on timeout.
- **Errors:**
  - `pty-spawn-error` keeps the OS error code and offers `use-value` (try another command).
  - `pty-io-error` offers `continue` (drop the write).
  - Every operation on a closed pty signals `pty-closed-error`.

Pair it with [`terminal-protocol`](https://github.com/egao1980/terminal-protocol). Feed `pty-read` output into `terminal-feed`, and write `encode-key` bytes and the terminal's replies back with `pty-write`.

## License

MIT
