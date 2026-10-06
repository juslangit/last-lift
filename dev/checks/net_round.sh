#!/usr/bin/env bash
## A real online round, headless: one host with bots and two clients on autopilot,
## connected over ENet on this computer. Checks that everyone reaches the lobby crash
## and that every peer saw the same results.
set -u
cd "$(dirname "$0")/../.."
G="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
LOGS=dev/logs
mkdir -p "$LOGS"
PORT_ARGS=""
ROUNDS="${ROUNDS:-1}"

"$G" --headless --path . -- --host --name=Host --bots=5 --autostart=3 --autopilot \
	--rounds="$ROUNDS" --quit --log > "$LOGS/host.log" 2>&1 &
HOST=$!
sleep 2
"$G" --headless --path . -- --join=127.0.0.1 --name=Ana --autopilot --rounds="$ROUNDS" --quit --log > "$LOGS/ana.log" 2>&1 &
A=$!
"$G" --headless --path . -- --join=127.0.0.1 --name=Ben --autopilot --rounds="$ROUNDS" --quit --log > "$LOGS/ben.log" 2>&1 &
B=$!

for i in $(seq 1 $((ROUNDS * 150))); do
	sleep 1
	if ! kill -0 $HOST 2>/dev/null && ! kill -0 $A 2>/dev/null && ! kill -0 $B 2>/dev/null; then break; fi
done
kill $HOST $A $B 2>/dev/null

fail=0
check() { if eval "$2"; then echo "  ok    $1"; else echo "  FAIL  $1"; fail=1; fi; }
results() { grep -o 'RESULT round=[0-9]* name=[A-Za-z]* haul=[0-9]* total=[0-9]* survived=[a-z]*' "$1" | sort; }

check "host finished $ROUNDS round(s)" "[ \$(grep -c 'phase results' $LOGS/host.log) -ge $ROUNDS ]"
check "Ana was welcomed into the lobby" "grep -q 'welcomed: phase lobby' $LOGS/ana.log"
check "Ben was welcomed into the lobby" "grep -q 'welcomed: phase lobby' $LOGS/ben.log"
check "clients saw the doors open" "grep -q 'phase open' $LOGS/ana.log && grep -q 'phase open' $LOGS/ben.log"
check "clients reached the lobby crash" "grep -q 'phase crash' $LOGS/ana.log && grep -q 'phase crash' $LOGS/ben.log"
check "clients picked up loot over the network" "grep -qE 'PICKUP (Ana|Ben) took' $LOGS/host.log"
check "Ana's results match the host's" "[ \"\$(results $LOGS/host.log)\" = \"\$(results $LOGS/ana.log)\" ]"
check "Ben's results match the host's" "[ \"\$(results $LOGS/host.log)\" = \"\$(results $LOGS/ben.log)\" ]"
check "no script errors anywhere" "! grep -hE 'SCRIPT ERROR|Invalid|Nonexistent|Parse Error' $LOGS/*.log"
echo
results $LOGS/host.log
exit $fail
