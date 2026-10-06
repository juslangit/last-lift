class_name Rules
extends RefCounted

## Every number the game is balanced on, and the pure functions built on them.
## Nothing here touches the scene tree, so dev/checks/_rules can test it headless.

const PORT := 7777
const MAX_PLAYERS := 12
const FULL_CAB := 8              # the host fills the lobby to this many with bots

# --- the round ---------------------------------------------------------------------------
const START_FLOOR := 40
const STEP_MIN := 6              # floors fallen between stops
const STEP_MAX := 9
const OPEN_TIME := 14.0          # seconds the doors stay open
const HOLD_EXTRA := 4.0          # the Door-Hold button, once per floor
const DOOR_ANIM := 0.8           # seconds for the doors to slide
const DESCENT_TIME := 5.0
const CRASH_TIME := 4.0
const OVERWEIGHT_GRACE := 6.0    # how long the doors refuse to close before the cable gives

# --- the cab -----------------------------------------------------------------------------
# Interior: x in [-CAB_HALF_W, CAB_HALF_W], z in [0, CAB_DEPTH]. The doors sit on z = 0 and
# open onto the room, which is built in negative z.
const CAB_HALF_W := 2.0
const CAB_DEPTH := 4.0
const CAB_HEIGHT := 3.0
const DOOR_HALF_W := 1.1
const INSIDE_MARGIN := 0.15      # your centre must be this far past the door line
const CAB_LIMIT_KG := 800.0
const PLAYER_KG := 70.0

# --- people ------------------------------------------------------------------------------
const WALK_SPEED := 4.2
const RUN_SPEED := 6.6
const JUMP_SPEED := 4.6
const GRAVITY := 14.0
const SLOTS := 3
const PICKUP_RANGE := 2.2
const SHOVE_RANGE := 1.9
const SHOVE_COOLDOWN := 1.0
const SHOVE_FORCE := 9.0

const PLAYER_COLORS := [
	Color("f2f2f2"), Color("e85d4a"), Color("4fa3e8"), Color("6ad08a"),
	Color("f0b13c"), Color("b07be0"), Color("e88ac0"), Color("9ad0e8"),
	Color("c9a24a"), Color("7a8bff"), Color("ff9d5c"), Color("8fe0c4"),
]
const BOT_NAMES := ["Aiko", "Bram", "Cleo", "Dmitri", "Esme", "Faisal", "Gus", "Hana", "Ivo", "Juno", "Kofi"]

# --- rooms and loot ----------------------------------------------------------------------
const ROOMS := ["office", "fire", "zoo"]
const ROOM_NAMES := {"office": "Office Party", "fire": "Server Farm Fire", "zoo": "Rooftop Zoo"}
const ROOM_HAZARDS := {
	"office": "Conga line on the loose",
	"fire": "Fire spreads row by row",
	"zoo": "Escaped gorilla",
}

# kind: [display name, value, kg, shape, colour, size]
const LOOT := {
	"cake":        ["Retirement cake", 120, 4.0, "cyl", Color("f4a6c6"), Vector3(0.5, 0.3, 0.5)],
	"mic":         ["Karaoke mic", 90, 2.0, "cyl", Color("c8ccd2"), Vector3(0.14, 0.4, 0.14)],
	"envelope":    ["Bonus envelope", 250, 0.5, "box", Color("f3d36b"), Vector3(0.4, 0.05, 0.28)],
	"stapler":     ["Golden stapler", 400, 3.0, "box", Color("e5b53a"), Vector3(0.36, 0.14, 0.12)],
	"cooler":      ["Water cooler", 180, 25.0, "cyl", Color("7fc4f0"), Vector3(0.45, 0.9, 0.45)],
	"trophy":      ["Bowling trophy", 200, 6.0, "cyl", Color("d9b45a"), Vector3(0.24, 0.5, 0.24)],
	"drive":       ["Hard drive", 150, 2.0, "box", Color("4b5563"), Vector3(0.3, 0.08, 0.2)],
	"rig":         ["Crypto rig", 600, 45.0, "box", Color("2dd4bf"), Vector3(0.7, 0.5, 0.5)],
	"router":      ["Router", 80, 3.0, "box", Color("e5e7eb"), Vector3(0.35, 0.08, 0.25)],
	"blade":       ["Server blade", 300, 20.0, "box", Color("9ca3af"), Vector3(0.7, 0.12, 0.5)],
	"tape":        ["Backup tape", 120, 1.0, "box", Color("1f2937"), Vector3(0.18, 0.18, 0.06)],
	"egg":         ["Golden egg", 500, 5.0, "sphere", Color("f5c542"), Vector3(0.32, 0.4, 0.32)],
	"parrot":      ["Parrot", 150, 1.0, "sphere", Color("ef4444"), Vector3(0.26, 0.3, 0.26)],
	"penguin":     ["Baby penguin", 250, 8.0, "sphere", Color("27272a"), Vector3(0.34, 0.44, 0.34)],
	"flamingo":    ["Flamingo", 220, 6.0, "cyl", Color("fb7aa8"), Vector3(0.2, 0.8, 0.2)],
	"panda":       ["Panda plush", 100, 4.0, "sphere", Color("f5f5f4"), Vector3(0.45, 0.45, 0.45)],
}
const ROOM_LOOT := {
	"office": ["cake", "mic", "envelope", "stapler", "cooler", "trophy"],
	"fire": ["drive", "rig", "router", "blade", "tape"],
	"zoo": ["egg", "parrot", "penguin", "flamingo", "panda"],
}


static func inside_cab(pos: Vector3) -> bool:
	return pos.z > INSIDE_MARGIN and pos.z < CAB_DEPTH + 0.5 \
		and absf(pos.x) < CAB_HALF_W + 0.3 and pos.y > -1.0 and pos.y < CAB_HEIGHT + 1.0


static func loot_name(kind: String) -> String:
	return LOOT[kind][0]


static func loot_value(kind: String) -> int:
	return LOOT[kind][1]


static func kg_text(kind: String) -> String:
	var kg := loot_kg(kind)
	return str(int(kg)) if is_equal_approx(kg, roundf(kg)) else str(kg)


static func loot_kg(kind: String) -> float:
	return LOOT[kind][2]


## How much carried weight slows you. 45 kg (the crypto rig) is about the worst case.
static func speed_factor(carried_kg: float) -> float:
	return clampf(1.0 - carried_kg / 80.0, 0.45, 1.0)


## The floors the cab will stop at this round, from START_FLOOR down. Lobby (0) is not a stop.
static func floor_plan(rng: RandomNumberGenerator) -> Array[int]:
	var stops: Array[int] = []
	var f := START_FLOOR
	while true:
		f -= rng.randi_range(STEP_MIN, STEP_MAX)
		if f <= 2:
			break
		stops.append(f)
	return stops


static func floor_label(f: int) -> String:
	return "L" if f <= 0 else "%02d" % f


static func spawn_spot(index: int) -> Vector3:
	# eight spots in two rows of four, at the back half of the cab
	var col := index % 4
	var row := (index / 4) % 3
	return Vector3(-1.35 + col * 0.9, 0.1, 3.3 - row * 0.9)
