# AudioManager.gd
extends Node

@onready var sfx_click: AudioStreamPlayer = $SFXClick
@onready var sfx_collect_ingredient: AudioStreamPlayer = $SFXCollectIngredient
@onready var sfx_correct_recipe: AudioStreamPlayer = $SFXRecipeGood
@onready var sfx_wrong_recipe: AudioStreamPlayer = $SFXRecipeBad
@onready var sfx_recipe_ready: AudioStreamPlayer = $SFXRecipeReady
@onready var sfx_whisking: AudioStreamPlayer = $SFXWhisking
@onready var sfx_time_up: AudioStreamPlayer = $SFXTimeUp
@onready var sfx_game_over: AudioStreamPlayer = $SFXGameOver
@onready var sfx_win: AudioStreamPlayer = $SFXWin
@onready var game_music: AudioStreamPlayer = $GameMusic
@onready var final_music: AudioStreamPlayer = $FinalMusic
@onready var sfx_customer_complaint := AudioStreamPlayer.new()
@onready var sfx_crowd_talking : AudioStreamPlayer = $SFXCrowdTalking
@onready var sfx_newton_humming : AudioStreamPlayer = $SFXNewtonHumming

var sfx_complaint_dict := {
	"female_sad": preload("res://assets/sfx/characters/sfx_female_sad.ogg"),
	"female_annoyed": preload("res://assets/sfx/characters/sfx_female_annoyed.ogg"),
	"female_stressed": preload("res://assets/sfx/characters/sfx_female_stressed.ogg"),
	"female_sleepy": preload("res://assets/sfx/characters/sfx_female_sleepy.ogg"),
	"female_happy": preload("res://assets/sfx/characters/sfx_female_happy.ogg"),
	"male_sad": preload("res://assets/sfx/characters/sfx_male_sad.ogg"),
	"male_annoyed": preload("res://assets/sfx/characters/sfx_male_annoyed.ogg"),
	"male_stressed": preload("res://assets/sfx/characters/sfx_male_stressed.ogg"),
	"male_sleepy": preload("res://assets/sfx/characters/sfx_male_sleepy.ogg"),
	"male_happy": preload("res://assets/sfx/characters/sfx_male_happy.ogg"),
}

var config_path := "user://audio_settings.cfg"

func _ready():
	add_child(sfx_customer_complaint)
	_cargar_audio_settings() # <-- Cargar valores guardados

### ============================
### Funciones existentes (sin cambios)
### ============================

func play_click_sfx():	
	if sfx_click:
		sfx_click.play()
	else:
		push_warning("SFXClick no está asignado o no existe en AudioManager")
		
func play_collect_ingredient_sfx():	
	if sfx_collect_ingredient:
		sfx_collect_ingredient.play()
	else:
		push_warning("SFXCollectIngredient no está asignado o no existe en AudioManager")
		
func play_correct_recipe_sfx():	
	if sfx_correct_recipe:
		sfx_correct_recipe.play()
	else:
		push_warning("SFXRightRecipe no está asignado o no existe en AudioManager")
		
func play_wrong_recipe_sfx():	
	if sfx_wrong_recipe:
		sfx_wrong_recipe.play()
	else:
		push_warning("SFXCollectIngredient no está asignado o no existe en AudioManager")

func play_recipe_ready_sfx():
	if sfx_recipe_ready:
		sfx_recipe_ready.play()
	else:
		push_warning("SFXRecipeReady no está asignado o no existe en AudioManager")
		
func play_whisking_sfx():	
	if sfx_whisking:
		sfx_whisking.play()
	else:
		push_warning("SFXWhisking no está asignado o no existe en AudioManager")

func play_customer_sfx(genre: String, mood_id: String, is_result: bool = false) -> void:
	var key = "%s_%s" % [genre, mood_id]
	if sfx_complaint_dict.has(key):
		sfx_customer_complaint.stream = sfx_complaint_dict[key]
		sfx_customer_complaint.stream.loop = not is_result
		sfx_customer_complaint.volume_db = -10.0
		sfx_customer_complaint.play()
	else:
		push_warning("Audio no encontrado: " + key)
		
