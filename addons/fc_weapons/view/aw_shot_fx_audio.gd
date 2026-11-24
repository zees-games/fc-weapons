extends "aw_shot_fx_materials.gd"

## Sound half of AwShotFx, split out for file size.
## A sound was handed to a voice. For a suite that asserts which stream played, and a HUD.
signal heard(stream: AudioStream)

## Most reports playing at once, per carrier. A minigun cuts its own oldest report off
## rather than stacking forty.
const MAX_VOICES := 6

## A report from further than this plays the stock's distant recording, when there is one.
const FAR_METRES := 60.0

## Shortest gap between two dry clicks and two case landings, in ms: a held trigger on an
## empty gun and a minigun would otherwise use every voice on them.
const DRY_GAP_MSEC := 250

const CASING_GAP_MSEC := 90

## Shortest gap between two impact sounds on the world: a shotgun's pellets land in one frame, and each
## taking a voice cut its own report off.
const IMPACT_GAP_MSEC := 30

## Where an Ogg voice start decodes on the game thread (web without threads, see [method ogg_starts_slow]) each costs about a millisecond, and a 32-player
## fight starts dozens a second. There, other players' impacts are heard only within [constant SLOW_IMPACT_DISTANCE] metres and at most one per
## [constant SLOW_IMPACT_GAP_MSEC] across all shooters. Native and the local gun are unchanged.
const SLOW_IMPACT_DISTANCE := 40.0
const SLOW_IMPACT_GAP_MSEC := 100
static var _slow_impact_msec: int = -100000
static var _ogg_slow := -1

## How far each kind of sound carries and how much its pitch wanders: [unit size, max distance, pitch spread].
## A report crosses the map, an impact a few rooms, a magazine going in only the next room; one shared
## falloff made reloads across the map as loud as shots.
const FALLOFF := {
	&"report": [12.0, 260.0, 0.05],
	&"impact": [5.0, 120.0, 0.12],
	&"handling": [2.0, 40.0, 0.04],
}

## gs-audio's PCM copies (duck-typed by path like [AwShotLayers]): starting an Ogg voice builds its decoder
## every time, about half a millisecond on the game thread per casing, tail or reload; a decoded copy starts
## in microseconds. Shared with gs-audio's own voices, so one copy per sound per process.
const PCM_PATH := "res://addons/gs_audio/sink/gs_audio_pcm.gd"
static var _pcm: Script = null
static var _pcm_probed := false

var _spin_voice: AudioStreamPlayer3D = null

## Replaces the stock report and tail: `func(id: StringName, kind: StringName, at: Vector3, indoors: bool) -> bool`, e.g. wrapping a GSShotPlayer's `fire`. Return true when it played the shot; false falls back to the stock sound. Unset keeps the stock sound.
var shot_sound: Callable = Callable()

var _layers: AwShotLayers = null
## True when [member _layers] is [AwFxPool]'s, which probes the room itself.
var _layers_shared := false

## What other people's shots may cost (`cl_shotfx_*`); shared by every AwShotFx. Bind it with [method GSWeaponCvarRules.bind_cvars].
## Made on first use: an instance built while this script loads blocks reloading AwShotFxRules (the parse pass).
static var rules: AwShotFxRules:
	get:
		if _rules == null:
			_rules = AwShotFxRules.new()
		return _rules
static var _rules: AwShotFxRules = null

## True for the local player's own gun, which none of [member rules] limits. Set before adding to the tree.
@export var first_person: bool = false

## Play reports.
@export var sounds: bool = true

## The game's roof probe ([code]GSAmbienceRoof[/code], which the game steps); roofed means indoors, so a shot is followed by a room tail.
var roof: RefCounted = null

var _voices: Array[AudioStreamPlayer3D] = []

var _last_dry_msec: int = -100000

var _last_casing_msec: int = -100000

## The audio bus reports are played on.
@export var bus: StringName = &"Master"

## Play guns as gs-audio's layered, room-aware shot when it is linked and the class has a stock shot; off, or missing, plays the single sound.
@export var layered_shots: bool = true

## Decibels added to every report. A game's mixer is the better place for this; this is
## for the game that has none.
@export_range(-40.0, 12.0, 0.5) var volume_db: float = 0.0


