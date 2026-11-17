class_name AwGrenadeSound
extends RefCounted

## The detonation recordings of the thrown grenades, which dot-audio's stock has no set for.
## Every grenade of the pack has a sound of its own here, recordings from the credited sources in CREDITS.md (a frag and a sticky blast, a flash bang, a steam release, a flame whoosh), cut and levelled by hand with ffmpeg to the loudness the stock explosion has.
## A host plays [method stream] where a grenade goes off.

const DIR := "res://addons/fc_weapons/assets/grenade_sounds/"

## Grenade id -> file stem of its detonation recordings (`<stem>_<n>.ogg`).
const STEMS := {
	&"frag": "frag_blast",
	&"sticky": "sticky_blast",
	&"flash": "flash_bang",
	&"smoke": "smoke_hiss",
	&"incendiary": "incendiary_ignite",
}

static var _streams: Dictionary = {}


## Number of takes grenade [param id] has; 0 means it uses the host's explosion.
static func count(id: StringName) -> int:
	if not STEMS.has(id):
		return 0
	var n := 0
	while ResourceLoader.exists("%s%s_%d.ogg" % [DIR, STEMS[id], n]):
		n += 1
	return n


## One take of [param id]'s detonation chosen by [param roll], or null when the id is not a grenade of the pack.
static func stream(id: StringName, roll: int = 0) -> AudioStream:
	var n := count(id)
	if n == 0:
		return null
	var path := "%s%s_%d.ogg" % [DIR, STEMS[id], absi(roll) % n]
	if not _streams.has(path):
		_streams[path] = load(path) as AudioStream
	return _streams[path]
