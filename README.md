# Last Lift

An online party game for 2–12 players. A skyscraper elevator is falling from floor 40. At each
stop the doors open for fourteen seconds on a random room: grab loot and get back in before
they shut. Anyone outside is left behind, and haunts the living as a ghost.

**Play in your browser:** https://juslangit.github.io/last-lift/
(desktop browser, mouse and keyboard)

- **Quickplay** puts you in a room with other players; bots fill the empty seats.
- **Play with friends** gives you a 4-digit room code and an invite link.

## How it's built
- Godot 4.7, GDScript. The host player's game is the authority; everyone else connects to it.
- In the browser, players connect over WebRTC. `relay/` is a small Cloudflare Worker that hands
  out room codes, finds Quickplay rooms and passes the WebRTC handshake; it never sees the game.
- The desktop build uses Steam lobbies instead (`addons/godotsteam`), or join by IP on the same Wi-Fi.

## Run it
- `./play.sh` (desktop), `./play.sh solo` (you + 7 bots), `./play.sh two` (two windows).
- Web build: `Godot --headless --path . --export-release "Web" build/web/index.html`, then serve
  `build/web/` (`python3 -m http.server`).
- Relay: `cd relay && npx wrangler deploy`.

Sounds: Kenney (CC0). Fonts: Bungee, Chakra Petch (OFL). See CREDITS.md.
