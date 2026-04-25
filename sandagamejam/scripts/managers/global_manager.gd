# GlobalManager.gd
extends Node

signal lives_changed(new_lives, maxi)
signal time_changed(new_time)
signal time_up
signal game_over
signal win
signal idioma_cambiado(nuevo_idioma) # Señal para actualizar UI en tiempo real

var lives
var max_lives
var time_left
var is_game_running : bool = false
var is_minigame_overlay_visible : bool = false
var ingredientes_array_size

var game_language : String = "es" 
var customers_to_serve: Array = []
var satisfied_customers: Array = []
var current_customer: Dictionary = {}
var current_level_recipes: Array = []
var all_ingredients: Array = []
var fake_ingredients: Array = []
var gravitational_ingredients: Array = []
var collected_ingredients: Array = []
var selected_recipe_idx : int = 0
var selected_recipe_data: Dictionary = {}
var recipe_started : bool = false

# Nuevas variables de audio globales
var music_volume : float = 1.0 # 0.0 a 1.0
var sfx_volume : float = 1.0   # 0.0 a 1.0
var audio_config_path := "user://audio_settings.cfg"

var btn_listen_customer_label = ""
var btn_help_customer_label = ""
var btn_reject_recipe_label = ""
var btn_choose_recipe_label = ""
var btn_cook_recipe_label = ""
var btn_continuar_label = ""
var loading_label = ""

# Estados del cliente
enum State { ENTERING, SEATED, FAIL, SUCCESS }
enum GameState { WIN, TIMEUP, GAMEOVER }

enum ResponseType {
	RECIPE_WRONG,
	RECIPE_NOT_PREPARED,
	INGREDIENTS_WRONG,
	RECIPE_CORRECT,
	GRAVITATIONAL
}

var response_keys := {
	ResponseType.RECIPE_WRONG: "recipe_wrong_",
	ResponseType.RECIPE_NOT_PREPARED: "recipe_timeout_",
	ResponseType.INGREDIENTS_WRONG: "ingredients_wrong_",
	ResponseType.RECIPE_CORRECT: "recipe_correct_",
	ResponseType.GRAVITATIONAL: "gravitational_"
}

var interaction_texts := {}     
var menu_labels := {}        
var characters_moods := {}  

func _ready():
	lives = GameController.LIVES
	max_lives = GameController.MAX_LIVES
	time_left = GameController.TIME_LEFT
	ingredientes_array_size = GameController.ING_ARR_SIZE
	cargar_audio_settings()

func start_game():
	is_game_running = true
	load_texts()
	load_button_labels()
	load_other_labels()
	UILayerManager.init_ui_layer()
	UILayerManager.show_hud()

#### Gestionar tiempo y vidas ####
func _process(delta: float) -> void:
	if is_game_running:
		time_left -= delta
		emit_signal("time_changed", time_left)
		if time_left <= 0:
			time_left = 0
			is_game_running = false
			print("****** TIME UP 2")
			emit_signal("time_up")

func apply_penalty(seconds: float):
	time_left = max(time_left - seconds, 0)
	emit_signal("time_changed", time_left)
	
	if time_left == 0 and is_game_running:
		print("****** TIME UP 1")
		is_game_running = false
		emit_signal("time_up")

func lose_life():
	if lives > 0:
		lives -= 1
		emit_signal("lives_changed", lives, max_lives)
		if lives == 0:
			print("****** GAME OVER ")
			is_game_running = false
			emit_signal("game_over")

func gain_life():
	if lives <= max_lives:
		lives += 1
		emit_signal("lives_changed", lives, max_lives)

func check_win_condition():
	if time_left > 0 and lives > 0 and customers_to_serve.is_empty():
		is_game_running = false
		emit_signal("win")
		
#### Gestionar cola de clientes ####
func initialize_customers(combos: Array):
	customers_to_serve = combos.duplicate()

func get_next_customer() -> Dictionary:
	if customers_to_serve.is_empty():
		return {}
	current_customer = customers_to_serve.pop_front()
	return current_customer

func return_customer():
	customers_to_serve.append(current_customer)

func mark_customer_as_satisfied():
	satisfied_customers.append(current_customer)