## A reload's sound at [param at]: [param stage] is [constant AwWeaponSound.RELOAD_OUT] or
## [constant AwWeaponSound.RELOAD_IN]. The rig decides when; this only plays it. [param weapon_id] picks the class's own reload.
func play_reload(stage: StringName, at: Vector3, weapon_id: StringName = &"") -> void:
	_play(AwWeaponSound.reload_stream(weapon_id, stage), at, -4.0, &"handling")


## One handling sound of a reload ([param cue] is a name from AwReloadCues, stock cue_NAME_N) at [param at]; [param db] is its
## level in the plan. [param weapon_id]'s own cue (AwGunCues) is played where it has one, else the stock one; a cue with
## neither is silent.
func play_cue(cue: StringName, at: Vector3, db: float = 0.0, weapon_id: StringName = &"") -> void:
	if not sounds or not is_inside_tree():
		return
	var roll := randi()
	var own := AwGunCues.stream(weapon_id, cue, roll) if weapon_id != &"" else null
	_play(own if own != null else GSWeaponSound.pick(StringName("cue_%s" % cue), roll), at, db - 4.0, &"handling")


## The selector switch of weapon [param weapon_id] at [param at]; the click differs per gun class.
func play_mode_click(at: Vector3, weapon_id: StringName) -> void:
	if not sounds or not is_inside_tree():
		return
	_play(AwWeaponSound.stream(AwWeaponSound.mode_click_for(weapon_id)), at, -2.0, &"handling")


## The hammer falling on nothing. Throttled, because a held trigger asks every tick.
func play_dry(at: Vector3, weapon_id: StringName = &"") -> void:
	var now := Time.get_ticks_msec()
	if not sounds or not is_inside_tree() or now - _last_dry_msec < DRY_GAP_MSEC:
		return
	_last_dry_msec = now
	_play(AwWeaponSound.dry_stream(weapon_id), at, -4.0, &"handling")


## A weapon coming up in the hands; a grenade ([param thrown]) is heard as its pin coming out.
func play_equip(at: Vector3, thrown: bool = false, weapon_id: StringName = &"") -> void:
	if not is_inside_tree():
		return
	var pin := GSWeaponSound.pick(&"pin_pull", randi()) if thrown else null
	_play(pin if pin != null else AwWeaponSound.equip_stream(weapon_id), at, -6.0, &"handling")


## One shell going into a tube magazine: a per-round reload plays this once per round. [param weapon_id]'s own shell
## recording (shotgun shell_load) when it has one.
func play_reload_shell(at: Vector3, weapon_id: StringName = &"") -> void:
	if not is_inside_tree():
		return
	var own := AwGunCues.stream(weapon_id, &"shell_load", randi()) if weapon_id != &"" else null
	_play(own if own != null else AwWeaponSound.stream(AwWeaponSound.RELOAD_SHELL), at, -4.0, &"handling")


## Starts the minigun's [param part] (spin_up, spin_loop or spin_down) on the one spin voice, replacing what it was playing.
func play_spin(part: StringName, at: Vector3) -> void:
	var stream := AwGunCues.spin_stream(part)
	if not sounds or stream == null or not is_inside_tree():
		return
	if _spin_voice == null or not is_instance_valid(_spin_voice):
		_spin_voice = AudioStreamPlayer3D.new()
		_spin_voice.name = "SpinVoice"
		_spin_voice.top_level = true
		_spin_voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		_spin_voice.unit_size = 12.0
		_spin_voice.max_distance = 120.0
		add_child(_spin_voice)
	heard.emit(stream)
	_spin_voice.bus = bus
	_spin_voice.stream = stream
	_spin_voice.volume_db = volume_db - 6.0
	_spin_voice.global_position = at
	_spin_voice.play()


## Cuts the spin voice now (a drop, a switch, a death): a loop must never outlive the gun.
func stop_spin() -> void:
	if _spin_voice != null and is_instance_valid(_spin_voice):
		_spin_voice.stop()


## True while the spin voice is sounding.
func spin_playing() -> bool:
	return _spin_voice != null and is_instance_valid(_spin_voice) and _spin_voice.playing


