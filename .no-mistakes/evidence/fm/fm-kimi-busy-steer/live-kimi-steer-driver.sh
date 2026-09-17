#!/usr/bin/env bash
# no-mistakes test phase, live driver for the Kimi mid-turn steer.
#
# Drives the REAL product - bin/fm-send.sh and bin/fm-watch.sh from the gate
# worktree - against a REAL Kimi Code launched in a REAL tmux server on a
# private socket. Kimi is launched in the author's already-trusted verification
# scratchpad (Kimi trusts folders per exact path and the fresh gate worktree is
# not trusted; accepting the dialog would persist user-level Kimi config, which
# this phase must not do). Everything the product writes lands in a temp LAB
# home; evidence goes to the evidence dir.
#
# Scenarios driven, in order:
#   S1 fm-send steers a doorbell that a mid-turn Kimi queued (one Ctrl-S,
#      reported "steered"), and the doorbell is echoed into the running turn.
#   S2 the watcher re-rings the still-unhandled record while Kimi stays
#      mid-turn: every re-ring is steered, the ladder count stays 0, and no
#      "unread firstmate instruction" stale wake is queued past the default
#      3-attempt budget (the false alarm the intent names).
#   S3 when the long tool call ends, Kimi acts on the injected instruction
#      (touches the acted file) and acks it (mv into handled/) with no re-ring
#      needed after the turn ends; the watcher goes quiet.
#   S4 an idle Kimi gets no steer: fm-send does not report "steered" and the
#      doorbell is honored directly.
set -u

ROOT=/Users/lele/.no-mistakes/worktrees/797acbb20279/01M2Q0XA6QDXYFVVN1TE9MT10C
EV=/Users/lele/.no-mistakes/evidence/01M2Q0XA6QDXYFVVN1TE9MT10C
KIMI_CWD=/private/tmp/claude-501/-Users-lele--treehouse-firstmate-8bf1b0-1-firstmate/1330ebde-4029-49e8-af69-5d09c6807309/scratchpad/kimi-verify
KIMI_BIN="$HOME/.kimi-code/bin/kimi"
GRACE=${GRACE:-20}          # watcher re-ring spacing under test (default 90)
TOOL_SECS=${TOOL_SECS:-150} # length of Kimi's long tool call

export PATH="$HOME/.kimi-code/bin:$PATH"
export FM_GATE_REFUSE_BYPASS=1
unset NO_MISTAKES_GATE

SOCKET="fm-live-steer-$$"
SESSION=steerlive
WIN=hx-kimi
TASK=live-kimi-busy
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-live-steer.XXXXXX"); LAB=$(cd "$LAB" && pwd)
HOME_DIR="$LAB/home"; STATE="$HOME_DIR/state"; mkdir -p "$STATE"
FRAMES="$EV/frames"; mkdir -p "$FRAMES"
ACTED="$LAB/acted-midturn"
ACTED2="$LAB/acted-idle"
FAILED=0

SHIM="$LAB/shim"; mkdir -p "$SHIM"
REAL_TMUX=$(command -v tmux)
cat > "$SHIM/tmux" <<SH
#!/usr/bin/env bash
exec "$REAL_TMUX" -L "$SOCKET" "\$@"
SH
chmod +x "$SHIM/tmux"
PATH="$SHIM:$PATH"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-tmux-lib.sh"
# shellcheck source=/dev/null
. "$ROOT/bin/fm-task-inbox-lib.sh"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
ok()   { printf 'ok - %s\n' "$*"; }
nok()  { FAILED=1; printf 'not ok - %s\n' "$*"; }
pane() { tmux capture-pane -p -t "$SESSION:$WIN" 2>/dev/null || true; }
rows() { pane | grep '[^[:space:]]' | tail -"${1:-14}"; }
frame() {  # <name>
  { printf '# %s  (%s)  tmux capture-pane -p of %s:%s\n' "$1" "$(date '+%H:%M:%S')" "$SESSION" "$WIN"; pane; } > "$FRAMES/$1.txt"
}
ring_state() { cat "$STATE/$TASK.inbox/.ring-state" 2>/dev/null || printf '(absent)'; }

WATCH_PID=''; REC_PID=''
cleanup() {
  [ -z "$WATCH_PID" ] || kill "$WATCH_PID" 2>/dev/null || true
  [ -z "$REC_PID" ] || kill "$REC_PID" 2>/dev/null || true
  tmux kill-server 2>/dev/null || true
  rm -rf "$LAB"
}
trap cleanup EXIT

