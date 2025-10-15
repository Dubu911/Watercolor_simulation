extends Node

# Controls paint opacity and glazing behavior
# Lower = more transparent, less darkening when layering (0.2-0.4 for lighter glazing)
# Higher = more opaque, faster darkening when layering (0.5-1.0 for traditional watercolor)
const K_ABSORPTION = 0.01
const EPS_A = 1e-6 # avoid log(0)

# --- HELPER FUNCTIONS ---

func _hue_to_optical_density(rgb: Color) -> Vector3:
	# Interpret hue as per-channel transmittance; convert to optical density.
	var r_t = clamp(rgb.r, EPS_A, 1.0)
	var g_t = clamp(rgb.g, EPS_A, 1.0)
	var b_t = clamp(rgb.b, EPS_A, 1.0)
	return Vector3(-log(r_t), -log(g_t), -log(b_t))

func _optical_density_to_rgb(od: Vector3) -> Color:
	# Convert OD back to per-channel transmittance (RGB).
	return Color(exp(-od.x), exp(-od.y), exp(-od.z), 1.0)

func _mix_pigments_optical(pigment_a: Color, pigment_b: Color, tint_strength_a = 1.0, tint_strength_b = 1.0) -> Color:
	var mass_a = _alpha_to_mass(pigment_a.a)
	var mass_b = _alpha_to_mass(pigment_b.a)

	if mass_a <= 0.0: return pigment_b
	if mass_b <= 0.0: return pigment_a

	var total_mass = mass_a + mass_b

	# Optical density “fingerprints” from hues
	var od_a = _hue_to_optical_density(pigment_a) * tint_strength_a
	var od_b = _hue_to_optical_density(pigment_b) * tint_strength_b

	# Mass-weighted OD (Beer–Lambert)
	var od_total = (od_a * mass_a + od_b * mass_b) / total_mass

	var rgb_total = _optical_density_to_rgb(od_total)
	return Color(rgb_total.r, rgb_total.g, rgb_total.b, _mass_to_alpha(total_mass))


func _alpha_to_mass(alpha: float) -> float:
	# Decode the visual alpha back into an abstract pigment mass.
	var a = clamp(alpha, 0.0, 1.0 - EPS_A)
	return -log(1.0 - a) / K_ABSORPTION

func _mass_to_alpha(mass: float) -> float:
	# Encode the abstract pigment mass into a visual alpha value for rendering.
	if mass <= 0.0: return 0.0
	return 1.0 - exp(-K_ABSORPTION * mass)
