extends Node

const DifficultyConfig = preload("res://resources/difficulty_config.gd")

const DB_PATH := "user://flyfishing.db"
const SCHEMA_VERSION := 1

var db = null  # SQLite — untyped to avoid GDExtension type-introspection on startup
var _db_open: bool = false


func _ready() -> void:
	# Resolve user:// to an absolute path — some godot-sqlite versions require this
	var abs_path := ProjectSettings.globalize_path(DB_PATH)
	if OS.is_debug_build():
		print("DatabaseManager: db path = ", abs_path)

	var sqlite := SQLite.new()
	sqlite.path = abs_path
	sqlite.verbosity_level = 1  # NORMAL
	if not sqlite.open_db():
		push_error("DatabaseManager: open_db() failed for %s" % abs_path)
		sqlite = null
		return
	db = sqlite
	_db_open = true
	if OS.is_debug_build():
		print("DatabaseManager: opened OK")
	_run_migrations()
	_seed_defaults()



func _run_migrations() -> void:
	# Create schema version tracking
	db.query("""
		CREATE TABLE IF NOT EXISTS schema_version (
			version INTEGER PRIMARY KEY
		)
	""")

	db.query("SELECT version FROM schema_version ORDER BY version DESC LIMIT 1")
	var current_version: int = 0
	if db.query_result.size() > 0:
		current_version = db.query_result[0]["version"]

	if current_version < 1:
		_migrate_v1()
		db.query("INSERT OR REPLACE INTO schema_version (version) VALUES (1)")


func _migrate_v1() -> void:
	db.query("""
		CREATE TABLE IF NOT EXISTS settings (
			key   TEXT PRIMARY KEY,
			value TEXT NOT NULL
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS difficulty_presets (
			tier                              TEXT PRIMARY KEY,
			base_spook_radius                 REAL NOT NULL,
			large_fish_radius_multiplier      REAL NOT NULL,
			deep_cover_reduction              REAL NOT NULL,
			dawn_dusk_wariness_reduction      REAL NOT NULL,
			bad_cast_spook_chance             REAL NOT NULL,
			wading_vibration_radius           REAL NOT NULL,
			blind_spot_half_angle             REAL NOT NULL,
			vision_cone_half_angle            REAL NOT NULL,
			show_shadow_cone                  INTEGER NOT NULL,
			shadow_cone_always_visible        INTEGER NOT NULL,
			fish_telegraph_strength           REAL NOT NULL,
			wrong_species_intrusion_delta     REAL NOT NULL,
			show_sample_abundance_bars        INTEGER NOT NULL,
			hookset_window_duration           REAL NOT NULL,
			structure_density_multiplier      REAL NOT NULL,
			fish_per_section                  INTEGER NOT NULL
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS sessions (
			id               INTEGER PRIMARY KEY AUTOINCREMENT,
			seed             INTEGER NOT NULL,
			start_hour       REAL    NOT NULL,
			difficulty_tier  TEXT    NOT NULL,
			time_scale       REAL    NOT NULL,
			started_at       TEXT    NOT NULL,
			ended_at         TEXT
		)
	""")

	db.query("""
		CREATE TABLE IF NOT EXISTS catches (
			id                INTEGER PRIMARY KEY AUTOINCREMENT,
			session_id        INTEGER NOT NULL REFERENCES sessions(id),
			species           TEXT    NOT NULL,
			size_cm           REAL    NOT NULL,
			fly_name          TEXT    NOT NULL,
			fly_stage         TEXT    NOT NULL,
			hatch_state       TEXT    NOT NULL,
			time_of_day       TEXT    NOT NULL,
			section_index     INTEGER NOT NULL,
			position_x        REAL    NOT NULL,
			fish_variant_seed INTEGER NOT NULL,
			caught_at         TEXT    NOT NULL
		)
	""")


func _seed_defaults() -> void:
	_seed_difficulty_preset(DifficultyConfig.arcade())
	_seed_difficulty_preset(DifficultyConfig.standard())
	_seed_difficulty_preset(DifficultyConfig.sim())

	# Default settings — only inserted if key not already present
	var defaults := {
		"active_difficulty_tier": "STANDARD",
		"time_scale_seconds_per_hour": "60.0",
		"session_start_hour": "6.0",
	}
	for key in defaults:
		db.query(
			"INSERT OR IGNORE INTO settings (key, value) VALUES ('%s', '%s')" \
			% [key, defaults[key]]
		)