### Gestionar recetas ###
func initialize_recipes(level: String):
	var level_recipes_json_path = "res://i18n/levels_recipes.json"
	var all_recipes_json_path = "res://i18n/all_recipes.json"
	var ingredients_json_path = "res://i18n/ingredients.json"
	var fake_ingr_json_path = "res://i18n/fake_ingredients.json"
	var gravitational_ingr_json_path = "res://i18n/gravitational_ingredients.json"
	var level_recipe_ids = FileHelper.read_data_from_file(level_recipes_json_path)[level]
	var all_recipes = FileHelper.read_data_from_file(all_recipes_json_path)
	all_ingredients = FileHelper.read_data_from_file(ingredients_json_path)
	fake_ingredients = FileHelper.read_data_from_file(fake_ingr_json_path)
	gravitational_ingredients = FileHelper.read_data_from_file(gravitational_ingr_json_path)

	for recipe in all_recipes:
		if recipe["id"] in level_recipe_ids:
			current_level_recipes.append(recipe)

### Game Controls ###
func pause_game():
	is_game_running = false

func resume_game():
	is_game_running = true

func reset():
	lives = GameController.LIVES
	max_lives = GameController.MAX_LIVES
	time_left = GameController.TIME_LEFT
	is_game_running = true
	customers_to_serve.clear()
	satisfied_customers.clear()
	current_customer.clear()
	current_level_recipes.clear()
	collected_ingredients.clear()
	selected_recipe_idx = -1
	selected_recipe_data.clear()
	recipe_started = false

	is_minigame_overlay_visible = false
	ingredientes_array_size = GameController.ING_ARR_SIZE
	
### Botones de interaccion con el cliente ###
func load_texts():
	if interaction_texts.is_empty():
		interaction_texts = _cargar_json_file("res://i18n/interaction_texts.json")
	if menu_labels.is_empty():
		menu_labels = _cargar_json_file("res://i18n/menu_labels.json")
	if characters_moods.is_empty():
		characters_moods = _cargar_json_file("res://i18n/characters_moods.json")

func load_button_labels():	
	if game_language in interaction_texts:
		btn_listen_customer_label = interaction_texts[game_language]["customer_seated"]
		btn_help_customer_label = interaction_texts[game_language]["start_helping"]
		btn_reject_recipe_label = interaction_texts[game_language]["reject_recipe"]
		btn_choose_recipe_label = interaction_texts[game_language]["choose_recipe"]
		btn_cook_recipe_label = interaction_texts[game_language]["newton_cook"]
		btn_continuar_label = interaction_texts[game_language]["continue"]
	else:
		btn_listen_customer_label = "Customer"
		btn_help_customer_label = "Help"

func load_other_labels():
	if game_language in interaction_texts:
		loading_label = interaction_texts[game_language]["loading"]
		
func get_response_texts(response: ResponseType) -> Array[String]:
	var lang_texts: Dictionary = interaction_texts.get(game_language, {})
	var prefix: String = response_keys.get(response, "")
	
	return [
		String(lang_texts.get(prefix + "feedback", "feedback")),
		String(lang_texts.get(prefix + "outcome", "outcome"))
	]
	
func _cargar_json_file(path: String) -> Dictionary:
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		push_error("No se pudo abrir " + path)
		return {}
	var text = f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	if typeof(data) == TYPE_DICTIONARY:
		return data
	else:
		push_error("Error parseando JSON: " + path)
		return {}

### Cambio de idioma en tiempo real ###
func set_language(nuevo_idioma: String) -> void:
	cambiar_idioma(nuevo_idioma)

func cambiar_idioma(nuevo_idioma: String) -> void:
	game_language = nuevo_idioma
	load_texts()            # Recarga todos los textos
	load_button_labels()    # Recarga labels de botones
	load_other_labels()
	emit_signal("idioma_cambiado", game_language) # Notificar a todas las escenas activas

### ============================
### NUEVO: Persistencia de Audio
### ============================

func guardar_audio_settings() -> void:
	var cfg = ConfigFile.new()
	cfg.load(audio_config_path)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.save(audio_config_path)

func cargar_audio_settings() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(audio_config_path) == OK:
		music_volume = cfg.get_value("audio", "music_volume", 1.0)
		sfx_volume = cfg.get_value("audio", "sfx_volume", 1.0)
	else:
		music_volume = 1.0
		sfx_volume = 1.0

	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		linear_to_db(music_volume)
	)
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"),
		linear_to_db(sfx_volume)
	)