## The case landing, a little after it left the port.
func _schedule_casing(at: Vector3, delay: float) -> void:
	var now := Time.get_ticks_msec()
	if not sounds or not is_inside_tree() or now - _last_casing_msec < CASING_GAP_MSEC:
		return
	_last_casing_msec = now
	var timer := get_tree().create_timer(0.38 + delay)
	timer.timeout.connect(_play_casing.bind(at))


func _play_casing(at: Vector3) -> void:
	if is_inside_tree():
		_play(AwWeaponSound.stream(AwWeaponSound.CASING), at - Vector3(0.0, 1.2, 0.0), -2.0, &"handling")


func _report(id: StringName, kind: StringName, at: Vector3) -> void:
	if not sounds or kind == GSWeaponOutcome.KIND_NONE or _too_far(at, rules.voice_distance):
		return
	if shot_sound.is_valid() and bool(shot_sound.call(id, kind, at, roof != null and bool(roof.get(&"roofed")))):
		return
	if _layered(id, kind, at):
		return

	var heard: AudioStream = null
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera != null and camera.global_position.distance_to(at) > FAR_METRES:
		heard = AwWeaponSound.far_for(id, kind)

	_play(heard if heard != null else AwWeaponSound.stream_for(id, kind), at, 0.0)
	_play_tail(id, kind, at)


## Builds the layered shot's audio manager, room and player now (what the first layered shot would, about 60 ms on a
## GPU box), so a game can do it under its loading cover. True when layered shots are on and ready; safe to call again.
## Somebody else's gun takes [AwFxPool]'s shared one when a pool is in the tree.
func prewarm_layers() -> bool:
	if not layered_shots or not is_inside_tree():
		return false
	if _layers != null and is_instance_valid(_layers):
		return _layers.is_ready()
	_layers = null
	if not AwShotLayers.available():
		layered_shots = false
		return false
	_layers_shared = false
	if not first_person:
		var shared: AwShotLayers = _fx_pool().shared_layers(self, bus)
		if shared != null:
			_layers = shared
			_layers_shared = true
			return true
	_layers = AwShotLayers.new()
	add_child(_layers)
	set_process(true)
	if not _layers.setup(bus):
		layered_shots = false
		return false
	return true


## Plays the layered shot for a gun class that has one; false leaves the single sound to the caller.
func _layered(id: StringName, kind: StringName, at: Vector3) -> bool:
	if not layered_shots or not is_inside_tree():
		return false
	var own := kind == GSWeaponOutcome.KIND_SHOT and AwShotLayers.has_gun_sound(id)
	if AwShotLayers.shot_class(AwWeaponSound.class_for(id, kind)) == &"" and not own:
		return false
	if not prewarm_layers():
		return false
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	var listener := camera.global_position if camera != null else at
	if not _layers.fire(AwWeaponSound.class_for(id, kind), at, listener, id if own else &""):
		return false
	heard.emit(AwWeaponSound.stream_for(id, kind))
	return true


## Indoors the class's distant recording follows the report, [constant GSWeaponSound.TAIL_DELAY] late.
func _play_tail(id: StringName, kind: StringName, at: Vector3) -> void:
	var indoors := roof != null and bool(roof.get(&"roofed"))
	var tail := GSWeaponSound.pick_tail(AwWeaponSound.class_for(id, kind), indoors, randi())
	if tail == null or not is_inside_tree():
		return
	await get_tree().create_timer(GSWeaponSound.TAIL_DELAY).timeout
	if is_instance_valid(self) and is_inside_tree():
		_play(tail, at, GSWeaponSound.TAIL_GAIN_DB)


## True when this is somebody else's gun and [param at] is farther than [param limit] metres from the camera (0 never).
func _too_far(at: Vector3, limit: float) -> bool:
	if first_person or limit <= 0.0 or not is_inside_tree():
		return false
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	return camera != null and camera.global_position.distance_to(at) > limit


## Other shooters' shots drawn in the frame [member _crowd_at], across every AwShotFx ([member AwShotFxRules.crowd_frame]).
static var _crowd_at := -1
static var _crowd_drawn := 0