# Frame recorder: saves the bottom rows whenever they change, spinner rows
# stripped so the moon phase alone does not produce a frame.
recorder() {  # <prefix>
  local prefix=$1 last='' cur n=0
  while :; do
    cur=$(rows 16 | grep -v '· Tip:' | grep -v 'Press Ctrl+B')
    if [ "$cur" != "$last" ]; then
      n=$((n + 1))
      { printf '# %s frame %02d (%s)\n' "$prefix" "$n" "$(date '+%H:%M:%S')"; rows 16; } \
        > "$FRAMES/$(printf '%s-%02d' "$prefix" "$n").txt"
      last=$cur
    fi
    sleep 0.1
  done
}

log "kimi: $("$KIMI_BIN" --version 2>/dev/null | head -1)  tmux: $(tmux -V)  socket: $SOCKET"
log "LAB=$LAB  kimi cwd=$KIMI_CWD"

tmux new-session -d -s "$SESSION" -x 200 -y 50 -c "$KIMI_CWD"
tmux new-window -d -t "$SESSION:" -n "$WIN" -c "$KIMI_CWD" -- bash -lc "$KIMI_BIN --auto"

# --- readiness (mirrors the live guard's wait_ready: never Enter on a modal) ---
i=0; verdict=''
while [ "$i" -lt 90 ]; do
  verdict=$(fm_tmux_composer_state "$SESSION:$WIN")
  [ "$verdict" = empty ] && break
  if pane | grep -qi 'trust this folder'; then
    nok "kimi showed its folder-trust dialog in $KIMI_CWD; refusing to accept it (user-level config)"
    frame 00-trust-dialog
    exit 1
  fi
  i=$((i + 1))
  if [ "$i" -eq 30 ]; then tmux send-keys -t "$SESSION:$WIN" Escape; fi
  sleep 1
done
if [ "$verdict" != empty ]; then
  nok "kimi composer never read empty within 90s (last verdict: $verdict)"
  frame 00-not-ready; rows 20
  exit 1
fi
log "kimi ready (composer empty after ${i}s)"
frame 00-kimi-idle-ready
sleep 6

# --- put Kimi mid-turn: a long tool call ---
tmux send-keys -t "$SESSION:$WIN" -l "Run the shell command: sleep $TOOL_SECS ; then reply with the single word FINISHED."
sleep 1
tmux send-keys -t "$SESSION:$WIN" Enter
i=0
while [ "$i" -lt 60 ]; do
  pane | grep -q "sleep $TOOL_SECS" && pane | fm_busy_lines_match kimi && pane | grep -q 'Running a command' && break
  sleep 1; i=$((i + 1))
done
if [ "$i" -ge 60 ]; then
  nok "the long tool call never started; nothing mid-turn was reached"; frame 01-no-toolcall; rows 20
  exit 1
fi
T0=$(date +%s)
log "kimi mid-turn: 'sleep $TOOL_SECS' tool call running (busy footer matched)"
frame 01-midturn-before-doorbell

printf 'window=%s:%s\nkind=ship\nharness=kimi\n' "$SESSION" "$WIN" > "$STATE/$TASK.meta"
REC="$STATE/$TASK.inbox/001.msg"
HANDLED="$STATE/$TASK.inbox/handled/001.msg"

# --- S1: real fm-send against the mid-turn pane ---
recorder s1-fm-send & REC_PID=$!
sleep 0.5
FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$HOME_DIR" "$ROOT/bin/fm-send.sh" "$TASK" \
  "Firstmate live check: run exactly this shell command now: touch $ACTED - then follow the mv instruction you were given for this message. Reply with one short line." \
  > "$LAB/send1.out" 2> "$LAB/send1.err"; rc=$?
sleep 2
kill "$REC_PID" 2>/dev/null; wait "$REC_PID" 2>/dev/null; REC_PID=''
{ printf '# fm-send #1 (mid-turn kimi) exit=%s\n# stdout:\n' "$rc"; cat "$LAB/send1.out"; printf '# stderr:\n'; cat "$LAB/send1.err"; } > "$EV/s1-fm-send-midturn-output.txt"
cat "$EV/s1-fm-send-midturn-output.txt"
frame 02-after-fm-send-steer
[ "$rc" -eq 0 ] && ok "S1 fm-send exit 0 (steer durably recorded)" || nok "S1 fm-send exit $rc"
[ -f "$REC" ] && ok "S1 durable record written: $REC" || nok "S1 no durable record at $REC"
grep -q 'doorbell queued by a mid-turn kimi' "$LAB/send1.err" && grep -q 'steered into its running turn' "$LAB/send1.err" \
  && ok "S1 fm-send reported the doorbell as queued by a mid-turn kimi and steered (ring outcome 4)" \
  || nok "S1 fm-send did not report a steered doorbell"
