# Pastry Level 1
extends Node2D

signal level_cleared

@onready var characters = $Personajes
@onready var customer_scene := preload("res://scenes/characters/Customer.tscn")
@export var pause_texture: Texture

var characters_mood_file_path = "res://i18n/characters_moods.json"
var interact_btns_file_path = "res://i18n/interaction_texts.json"
var customer_count = 1 if GameController.IS_TESTING else 4
var current_customer: Node2D = null

var center_frac_x := 0.5 # 0.25 cuando se abra el minijuego
var original_viewport_size: Vector2

# Escena del nivel base
func _ready():
	print("ready from LEVEL 1********")
	add_to_group("levels")
	original_viewport_size = get_viewport().size
	get_viewport().connect("size_changed", Callable(self, "_on_viewport_resized"))
		
	# Música diferida
	call_deferred("_start_level_music")
	
	# Cargar combinaciones y preparar cola
	GameController.show_newton_layer()
	var universe_combinations := get_random_combinations(characters_mood_file_path, customer_count)
	GlobalManager.initialize_customers(universe_combinations)
	AudioManager.play_crowd_talking_sfx()
	spawn_next_customer()
	GlobalManager.initialize_recipes("level1")

func spawn_next_customer():
	GlobalManager.recipe_started = false
	var next := GlobalManager.get_next_customer()
	if next.is_empty():
		emit_signal("level_cleared")
		return 
	
	current_customer = customer_scene.instantiate()
	current_customer.visible = false # Evita que se vea el new customer en la esquina
	current_customer.setup(next, GlobalManager.game_language)
	characters.add_child(current_customer)
	
	# Conectar señales
	current_customer.arrived_at_center.connect(_on_customer_seated)
	current_customer.connect("listen_customer_pressed", Callable(self, "_on_listen_customer_pressed"))

	# Estado del cliente
	current_customer.set_state(GlobalManager.State.ENTERING)
	
	# Esperar el frame cuando se hace resize 
	await get_tree().process_frame
	
	# Calcular posiciones usando helpers del customer
	var start_pos = current_customer.get_initial_position()
	current_customer.visible = true
	var target_pos = current_customer.get_target_position()
	current_customer.position = start_pos
	current_customer.move_to(target_pos)

func get_random_combinations(json_path: String, count: int = 4) -> Array:
	var customer_data = FileHelper.read_data_from_file(json_path)

	if typeof(customer_data) != TYPE_DICTIONARY: #27
		push_error("El JSON no es un Dictionary válido")
		return []
	
	if not customer_data.has("combinations"):
		push_error("El JSON no tiene la sección 'combinations'")
		return []
		
	# Clonar customer_data, para no modificar el original, y mezclar
	var combos = customer_data["combinations"].duplicate()
	combos.shuffle()

	# Tomar las primeras `count` combinaciones
	var selected : Array = combos.slice(0, min(count, combos.size()))
	return selected

# La reaccion (animacion + sfx) debe durar maximo 2.5
func show_customer_reaction(success: bool):
	#print("DEBUG > show_customer_reaction, success: ", success, current_customer)
	if current_customer:
		if success:
			current_customer.react_happy()
		else:
			current_customer.react_angry()
	
	# Esperar un ratito antes de traer al próximo cliente
	await get_tree().create_timer(1.5).timeout
	
	# Animación de salida: alejar hacia el fonfo
	if current_customer and is_instance_valid(current_customer):
		var tween := create_tween()
		tween.tween_property(current_customer, "scale", current_customer.scale * 0.5, 1.0)
		tween.parallel().tween_property(current_customer, "modulate:a", 0.0, 1.0)
		tween.tween_callback(Callable(self, "_on_customer_exit_complete"))

# Funciones lanzadas por los signals
func _on_customer_seated(cust: Node2D):
	var btn_listen : TextureButton = cust.get_node("BtnListen")
	btn_listen.show()
	#print("DEBUG > _on_customer_seated El cliente llegó y se sentó: ", cust.character_id, "\n", cust.mood_id, "\n", cust.texts, "\n", cust.language)
	
func _on_listen_customer_pressed():
	UILayerManager.show_message(current_customer.texts[current_customer.language])

func _on_ingredients_minigame_started():
	if current_customer:
		current_customer.hide_listen_button()

func _on_customer_exit_complete():
	if not current_customer or not is_instance_valid(current_customer):
		return
	current_customer.visible = false
	current_customer.queue_free()
	current_customer = null
	AudioManager.stop_customer_sfx()
	
	# Preparar siguiente cliente
	spawn_next_customer()

func _on_viewport_resized():
	if current_customer:
		var new_target = current_customer.get_target_position()

		# Mantener coherencia en X e Y
		current_customer.position.x = new_target.x
		current_customer.position.y = new_target.y

func _start_level_music():
	AudioManager.stop_end_music()
	AudioManager.play_game_music()
	AudioManager.play_crowd_talking_sfx()
	
# Debug :]
func print_combos(combos):
	for comb in combos:
		print("Personaje: ", comb["character_id"], "\nEstado: ", comb["mood_id"], "\nTexto: ", comb["texts"][GlobalManager.game_language])
		print("......")
