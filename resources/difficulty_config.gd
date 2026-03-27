class_name DifficultyConfig
extends Resource

enum Tier { ARCADE, STANDARD, SIM }

@export var tier: Tier = Tier.STANDARD

# --- Spook system ---
@export var base_spook_radius: float = 150.0
@export var large_fish_radius_multiplier: float = 1.5
@export var deep_cover_reduction: float = 0.35         # fraction subtracted at max cover
@export var dawn_dusk_wariness_reduction: float = 0.20 # fraction reduction during feeding windows
@export var bad_cast_spook_chance: float = 0.6         # 0.0–1.0
@export var wading_vibration_radius: float = 80.0

# --- Vision cone ---
@export var blind_spot_half_angle: float = 30.0   # degrees behind fish, each side
@export var vision_cone_half_angle: float = 120.0 # degrees forward, each side

# --- Player feedback ---
@export var show_shadow_cone: bool = true
@export var shadow_cone_always_visible: bool = false   # true = always, false = only when close
@export var fish_telegraph_strength: float = 0.5       # 0.0 = none, 1.0 = strong color shift

# --- Fly matching ---
@export var wrong_species_intrusion_delta: float = 0.0 # +1.0 on Sim

# --- Net sampling ---
@export var show_sample_abundance_bars: bool = true    # false on Sim

# --- Hookset ---
@export var hookset_window_duration: float = 0.8       # seconds

# --- River generation ---
@export var structure_density_multiplier: float = 1.0
@export var fish_per_section: int = 12


static func arcade() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.tier = Tier.ARCADE
	c.base_spook_radius = 100.0
	c.large_fish_radius_multiplier = 1.2
	c.deep_cover_reduction = 0.50
	c.dawn_dusk_wariness_reduction = 0.30
	c.bad_cast_spook_chance = 0.30
	c.wading_vibration_radius = 50.0
	c.blind_spot_half_angle = 45.0
	c.vision_cone_half_angle = 110.0
	c.show_shadow_cone = true
	c.shadow_cone_always_visible = true
	c.fish_telegraph_strength = 1.0
	c.wrong_species_intrusion_delta = 0.0
	c.show_sample_abundance_bars = true
	c.hookset_window_duration = 1.2
	c.structure_density_multiplier = 2.0
	c.fish_per_section = 26
	return c


static func standard() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.tier = Tier.STANDARD
	c.base_spook_radius = 150.0
	c.large_fish_radius_multiplier = 1.5
	c.deep_cover_reduction = 0.35
	c.dawn_dusk_wariness_reduction = 0.20
	c.bad_cast_spook_chance = 0.60
	c.wading_vibration_radius = 80.0
	c.blind_spot_half_angle = 30.0
	c.vision_cone_half_angle = 120.0
	c.show_shadow_cone = true
	c.shadow_cone_always_visible = false
	c.fish_telegraph_strength = 0.5
	c.wrong_species_intrusion_delta = 0.0
	c.show_sample_abundance_bars = true
	c.hookset_window_duration = 0.8
	c.structure_density_multiplier = 1.5
	c.fish_per_section = 18
	return c


static func sim() -> DifficultyConfig:
	var c := DifficultyConfig.new()
	c.tier = Tier.SIM
	c.base_spook_radius = 220.0
	c.large_fish_radius_multiplier = 2.0
	c.deep_cover_reduction = 0.20
	c.dawn_dusk_wariness_reduction = 0.10
	c.bad_cast_spook_chance = 0.90
	c.wading_vibration_radius = 130.0
	c.blind_spot_half_angle = 20.0
	c.vision_cone_half_angle = 130.0
	c.show_shadow_cone = false
	c.shadow_cone_always_visible = false
	c.fish_telegraph_strength = 0.0
	c.wrong_species_intrusion_delta = 1.0
	c.show_sample_abundance_bars = false
	c.hookset_window_duration = 0.5
	c.structure_density_multiplier = 1.0
	c.fish_per_section = 12
	return c


func tier_name() -> String:
	return Tier.keys()[tier]