if pane | fm_composer_kimi_queued_input; then nok "S1 queue block still on screen after fm-send: Ctrl-S did not inject"; else ok "S1 no queue block remains after the steer"; fi
pane | grep -q '✨ : Firstmate instruction waiting' && ok "S1 the doorbell was echoed into the running turn (✨ row)" || nok "S1 no ✨ echo of the doorbell in the running turn"
pane | fm_busy_lines_match kimi && ok "S1 kimi still mid-turn after the steer (busy footer)" || nok "S1 kimi no longer mid-turn; nothing mid-turn proven"
ls "$FRAMES"/s1-fm-send-*.txt >/dev/null 2>&1 && { for f in "$FRAMES"/s1-fm-send-*.txt; do grep -q '↑ to edit · ctrl-s to steer immediately' "$f" && { ok "S1 recorder caught Kimi's queue block before the steer: $(basename "$f")"; break; }; done; }

# --- S2: the real watcher re-rings while Kimi stays mid-turn ---
: > "$LAB/watch.out"
( PATH="$PATH" FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$HOME_DIR" FM_STATE_OVERRIDE="$STATE" \
  FM_POLL=1 FM_SIGNAL_GRACE=1 FM_CHECK_INTERVAL=999999 FM_HEARTBEAT=999999 \
  FM_TASK_INBOX_GRACE_SECS="$GRACE" \
  "$ROOT/bin/fm-watch.sh" > "$LAB/watch.out" 2> "$LAB/watch.err" ) & WATCH_PID=$!
log "watcher started pid=$WATCH_PID grace=${GRACE}s ring-max=default(3)"
recorder s2-watcher & REC_PID=$!

# Observe until the tool call ends (plus margin) or the record is acked.
deadline=$((T0 + TOOL_SECS + 45))
last_seen=''; steered_rerings=0; frames_n=0
: > "$EV/s2-watcher-ladder-timeline.txt"
while [ "$(date +%s)" -lt "$deadline" ]; do
  attempts=$(grep -c 'steer-inbox delivery attempt' "$STATE/.watch-triage.log" 2>/dev/null || echo 0)
  line="t+$(( $(date +%s) - T0 ))s ring-state=[$(ring_state)] triage-attempts=$attempts wake-queue=$([ -s "$STATE/.wake-queue" ] && printf 'PRESENT' || printf 'none') watcher=$(kill -0 "$WATCH_PID" 2>/dev/null && printf alive || printf exited) handled=$([ -f "$HANDLED" ] && printf yes || printf no) acted=$([ -e "$ACTED" ] && printf yes || printf no)"
  if [ "$line" != "$last_seen" ]; then printf '%s\n' "$line" >> "$EV/s2-watcher-ladder-timeline.txt"; last_seen=$line; fi
  [ -f "$HANDLED" ] && [ -e "$ACTED" ] && break
  kill -0 "$WATCH_PID" 2>/dev/null || break
  sleep 1
done
kill "$REC_PID" 2>/dev/null; wait "$REC_PID" 2>/dev/null; REC_PID=''
frame 03-after-toolcall-kimi-acted
cp "$STATE/.watch-triage.log" "$EV/s2-watcher-triage.log" 2>/dev/null || printf '(no triage log)\n' > "$EV/s2-watcher-triage.log"
cp "$STATE/.wake-queue" "$EV/s2-wake-queue.txt" 2>/dev/null || printf '(no .wake-queue was ever written)\n' > "$EV/s2-wake-queue.txt"
cp "$LAB/watch.out" "$EV/s2-watcher-stdout.txt"; cp "$LAB/watch.err" "$EV/s2-watcher-stderr.txt"
cat "$EV/s2-watcher-ladder-timeline.txt"
echo "--- triage log ---"; cat "$EV/s2-watcher-triage.log"
echo "--- watcher stdout ---"; cat "$EV/s2-watcher-stdout.txt"
echo "--- watcher stderr (tail) ---"; tail -5 "$EV/s2-watcher-stderr.txt"

steered=$(grep -c 'steer-inbox delivery attempt: .* result=4' "$EV/s2-watcher-triage.log" 2>/dev/null || echo 0)
plain=$(grep -c 'steer-inbox delivery attempt: .* result=0' "$EV/s2-watcher-triage.log" 2>/dev/null || echo 0)
[ "$steered" -ge 3 ] && ok "S2 the watcher re-rang a mid-turn kimi $steered times, each steered (result=4), past the default 3-attempt budget" \
  || nok "S2 expected >=3 steered watcher re-rings (result=4), got $steered (plain=$plain)"
grep -q 'unread firstmate instruction' "$EV/s2-wake-queue.txt" "$EV/s2-watcher-stdout.txt" 2>/dev/null \
  && nok "S2 FALSE ALARM: an 'unread firstmate instruction' stale wake was queued while kimi was mid-turn" \
  || ok "S2 no 'unread firstmate instruction' stale wake while kimi stayed mid-turn"
if grep -q 'ring-state=\[001.msg	[1-9]' "$EV/s2-watcher-ladder-timeline.txt"; then nok "S2 the ladder spent budget on a steered ring (count > 0 observed)"; else ok "S2 the ladder count never left 0 while every re-ring was steered"; fi
echo "--- queue-block/injection frames during watcher re-rings ---"; ls "$FRAMES" | grep -c 's2-watcher-' | sed 's/^/frames saved: /'
for f in "$FRAMES"/s2-watcher-*.txt; do grep -q '↑ to edit · ctrl-s to steer immediately' "$f" && { ok "S2 recorder caught the queue block during a watcher re-ring: $(basename "$f")"; break; }; done

# --- S3: Kimi acts and acks after the tool call ends ---
[ -e "$ACTED" ] && ok "S3 kimi ACTED on the injected instruction (touched $(basename "$ACTED"))" || nok "S3 kimi did not act (no $ACTED)"
[ -f "$HANDLED" ] && ok "S3 kimi ACKED the record (mv into handled/): $HANDLED" || nok "S3 record never acked: $REC"
sleep 3
due=$(FM_TASK_INBOX_GRACE_SECS="$GRACE" fm_task_inbox_due_action "$STATE" "$TASK" || true)
[ "$due" = quiet ] && ok "S3 ladder is quiet after the ack (due_action=quiet, ring-state=[$(ring_state)])" || nok "S3 ladder not quiet after ack: $due"
kill "$WATCH_PID" 2>/dev/null; wait "$WATCH_PID" 2>/dev/null; WATCH_PID=''

# --- S4: idle Kimi gets no steer ---
i=0
while [ "$i" -lt 60 ]; do
  [ "$(fm_tmux_composer_state "$SESSION:$WIN")" = empty ] && ! pane | fm_busy_lines_match kimi && break
  sleep 1; i=$((i + 1))
done
frame 04-kimi-idle-before-second-steer
FM_HOME="$HOME_DIR" FM_ROOT_OVERRIDE="$HOME_DIR" "$ROOT/bin/fm-send.sh" "$TASK" \
  "Firstmate live check 2: run exactly this shell command now: touch $ACTED2 - then follow the mv instruction you were given for this message. Reply with one short line." \
  > "$LAB/send2.out" 2> "$LAB/send2.err"; rc=$?
{ printf '# fm-send #2 (idle kimi) exit=%s\n# stdout:\n' "$rc"; cat "$LAB/send2.out"; printf '# stderr:\n'; cat "$LAB/send2.err"; } > "$EV/s4-fm-send-idle-output.txt"
cat "$EV/s4-fm-send-idle-output.txt"
[ "$rc" -eq 0 ] && ok "S4 fm-send exit 0 on idle kimi" || nok "S4 fm-send exit $rc"
grep -q 'steered' "$LAB/send2.err" && nok "S4 an idle kimi was reported steered" || ok "S4 idle kimi: fm-send did not report a steer (no Ctrl-S path taken)"
HANDLED2="$STATE/$TASK.inbox/handled/002.msg"
i=0
while [ "$i" -lt 180 ]; do [ -f "$HANDLED2" ] && [ -e "$ACTED2" ] && break; sleep 1; i=$((i + 1)); done
frame 05-kimi-idle-acted
[ -f "$HANDLED2" ] && [ -e "$ACTED2" ] && ok "S4 idle kimi read the doorbell directly, acted and acked (${i}s)" || nok "S4 idle kimi did not act/ack within 180s (acted=$([ -e "$ACTED2" ] && echo yes || echo no) acked=$([ -f "$HANDLED2" ] && echo yes || echo no))"

echo; echo "=== final pane (bottom rows) ==="; rows 24
[ "$FAILED" -eq 0 ] && { echo; echo "RESULT: all live scenarios passed"; exit 0; } || { echo; echo "RESULT: FAILURES above"; exit 1; }