func play_time_up_sfx():	
	if sfx_time_up:
		sfx_time_up.play()
	else:
		push_warning("SFXTimeUp no está asignado o no existe en AudioManager")

func play_game_over_sfx():	
	if sfx_game_over:
		sfx_game_over.play()
	else:
		push_warning("SFXGameOver no está asignado o no existe en AudioManager")

func play_win_sfx():	
	if sfx_win:
		sfx_win.play()
	else:
		push_warning("SFXWin no está asignado o no existe en AudioManager")

func play_game_music():
	if is_instance_valid(game_music):
		if game_music and not game_music.playing:
			game_music.play()
	else:
		await get_tree().process_frame
		if is_instance_valid(game_music) and not game_music.playing:
			game_music.play()
		else:
			push_warning("GameMusic no está asignado o no existe en AudioManager")

func play_end_music():
	if final_music:
		final_music.play()
	else:
		push_warning("FinalMusic no está asignado o no existe en AudioManager")

func play_crowd_talking_sfx():	
	if sfx_crowd_talking:
		sfx_crowd_talking.play()
	else:
		push_warning("SFXCrowdTalking no está asignado o no existe en AudioManager")

func play_newton_humming_sfx():	
	if sfx_newton_humming:
		sfx_newton_humming.play()
	else:
		push_warning("SFXNewtonHumming no está asignado o no existe en AudioManager")

func stop_whisking_sfx():	
	if sfx_whisking and sfx_whisking.playing:
		sfx_whisking.stop()
	else:
		push_warning("SFXWhisking no está asignado o no existe en AudioManager")

func stop_game_music():
	stop_crowd_talking_sfx()
	if game_music and game_music.playing:
		game_music.stop()
	else:
		push_warning("GameMusic no está asignado o no existe en AudioManager")

func stop_end_music():
	if is_instance_valid(final_music):
		if final_music.playing:
			final_music.stop()
	else:
		await get_tree().process_frame
		if is_instance_valid(final_music) and final_music.playing:
			final_music.stop()
		else:
			push_warning("FinalMusic no está asignado o no existe en AudioManager")

func stop_customer_sfx() -> void:
	if sfx_customer_complaint.playing:
		sfx_customer_complaint.stop()

func stop_crowd_talking_sfx():	
	if sfx_crowd_talking and sfx_crowd_talking.playing:
		sfx_crowd_talking.stop()
	else:
		push_warning("SFXCrowdTalking no está asignado o no existe en AudioManager")

func stop_newton_humming_sfx():	
	print("STOPPING HUMMING")
	if sfx_newton_humming and sfx_newton_humming.playing:
		sfx_newton_humming.stop()
	else:
		push_warning("SFXNewtonHumming no está asignado o no existe en AudioManager")

### ============================
### NUEVO: Audio con sliders y persistencia
### ============================

func set_music_volume(vol: float) -> void:
	var clamped = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(clamped))
	GlobalManager.music_volume = clamped
	_guardar_audio_settings("music_volume", clamped)

func set_sfx_volume(vol: float) -> void:
	var clamped = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(clamped))
	GlobalManager.sfx_volume = clamped
	_guardar_audio_settings("sfx_volume", clamped)

func _guardar_audio_settings(key: String, value: float) -> void:
	var cfg = ConfigFile.new()
	cfg.load(config_path)
	cfg.set_value("audio", key, value)
	cfg.save(config_path)

func _cargar_audio_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(config_path) == OK:
		# Música
		var music_vol = cfg.get_value("audio", "music_volume", 1.0)
		set_music_volume(music_vol)
		# SFX
		var sfx_vol = cfg.get_value("audio", "sfx_volume", 1.0)
		set_sfx_volume(sfx_vol)
	else:
		# Defaults si no existe archivo
		set_music_volume(GlobalManager.music_volume)
		set_sfx_volume(GlobalManager.sfx_volume)
