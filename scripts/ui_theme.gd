extends RefCounted

# Shared typography and red-light palette for the HUD and the research chart.
#
# The design hand-off specifies every coordinate against a 1920x1080 frame while
# the project renders a 1152x648 viewport and scales it with `canvas_items`.
# SCALE converts the two so the spec numbers stay readable at their call sites
# and still land where the mock-up put them on a 1920-wide display.
const SCALE := 1152.0 / 1920.0

const MONO_REGULAR := "res://fonts/IBMPlexMono-Regular.ttf"
const MONO_MEDIUM := "res://fonts/IBMPlexMono-Medium.ttf"
const SANS_LIGHT := "res://fonts/IBMPlexSansKR-Light.ttf"
const SANS_REGULAR := "res://fonts/IBMPlexSansKR-Regular.ttf"
const SANS_MEDIUM := "res://fonts/IBMPlexSansKR-Medium.ttf"

# Red-light ink. Observatories keep their instrument lighting red to protect
# dark adaptation; the information layer borrows that convention.
const INK_MAX := Color("FFD4B0")
const INK_HIGH := Color("F3D0B9")
const INK_MID := Color("997866")
const INK_LOW := Color("61554E")
const ACCENT_PIP := Color("FFA47A")
const ACCENT_LINE := Color("FFAB82")
const ACCENT_TEXT := Color("FFB48E")
const ACCENT_DEEP := Color("553C31")
const GAIN := Color("E88761")
const BANNER_TITLE := Color("FFD1AC")
const BANNER_SUB := Color("A57C67")
const BANNER_RULE := Color("A15D3E")
const HINT := Color("A18E81")

# The palette's one attention ink. A red-light layer cannot say "bad" with a red
# colour, so failures and destructive actions take the hottest, most saturated
# warm in the set instead. GAIN is reserved for data arriving and must stay a
# separate value or the two meanings collapse.
const ALERT := Color("FF7043")

# Warm near-blacks. Anything backing red-light ink is warm-biased: a cold
# shadow under warm strokes reads as a different rendering pass.
const SHADOW := Color(0.03, 0.012, 0.008, 0.94)
const GROUND := Color("090604")
const SCRIM := Color(0.016, 0.008, 0.006, 0.9)

# Instrument white. Only the live tracking gauge leaves the red-light palette,
# which is what tells the player where their hand currently is.
const INSTRUMENT_ARC := Color("F8F5EE")
const INSTRUMENT_RING := Color("B0AEA7")
const INSTRUMENT_LABEL := Color("C6C4BD")
const INSTRUMENT_QUALITY := Color("FFBA94")

# Research chart star states.
const STAR_INSTALLED := Color("FFF1D8")
const STAR_INSTALLED_GLOW := Color("FFD5AE")
const STAR_READY_FILL := Color("FFB281")
const STAR_READY_BORDER := Color("FFC295")
const STAR_READY_RING := Color("FFAE82")
const STAR_SHORT_BORDER := Color("B37458")
const STAR_LOCKED := Color("AEA298")
const STAR_BACKGROUND := Color("EAEFF5")

const LINE_IDLE := Color("A5AFBA")
const LINE_INSTALLED := Color("F6D8BC")
const LINE_FRONTIER := Color("FFAE82")

const HORIZON := Color("644436")
const HORIZON_TICK := Color("AF775D")
const HORIZON_LABEL := Color("7B5B4A")

const TOOLTIP_BACKGROUND := Color(0.0157, 0.0235, 0.0392, 0.95)
const TOOLTIP_BORDER := Color("5E402F")
const TOOLTIP_NAME := Color("FBE7D8")
const TOOLTIP_BODY := Color("BBAEA5")
const TOOLTIP_LABEL := Color("7D6A5E")
const TOOLTIP_VALUE := Color("CCB1A0")
const TOOLTIP_ACTION := Color("FEA47C")

static var _cache: Dictionary = {}


# Spec pixels -> viewport pixels.
static func px(spec_pixels: float) -> float:
	return spec_pixels * SCALE


static func size_px(spec_pixels: float) -> int:
	return maxi(1, int(round(spec_pixels * SCALE)))


# Godot has no letter-spacing property, so the spec's em tracking is applied by
# padding each glyph's advance. `em` is the spec value, e.g. 0.28 for 0.28em.
static func tracking(font_size: int, em: float) -> int:
	return int(round(float(font_size) * em))


static func _font(path: String) -> FontFile:
	if _cache.has(path):
		return _cache[path]
	var font: FontFile = load(path)
	_cache[path] = font
	return font


static func mono(medium: bool = false) -> FontFile:
	return _font(MONO_MEDIUM if medium else MONO_REGULAR)


static func sans(weight: String = "regular") -> FontFile:
	match weight:
		"light":
			return _font(SANS_LIGHT)
		"medium":
			return _font(SANS_MEDIUM)
		_:
			return _font(SANS_REGULAR)


# Tabular figures. Counters, clocks and costs must not shift width as they tick.
static func mono_tabular(medium: bool = false) -> FontVariation:
	var key := "tnum_medium" if medium else "tnum_regular"
	if _cache.has(key):
		return _cache[key]
	var variation := FontVariation.new()
	variation.base_font = mono(medium)
	# FontVariation takes OpenType feature tags as their 32-bit integer form.
	variation.opentype_features = {_feature_tag("tnum"): 1}
	_cache[key] = variation
	return variation


static func _feature_tag(tag: String) -> int:
	var value := 0
	for index in range(4):
		value = (value << 8) | tag.unicode_at(index)
	return value