func _seed_difficulty_preset(cfg: DifficultyConfig) -> void:
	db.query("SELECT tier FROM difficulty_presets WHERE tier = '%s'" % cfg.tier_name())
	if db.query_result.size() > 0:
		return  # Already seeded — do not overwrite user customisations
	db.query("""
		INSERT INTO difficulty_presets VALUES (
			'%s', %f, %f, %f, %f, %f, %f, %f, %f, %d, %d, %f, %f, %d, %f, %f, %d
		)
	""" % [
		cfg.tier_name(),
		cfg.base_spook_radius,
		cfg.large_fish_radius_multiplier,
		cfg.deep_cover_reduction,
		cfg.dawn_dusk_wariness_reduction,
		cfg.bad_cast_spook_chance,
		cfg.wading_vibration_radius,
		cfg.blind_spot_half_angle,
		cfg.vision_cone_half_angle,
		int(cfg.show_shadow_cone),
		int(cfg.shadow_cone_always_visible),
		cfg.fish_telegraph_strength,
		cfg.wrong_species_intrusion_delta,
		int(cfg.show_sample_abundance_bars),
		cfg.hookset_window_duration,
		cfg.structure_density_multiplier,
		cfg.fish_per_section,
	])


# --- Public API ---

func load_difficulty(tier_name: String) -> DifficultyConfig:
	db.query(
		"SELECT * FROM difficulty_presets WHERE tier = '%s'" % tier_name
	)
	if db.query_result.size() == 0:
		push_warning("DatabaseManager: tier '%s' not found, returning standard" % tier_name)
		return DifficultyConfig.standard()

	var row: Dictionary = db.query_result[0]
	var cfg := DifficultyConfig.new()
	cfg.tier = DifficultyConfig.Tier[tier_name]
	cfg.base_spook_radius                = row["base_spook_radius"]
	cfg.large_fish_radius_multiplier     = row["large_fish_radius_multiplier"]
	cfg.deep_cover_reduction             = row["deep_cover_reduction"]
	cfg.dawn_dusk_wariness_reduction     = row["dawn_dusk_wariness_reduction"]
	cfg.bad_cast_spook_chance            = row["bad_cast_spook_chance"]
	cfg.wading_vibration_radius          = row["wading_vibration_radius"]
	cfg.blind_spot_half_angle            = row["blind_spot_half_angle"]
	cfg.vision_cone_half_angle           = row["vision_cone_half_angle"]
	cfg.show_shadow_cone                 = bool(row["show_shadow_cone"])
	cfg.shadow_cone_always_visible       = bool(row["shadow_cone_always_visible"])
	cfg.fish_telegraph_strength          = row["fish_telegraph_strength"]
	cfg.wrong_species_intrusion_delta    = row["wrong_species_intrusion_delta"]
	cfg.show_sample_abundance_bars       = bool(row["show_sample_abundance_bars"])
	cfg.hookset_window_duration          = row["hookset_window_duration"]
	cfg.structure_density_multiplier     = row["structure_density_multiplier"]
	cfg.fish_per_section                 = row["fish_per_section"]
	return cfg


func get_setting(key: String, default_value: String = "") -> String:
	db.query("SELECT value FROM settings WHERE key = '%s'" % key)
	if db.query_result.size() > 0:
		return db.query_result[0]["value"]
	return default_value


func set_setting(key: String, value: String) -> void:
	db.query(
		"INSERT OR REPLACE INTO settings (key, value) VALUES ('%s', '%s')" % [key, value]
	)


func save_session(seed: int, start_hour: float, tier_name: String, time_scale: float) -> int:
	db.query("""
		INSERT INTO sessions (seed, start_hour, difficulty_tier, time_scale, started_at)
		VALUES (%d, %f, '%s', %f, datetime('now'))
	""" % [seed, start_hour, tier_name, time_scale])
	db.query("SELECT last_insert_rowid() AS id")
	return db.query_result[0]["id"]


func end_session(session_id: int) -> void:
	db.query(
		"UPDATE sessions SET ended_at = datetime('now') WHERE id = %d" % session_id
	)


func save_catch(session_id: int, data: Dictionary) -> void:
	db.query("""
		INSERT INTO catches (
			session_id, species, size_cm, fly_name, fly_stage,
			hatch_state, time_of_day, section_index, position_x,
			fish_variant_seed, caught_at
		) VALUES (
			%d, '%s', %f, '%s', '%s', '%s', '%s', %d, %f, %d, datetime('now')
		)
	""" % [
		session_id,
		data["species"],
		data["size_cm"],
		data["fly_name"],
		data["fly_stage"],
		data["hatch_state"],
		data["time_of_day"],
		data["section_index"],
		data["position_x"],
		data["fish_variant_seed"],
	])


func load_catches(session_id: int) -> Array:
	db.query(
		"SELECT * FROM catches WHERE session_id = %d ORDER BY caught_at ASC" % session_id
	)
	return db.query_result


func close() -> void:
	if db and _db_open:
		db.close_db()
		_db_open = false
