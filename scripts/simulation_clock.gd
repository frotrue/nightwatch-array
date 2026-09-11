extends RefCounted

const TICKS_PER_SECOND := 60
const STEP := 1.0 / TICKS_PER_SECOND
const HITSTOP_SCALE := 0.06
const HITSTOP_COOLDOWN := 24

var tick := 0
var epoch := 0
var hitstop_ticks := 0
var cooldown_ticks := 0

func begin_tick() -> float:
	tick += 1
	var scale := HITSTOP_SCALE if hitstop_ticks > 0 else 1.0
	if hitstop_ticks > 0:
		hitstop_ticks -= 1
		if hitstop_ticks == 0: cooldown_ticks = HITSTOP_COOLDOWN
	elif cooldown_ticks > 0:
		cooldown_ticks -= 1
	return scale

func request_hitstop(seconds: float) -> bool:
	if hitstop_ticks > 0 or cooldown_ticks > 0: return false
	hitstop_ticks = maxi(1, ceili(seconds * TICKS_PER_SECOND))
	return true

func reset_boundary() -> void:
	epoch += 1
	hitstop_ticks = 0
	cooldown_ticks = 0