## True when this is somebody else's gun and the crowd has drawn [member AwShotFxRules.crowd_frame] shots this frame;
## otherwise counts this one. The report is played before it is asked: only the sight of the shot is dropped.
func _crowd_full() -> bool:
	if first_person or rules.crowd_frame <= 0:
		return false
	var frame := Engine.get_process_frames()
	if frame != _crowd_at:
		_crowd_at = frame
		_crowd_drawn = 0
	if _crowd_drawn >= rules.crowd_frame:
		return true
	_crowd_drawn += 1
	return false


## Voices this shooter may hold at once.
func _voice_cap() -> int:
	return MAX_VOICES if first_person else mini(MAX_VOICES, rules.remote_voices)


## Builds one report voice, idle and parked. Also what [method prewarm_voices] calls.
func _make_voice() -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.name = "Voice%d" % _voices.size()
	voice.top_level = true
	# A report's reach until _play sets each sound's own (FALLOFF): the default attenuation
	# makes a shot at forty metres inaudible.
	voice.unit_size = 12.0
	voice.max_distance = 260.0
	voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(voice)
	_voices.append(voice)
	return voice


## Builds [param count] voices now (default: this shooter's cap), so the first shots and impacts create no AudioStreamPlayer3D.
func prewarm_voices(count: int = -1) -> void:
	var want := _voice_cap() if count < 0 else mini(count, _voice_cap())
	while _voices.size() < want:
		var _made := _make_voice()


func _play(stream: AudioStream, at: Vector3, extra_db: float, falloff: StringName = &"report") -> void:
	if not sounds or stream == null or _too_far(at, rules.voice_distance):
		return
	# Past its max distance the voice is silent anyway; only worth the check where a start costs.
	if ogg_starts_slow() and _too_far(at, float((FALLOFF.get(falloff, FALLOFF[&"report"]) as Array)[1])):
		return

	var voice: AudioStreamPlayer3D = null

	# A finished voice is reused before a new one is made; with every voice busy the
	# oldest is cut off, which is what a gun firing faster than its report can ring out
	# actually sounds like.
	for candidate in _voices:
		if is_instance_valid(candidate) and not candidate.playing:
			voice = candidate
			break

	if voice == null and _voices.size() < _voice_cap():
		voice = _make_voice()

	if voice == null:
		voice = _voices.pop_front()
		_voices.append(voice)

	heard.emit(stream)
	voice.bus = bus
	var played := _pcm_of(stream)
	voice.stream = played
	voice.volume_db = volume_db + extra_db + (float(_pcm.get(&"HEADROOM_DB")) if played != stream else 0.0)
	var shape: Array = FALLOFF.get(falloff, FALLOFF[&"report"])
	voice.unit_size = float(shape[0])
	voice.max_distance = float(shape[1])
	# A rifle that sounds identical every shot is a metronome. Presentation, so randf.
	voice.pitch_scale = 1.0 + randf_range(-float(shape[2]), float(shape[2]))
	voice.global_position = at
	voice.play()


## True when playing an Ogg stream decodes on the game thread: gs-audio is missing or cannot decode to
## PCM off-thread (single-threaded web). Probed once.
static func ogg_starts_slow() -> bool:
	if _ogg_slow < 0:
		var _probe := _pcm_of(null)
		_ogg_slow = 1 if _pcm == null or not bool(_pcm.call(&"threaded")) else 0
	return _ogg_slow == 1


## True when a remote impact sound at [param at] should be skipped because Ogg starts are slow here.
func _skip_slow_impact(at: Vector3) -> bool:
	if first_person or not ogg_starts_slow():
		return false
	if _too_far(at, SLOW_IMPACT_DISTANCE):
		return true
	var now := Time.get_ticks_msec()
	if now - _slow_impact_msec < SLOW_IMPACT_GAP_MSEC:
		return true
	_slow_impact_msec = now
	return false


## [param stream]'s decoded copy once gs-audio has one, else [param stream] (the first play starts the decode).
static func _pcm_of(stream: AudioStream) -> AudioStream:
	if not _pcm_probed:
		_pcm_probed = true
		if ResourceLoader.exists(PCM_PATH):
			_pcm = load(PCM_PATH) as Script
	if _pcm == null or stream == null or stream.resource_path.is_empty() or bool(stream.get(&"loop")):
		return stream
	return _pcm.call(&"copy_for", stream.resource_path, stream) as AudioStream
