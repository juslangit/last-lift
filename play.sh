#!/usr/bin/env bash
## Start Last Lift.
##   ./play.sh          the menu: host a game or join one
##   ./play.sh solo     straight into a hosted game with 7 bots
##   ./play.sh two      two windows on this Mac: a host with bots, and a second player joining it
cd "$(dirname "$0")"
G="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
case "${1:-}" in
	solo) exec "$G" --path . -- --host --bots=7 ;;
	two)
		"$G" --path . --position 40,60 --resolution 1280x720 -- --host --name=Host --bots=6 &
		sleep 2
		exec "$G" --path . --position 1360,60 --resolution 1280x720 -- --join=127.0.0.1 --name=Guest ;;
	*) exec "$G" --path . ;;
esac
