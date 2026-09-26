# Kimi folder-trust pre-registration - live validation

Real Kimi Code 2.1.1 (`~/.kimi-code/bin/kimi`), real tmux on a private lab socket, real `bin/fm-spawn.sh` in a disposable lab FM_HOME. Nothing was written to the operator's own Kimi store, treehouse pools or fleet state.

## The user-visible result, from two real kimi crewmate spawns in the same lab

WITHOUT the pre-registration (trust store deliberately made unwritable) - the worker's pane stops on the vendor dialog:

```
  Trust this folder?
  ↑↓ navigate · Enter select · Esc exit
  /private/var/folders/9m/0zwy5dlx3h51v4rxb2pxkmvr0000gn/T/fm-lab.WM9wCF/.treehouse/proj-e9c6de/4/proj
  Project-level MCP servers are disabled until you explicitly choose Trust. Trust starts the listed project MCP targets and remembers this folder.
   ❯ Trust this folder
     Enable project MCP servers. Remembered for this folder.
     Don't trust
     Exit Kimi Code. Asked again next launch.
```

WITH the pre-registration - the same spawn shape reaches the composer and the brief pointer, and the dialog is never drawn in 180 pane samples:

```
 │  ▐█▛█▛█▌  Welcome to Kimi Code!                                                                                                                                                                                        │
 │  ▐█████▌  Send /help for help information.                                                                                                                                                                             │
 │                                                                                                                                                                                                                        │
 │  Directory: /private/var/folders/9m/0zwy5dlx3h51v4rxb2pxkmvr0000gn/T/fm-lab.WM9wCF/.treehouse/proj-e9c6de/5/proj                                                                                                       │
 │  Session:   session_c3e89c98-ce1c-4221-ab5c-fa3709413012                                                                                                                                                               │
 │  Model:     K3                                                                                                                                                                                                         │
 │  Version:   2.1.1                                                                                                                                                                                                      │
 │                                                                                                                                                                                                                        │
 ╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
 ✦ Kimi Code Desktop is here — Everything you love about Kimi Code, now on desktop
   Run /desktop or visit https://www.kimi.com/code to install
   No session yet — one will be created on your first message.
   tmux extended-keys is off. Modified Enter keys may not work. Add `set -g extended-keys on` to ~/.tmux.conf and restart tmux.
 ✨ Read the brief at /private/var/folders/9m/0zwy5dlx3h51v4rxb2pxkmvr0000gn/T/fm-lab.WM9wCF/data/kimi-live-pretrust2/launch-brief.md and follow it exactly.
   Error: [internal] Stored token for "kimi-code" was rejected; re-login required.
   If this persists, run `/export-debug-zip` and share the file with us for diagnosis. Please don't share it publicly.
 ╭────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
 │ >                                                                                                                                                                                                                      │
 ╰────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
 Never Ask  K3 thinking: high  …/proj-e9c6de/5/proj                                                                                                                            /web: use the Web UI for a better experience
                                                                                                                                                                                                        context: 1% (39/1M)
```

## Pane sampling during each spawn (0.3s interval)

| spawn | pre-registered | pane samples | samples showing "Trust this folder?" | spawn exit |
|---|---|---|---|---|
| kimi-live-pretrust2 | yes | 180 | 0 | 0 (brief delivered) |
| kimi-live-nopretrust | no (store malformed, registration refused) | 191 | 2 | 0 (dialog answered by the readiness gate, brief delivered) |

Full transcripts: live-01 .. live-08 in this directory.

## Notes

- The lab Kimi home carries a copied credential file and was deliberately never logged in, so the worker's first model call fails ("Stored token ... re-login required"). That is after the surface under test: the folder-trust dialog is decided before any model call, and both spawns still reached the composer and had the brief pointer delivered.
- The dialog is modal and stays until answered, so a 0.3s pane sample cannot miss it; live-03 additionally shows the same directory prompting without a record and going straight to the composer with one, on the same binary.
