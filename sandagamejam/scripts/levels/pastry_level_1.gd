# Pastry Level 1
extends Node2D

signal level_cleared
signal ingredients_timeout

@onready var characters = $Personajes
@onready var customer_scene := preload("res://scenes/characters/Customer.tscn")
@export var pause_texture: Texture

var characters_mood_file_path = "res://i18n/characters_moods.json"
var interact_btns_file_path = "res://i18n/interaction_texts.json"
var customer_count = 1 if GameController.IS_TESTING else 4
var current_customer: Node2D = null

var center_frac_x := 0.5 # 0.25 cuando se abra el minijuego
var original_viewport_size: Vector2

# Variables para ingredientes en la mesa
var active_ingredients: Array = []
var active_tweens: Array = []
var ingredients_container: Node2D = null
var prepare_button: Button = null
var minigame_active: bool = false

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

# ============ INGREDIENTES EN LA MESA ============

func start_ingredients_on_table(recipe_data: Dictionary, ingr_loop: Array) -> void:
	print("🍳 Iniciando ingredientes en la mesa: ", ingr_loop)
	print("🍳 Cantidad de ingredientes: ", ingr_loop.size())

	# Crear contenedor si no existe
	if not ingredients_container:
		ingredients_container = Node2D.new()
		ingredients_container.name = "IngredientsContainer"
		ingredients_container.z_index = 5
		ingredients_container.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ingredients_container)
		print("📦 Contenedor creado, en árbol: ", ingredients_container.is_inside_tree())

	# Limpiar ingredientes anteriores
	clear_ingredients()

	# Configuracion del movimiento horizontal (de izquierda a derecha)
	var viewport_size = get_viewport().get_visible_rect().size
	var start_x: float = -100.0  # Empieza desde la izquierda (fuera de pantalla)
	var end_x: float = viewport_size.x + 100.0  # Sale por la derecha
	var table_y: float = 540.0  # Sobre la mesa
	var duration: float = 5.0
	var spawn_interval: float = 0.7
	print("📐 start_x: ", start_x, " end_x: ", end_x)

	var ingredients_created = 0
	for i in range(ingr_loop.size()):
		var ing_id = ingr_loop[i]

		var ingredient = create_clickable_ingredient(ing_id)
		if not ingredient:
			print("❌ No se pudo crear ingrediente: ", ing_id)
			continue

		ingredients_container.add_child(ingredient)
		active_ingredients.append(ingredient)
		ingredients_created += 1

		# Posicion inicial con variacion vertical mas amplia
		var random_y = table_y + randf_range(-60.0, 40.0)
		ingredient.position = Vector2(start_x, random_y)

		# Animacion de movimiento horizontal
		var tween = get_tree().create_tween()
		tween.bind_node(ingredient)
		tween.tween_property(ingredient, "position:x", end_x, duration) \
			.set_trans(Tween.TRANS_LINEAR) \
			.set_delay(spawn_interval * i)
		tween.tween_callback(ingredient.queue_free)
		active_tweens.append(tween)

		if i == 0:
			print("🎬 Primer tween - delay: 0, duracion: ", duration)
		if i == ingr_loop.size() - 1:
			print("🎬 Último tween - delay: ", spawn_interval * i, ", duracion: ", duration)

		# En el ultimo ingrediente, emitir timeout
		if i == ingr_loop.size() - 1:
			print("🔗 Conectando timeout al ingrediente #", i, " (último)")
			tween.finished.connect(func():
				print("⚠️ NIVEL: Último ingrediente terminó, emitiendo timeout")
				minigame_active = false
				if prepare_button and is_instance_valid(prepare_button):
					prepare_button.queue_free()
					prepare_button = null
				emit_signal("ingredients_timeout")
			)

	print("✅ Ingredientes creados: ", ingredients_created, " de ", ingr_loop.size())

	# Crear botón de preparar
	minigame_active = true
	create_prepare_button()

func create_prepare_button() -> void:
	if prepare_button and is_instance_valid(prepare_button):
		prepare_button.queue_free()

	prepare_button = Button.new()
	prepare_button.text = GlobalManager.btn_cook_recipe_label
	prepare_button.custom_minimum_size = Vector2(200, 60)
	prepare_button.disabled = true  # Deshabilitado hasta seleccionar ingredientes

	# Posicionar en la parte inferior central
	var viewport_size = get_viewport().get_visible_rect().size
	prepare_button.position = Vector2(viewport_size.x / 2 - 100, viewport_size.y - 100)

	# Añadir al UILayer del nivel
	var ui_layer = $UILayer
	if ui_layer:
		ui_layer.add_child(prepare_button)
	else:
		add_child(prepare_button)

	prepare_button.pressed.connect(_on_prepare_button_pressed)

func _on_prepare_button_pressed() -> void:
	if not minigame_active:
		return

	AudioManager.play_click_sfx()
	GlobalManager.recipe_started = true
	minigame_active = false

	# Limpiar ingredientes y botón
	clear_ingredients()
	if prepare_button and is_instance_valid(prepare_button):
		prepare_button.queue_free()
		prepare_button = null

	# Hacer que Newton cocine
	GameController.make_newton_cook()

func enable_prepare_button() -> void:
	if prepare_button and is_instance_valid(prepare_button):
		prepare_button.disabled = false

func create_clickable_ingredient(ingredient_id: String) -> Area2D:
	var path = "res://assets/pastry/ingredients/%s.png" % ingredient_id
	if not ResourceLoader.exists(path):
		return null

	var tex = load(path)

	var area = Area2D.new()
	area.add_to_group("ingredients")
	area.set_meta("id", ingredient_id)
	area.input_pickable = true

	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(0.4, 0.4)
	area.add_child(sprite)

	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 45
	collision.shape = shape
	area.add_child(collision)

	area.z_index = 10

	# Conectar click
	area.input_event.connect(_on_table_ingredient_clicked.bind(area, ingredient_id))

	return area

func _on_table_ingredient_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, area: Area2D, ing_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		AudioManager.play_collect_ingredient_sfx()
		GlobalManager.collected_ingredients.append(ing_id)

		# Animacion de recoleccion
		var tween = create_tween()
		tween.tween_property(area, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(area, "modulate:a", 0.0, 0.15)
		tween.tween_callback(area.queue_free)

		# Remover de la lista
		active_ingredients.erase(area)

		# Habilitar boton de preparar si hay ingredientes seleccionados
		if GlobalManager.collected_ingredients.size() > 0:
			enable_prepare_button()

func clear_ingredients() -> void:
	print("🧹 clear_ingredients llamado - tweens activos: ", active_tweens.size())
	# Detener tweens
	for t in active_tweens:
		if is_instance_valid(t):
			t.kill()
	active_tweens.clear()

	# Eliminar ingredientes
	for ing in active_ingredients:
		if is_instance_valid(ing):
			ing.queue_free()
	active_ingredients.clear()

	# Limpiar contenedor
	if ingredients_container:
		for child in ingredients_container.get_children():
			child.queue_free()

func stop_ingredients_minigame() -> void:
	minigame_active = false
	clear_ingredients()
	if prepare_button and is_instance_valid(prepare_button):
		prepare_button.queue_free()
		prepare_button = null
