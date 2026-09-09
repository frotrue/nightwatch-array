extends Control

# Text only. The gauge ring moved onto the software cursor, which is drawn at
# the observation radius and already sat at this same point — two rings a few
# pixels apart, both centred on the cursor, showing the same number.
# ring_radius is kept because the text block is placed clear of it.
var cursor := Vector2.ZERO
var ring_radius: float = 50.0
