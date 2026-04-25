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
var minigame_active: bool = false

# UI del minijuego
var ingredients_counter_label: Label = null
var progress_bar: ProgressBar = null
var total_ingredients_needed: int = 0
var current_customer_index: int = 0
var progress_start_time: float = 0.0
var progress_total_duration: float = 0.0

# Indicador de progreso de clientes
var customer_progress_container: HBoxContainer = null
var customer_dots: Array = []

# Tutorial
var tutorial_shown: Dictionary = {
	"listen": false,
	"select_recipe": false,
	"collect": false,
	"prepare": false
}
var current_tooltip: Control = null

# Ambiente
var ambient_container: Node2D = null
var ambient_lights: Array = []
var steam_timer: Timer = null

# Receta visible durante minijuego
var recipe_display: Control = null
var recipe_ingredient_labels: Array = []
var current_recipe_ingredients: Array = []

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

	# Crear indicador de progreso de clientes
	create_customer_progress_indicator()

	# Efectos ambientales deshabilitados temporalmente
	# create_ambient_effects()

	spawn_next_customer()
	GlobalManager.initialize_recipes("level1")

func _exit_tree() -> void:
	# Limpiar elementos UI (se liberan automáticamente con el nivel)
	customer_progress_container = null
	ingredients_counter_label = null
	progress_bar = null
	recipe_display = null

func spawn_next_customer():
	GlobalManager.recipe_started = false
	var next := GlobalManager.get_next_customer()
	if next.is_empty():
		emit_signal("level_cleared")
		return

	# Incrementar índice de cliente (para velocidad progresiva)
	current_customer_index += 1

	# Acelerar música gradualmente con cada cliente (estilo Club Penguin)
	if current_customer_index > 1:
		AudioManager.speed_up_music_gradually(0.03)

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
			# Mini celebracion estilo Club Penguin
			create_celebration_effect(current_customer.global_position)
		else:
			current_customer.react_angry()
			# Mostrar animación de pérdida de vida durante la salida del cliente
			show_life_lost_animation(current_customer.global_position)

	# Indicador de progreso deshabilitado temporalmente
	# update_customer_dot(current_customer_index - 1, success)

	# Esperar menos tiempo para crear overlap
	await get_tree().create_timer(0.8).timeout

	# Animación de salida: alejar hacia el fondo
	if current_customer and is_instance_valid(current_customer):
		var exiting_customer = current_customer
		var tween := create_tween()
		tween.tween_property(exiting_customer, "scale", exiting_customer.scale * 0.5, 0.8)
		tween.parallel().tween_property(exiting_customer, "modulate:a", 0.0, 0.8)
		tween.tween_callback(func():
			if exiting_customer and is_instance_valid(exiting_customer):
				exiting_customer.queue_free()
		)

		# Overlap: empezar a traer el siguiente cliente mientras el actual sale
		current_customer = null
		AudioManager.stop_customer_sfx()
		spawn_next_customer()

# Funciones lanzadas por los signals
func _on_customer_seated(cust: Node2D):
	var btn_listen : TextureButton = cust.get_node("BtnListen")
	btn_listen.show()
	#print("DEBUG > _on_customer_seated El cliente llegó y se sentó: ", cust.character_id, "\n", cust.mood_id, "\n", cust.texts, "\n", cust.language)

	# Tutorial deshabilitado temporalmente
	# show_listen_tutorial()
	
func _on_listen_customer_pressed():
	UILayerManager.show_message(current_customer.texts[current_customer.language])

func _on_ingredients_minigame_started():
	if current_customer:
		current_customer.hide_listen_button()

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

# ============ INDICADOR DE PROGRESO DE CLIENTES ============

func create_customer_progress_indicator() -> void:
	# Deshabilitado temporalmente para debug
	return
	#if customer_progress_container and is_instance_valid(customer_progress_container):
	#	customer_progress_container.queue_free()
	#
	#customer_progress_container = HBoxContainer.new()
	#customer_progress_container.add_theme_constant_override("separation", 6)
	#customer_progress_container.position = Vector2(1060, 610)
	#
	#if UILayerManager.ui_layer_instance:
	#	UILayerManager.ui_layer_instance.add_child(customer_progress_container)
	#else:
	#	get_tree().root.add_child(customer_progress_container)
	#
	#customer_dots.clear()
	#
	## Crear círculos para cada cliente (pequeños y sutiles)
	#for i in range(customer_count):
	#	var panel = Panel.new()
	#	panel.custom_minimum_size = Vector2(12, 12)
	#
	#	var style = StyleBoxFlat.new()
	#	style.bg_color = Color(0.4, 0.4, 0.4, 0.5)  # Gris semi-transparente
	#	style.corner_radius_top_left = 6
	#	style.corner_radius_top_right = 6
	#	style.corner_radius_bottom_left = 6
	#	style.corner_radius_bottom_right = 6
	#	panel.add_theme_stylebox_override("panel", style)
	#
	#	customer_progress_container.add_child(panel)
	#	customer_dots.append(panel)

func update_customer_dot(index: int, success: bool) -> void:
	if index < 0 or index >= customer_dots.size():
		return

	var panel = customer_dots[index] as Panel
	if not panel:
		return

	var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if success:
		style.bg_color = Color(0.2, 0.8, 0.3)  # Verde (éxito)
	else:
		style.bg_color = Color(0.9, 0.2, 0.2)  # Rojo (fallo)

	panel.add_theme_stylebox_override("panel", style)

	# Animación de pulso
	var tween = create_tween()
	tween.tween_property(panel, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.1)

# Debug :]
func print_combos(combos):
	for comb in combos:
		print("Personaje: ", comb["character_id"], "\nEstado: ", comb["mood_id"], "\nTexto: ", comb["texts"][GlobalManager.game_language])
		print("......")

# ============ TUTORIAL ============

func show_tutorial_tooltip(key: String, text: String, pos: Vector2, duration: float = 3.0) -> void:
	# Solo mostrar si no se ha mostrado antes
	if tutorial_shown.get(key, false):
		return
	tutorial_shown[key] = true

	# Limpiar tooltip anterior
	if current_tooltip and is_instance_valid(current_tooltip):
		current_tooltip.queue_free()

	# Crear panel de tooltip
	var tooltip = PanelContainer.new()
	tooltip.z_index = 200
	tooltip.position = pos

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.1, 0.95)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_color = Color(1, 0.85, 0.4)  # Dorado
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	tooltip.add_theme_stylebox_override("panel", style)

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.95, 0.8))
	tooltip.add_child(label)

	var ui_layer = $UILayer
	if ui_layer:
		ui_layer.add_child(tooltip)
	else:
		add_child(tooltip)

	current_tooltip = tooltip

	# Animacion de entrada
	tooltip.modulate.a = 0
	tooltip.scale = Vector2(0.8, 0.8)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(tooltip, "modulate:a", 1.0, 0.3)
	tween.tween_property(tooltip, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Animacion de salida despues de la duracion
	tween.set_parallel(false)
	tween.tween_interval(duration)
	tween.tween_property(tooltip, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		if tooltip and is_instance_valid(tooltip):
			tooltip.queue_free()
	)

func hide_current_tooltip() -> void:
	if current_tooltip and is_instance_valid(current_tooltip):
		var tween = create_tween()
		tween.tween_property(current_tooltip, "modulate:a", 0.0, 0.2)
		tween.tween_callback(func():
			if current_tooltip and is_instance_valid(current_tooltip):
				current_tooltip.queue_free()
				current_tooltip = null
		)

func show_listen_tutorial() -> void:
	if current_customer_index == 1:  # Solo primer cliente
		var viewport_size = get_viewport().get_visible_rect().size
		show_tutorial_tooltip("listen", "Escucha al cliente para saber que quiere", Vector2(viewport_size.x * 0.3, 200), 4.0)

func show_collect_tutorial() -> void:
	if current_customer_index == 1:  # Solo primer cliente
		show_tutorial_tooltip("collect", "Haz clic en los ingredientes para recolectarlos", Vector2(150, 380), 4.0)

func show_prepare_tutorial() -> void:
	if current_customer_index == 1 and not tutorial_shown["prepare"]:  # Solo primer cliente
		var viewport_size = get_viewport().get_visible_rect().size
		show_tutorial_tooltip("prepare", "Presiona PREPARAR cuando tengas todos", Vector2(viewport_size.x / 2 - 150, viewport_size.y - 150), 3.0)

# ============ AMBIENTE CON VIDA ============

func create_ambient_effects() -> void:
	# Crear contenedor para efectos ambientales
	if ambient_container and is_instance_valid(ambient_container):
		ambient_container.queue_free()

	ambient_container = Node2D.new()
	ambient_container.name = "AmbientEffects"
	ambient_container.z_index = -1  # Detras de todo
	add_child(ambient_container)

	# Crear luces decorativas parpadeantes
	create_ambient_lights()

	# Iniciar timer para vapor
	start_steam_effects()

func create_ambient_lights() -> void:
	var viewport_size = get_viewport().get_visible_rect().size
	var light_positions = [
		Vector2(100, 80),
		Vector2(300, 60),
		Vector2(500, 90),
		Vector2(700, 70),
		Vector2(900, 85),
	]

	for pos in light_positions:
		var light = ColorRect.new()
		light.size = Vector2(8, 8)
		light.position = pos
		light.color = Color(1, 0.9, 0.5, 0.6)  # Luz calida
		ambient_container.add_child(light)
		ambient_lights.append(light)

		# Animacion de parpadeo
		animate_light_twinkle(light)

func animate_light_twinkle(light: ColorRect) -> void:
	var tween = create_tween().set_loops()
	var delay = randf_range(0.0, 2.0)
	var duration = randf_range(1.5, 3.0)
	var min_alpha = randf_range(0.2, 0.4)
	var max_alpha = randf_range(0.7, 1.0)

	tween.tween_interval(delay)
	tween.tween_property(light, "color:a", min_alpha, duration * 0.5).set_trans(Tween.TRANS_SINE)
	tween.tween_property(light, "color:a", max_alpha, duration * 0.5).set_trans(Tween.TRANS_SINE)

func start_steam_effects() -> void:
	if steam_timer and is_instance_valid(steam_timer):
		steam_timer.queue_free()

	steam_timer = Timer.new()
	steam_timer.wait_time = 0.8
	steam_timer.autostart = true
	add_child(steam_timer)

	steam_timer.timeout.connect(create_steam_particle)

func create_steam_particle() -> void:
	if not ambient_container or not is_instance_valid(ambient_container):
		return

	# Posiciones de donde sale vapor (cerca de donde estaria la cocina)
	var steam_sources = [
		Vector2(950, 500),  # Cerca de Newton
		Vector2(920, 510),
	]

	if steam_sources.size() == 0:
		return
	var source = steam_sources[randi() % steam_sources.size()]
	source.x += randf_range(-20, 20)

	var steam = ColorRect.new()
	steam.size = Vector2(randf_range(6, 12), randf_range(6, 12))
	steam.position = source
	steam.color = Color(1, 1, 1, randf_range(0.15, 0.3))
	steam.z_index = 2
	ambient_container.add_child(steam)

	# Animacion: sube y se desvanece
	var target_y = source.y - randf_range(60, 120)
	var target_x = source.x + randf_range(-30, 30)
	var duration = randf_range(2.0, 3.5)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(steam, "position", Vector2(target_x, target_y), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(steam, "color:a", 0.0, duration)
	tween.tween_property(steam, "size", steam.size * 2, duration)
	tween.set_parallel(false)
	tween.tween_callback(steam.queue_free)

func stop_ambient_effects() -> void:
	if steam_timer and is_instance_valid(steam_timer):
		steam_timer.stop()
		steam_timer.queue_free()
		steam_timer = null

	if ambient_container and is_instance_valid(ambient_container):
		ambient_container.queue_free()
		ambient_container = null

	ambient_lights.clear()

# ============ INGREDIENTES EN LA MESA ============

func start_ingredients_on_table(recipe_data: Dictionary, ingr_loop: Array) -> void:
	print("🍳 Iniciando ingredientes en la mesa: ", ingr_loop)
	print("🍳 Cantidad de ingredientes: ", ingr_loop.size())

	# Guardar total de ingredientes necesarios para la receta
	total_ingredients_needed = recipe_data["ingredients"].size()

	# Guardar ingredientes correctos de la receta para validación
	current_recipe_ingredients = recipe_data.get("ingredients", [])

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

	# UI del minijuego (contador de ingredientes y barra de progreso)
	create_minigame_ui()

	# Configuracion del movimiento horizontal (de izquierda a derecha)
	var viewport_size = get_viewport().get_visible_rect().size
	var start_x: float = -100.0  # Empieza desde la izquierda (fuera de pantalla)
	var end_x: float = viewport_size.x + 100.0  # Sale por la derecha
	var table_y: float = 540.0  # Sobre la mesa

	# Velocidad según cliente (primer cliente más lento, últimos más rápidos)
	var base_duration: float = 6.0
	var speed_increase: float = 0.8  # Cada cliente es 0.8s más rápido
	var duration: float = max(3.0, base_duration - (current_customer_index * speed_increase))
	var spawn_interval: float = 0.6
	print("📐 start_x: ", start_x, " end_x: ", end_x, " duration: ", duration, " (cliente #", current_customer_index, ")")

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
				clear_minigame_ui()
				emit_signal("ingredients_timeout")
			)

	print("✅ Ingredientes creados: ", ingredients_created, " de ", ingr_loop.size())

	# Calcular duración total del minijuego para la barra de progreso
	var total_duration = duration + (spawn_interval * (ingr_loop.size() - 1))
	start_progress_bar_timer(total_duration)

	# Activar minijuego
	minigame_active = true

	# Deshabilitado temporalmente para debug
	# create_recipe_display(recipe_data)
	# show_collect_tutorial()

func create_minigame_ui() -> void:
	var viewport_size = get_viewport().get_visible_rect().size

	# Crear contador de ingredientes (esquina superior derecha, debajo del botón pausa)
	if ingredients_counter_label and is_instance_valid(ingredients_counter_label):
		ingredients_counter_label.queue_free()

	ingredients_counter_label = Label.new()
	ingredients_counter_label.text = "0/%d" % total_ingredients_needed
	ingredients_counter_label.add_theme_font_size_override("font_size", 24)
	ingredients_counter_label.add_theme_color_override("font_color", Color(1, 1, 1))
	ingredients_counter_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	ingredients_counter_label.add_theme_constant_override("shadow_offset_x", 2)
	ingredients_counter_label.add_theme_constant_override("shadow_offset_y", 2)
	ingredients_counter_label.position = Vector2(viewport_size.x - 80, 90)

	# Añadir al UILayer del nivel
	var ui_layer = $UILayer
	if ui_layer:
		ui_layer.add_child(ingredients_counter_label)
	else:
		add_child(ingredients_counter_label)

	# Crear barra de progreso (debajo del contador, en la esquina superior derecha)
	if progress_bar and is_instance_valid(progress_bar):
		progress_bar.queue_free()

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(150, 12)
	progress_bar.max_value = 100
	progress_bar.value = 100
	progress_bar.show_percentage = false
	progress_bar.position = Vector2(viewport_size.x - 170, 120)

	# Estilo de la barra
	var style_bg = StyleBoxFlat.new()
	style_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	style_bg.corner_radius_top_left = 5
	style_bg.corner_radius_top_right = 5
	style_bg.corner_radius_bottom_left = 5
	style_bg.corner_radius_bottom_right = 5
	progress_bar.add_theme_stylebox_override("background", style_bg)

	var style_fill = StyleBoxFlat.new()
	style_fill.bg_color = Color(0.2, 0.8, 0.3)  # Verde
	style_fill.corner_radius_top_left = 5
	style_fill.corner_radius_top_right = 5
	style_fill.corner_radius_bottom_left = 5
	style_fill.corner_radius_bottom_right = 5
	progress_bar.add_theme_stylebox_override("fill", style_fill)

	# Añadir al UILayer del nivel
	var ui_layer_pb = $UILayer
	if ui_layer_pb:
		ui_layer_pb.add_child(progress_bar)
	else:
		add_child(progress_bar)

func update_ingredients_counter() -> void:
	if ingredients_counter_label and is_instance_valid(ingredients_counter_label):
		var collected = GlobalManager.collected_ingredients.size()
		ingredients_counter_label.text = "%d/%d" % [collected, total_ingredients_needed]

		# Cambiar color si tiene todos los necesarios
		if collected >= total_ingredients_needed:
			ingredients_counter_label.add_theme_color_override("font_color", Color(0.2, 1, 0.2))

func update_progress_bar(progress: float) -> void:
	if progress_bar and is_instance_valid(progress_bar):
		progress_bar.value = progress * 100

		# Cambiar color según progreso
		var style_fill = progress_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if style_fill:
			if progress < 0.3:
				style_fill.bg_color = Color(0.9, 0.2, 0.2)  # Rojo
			elif progress < 0.6:
				style_fill.bg_color = Color(0.9, 0.7, 0.2)  # Amarillo
			else:
				style_fill.bg_color = Color(0.2, 0.8, 0.3)  # Verde

func start_progress_bar_timer(total_duration: float) -> void:
	progress_start_time = Time.get_ticks_msec() / 1000.0
	progress_total_duration = total_duration

func _process(_delta: float) -> void:
	# Actualizar barra de progreso si el minijuego está activo
	if minigame_active and progress_total_duration > 0:
		var elapsed = (Time.get_ticks_msec() / 1000.0) - progress_start_time
		var progress = 1.0 - (elapsed / progress_total_duration)
		progress = clamp(progress, 0.0, 1.0)
		update_progress_bar(progress)

		# Si el tiempo se acabó y no se ha completado la receta, emitir timeout
		if progress <= 0.0 and GlobalManager.collected_ingredients.size() < total_ingredients_needed:
			print("⚠️ NIVEL: Tiempo acabado, emitiendo timeout desde _process")
			minigame_active = false
			clear_ingredients()
			clear_minigame_ui()
			emit_signal("ingredients_timeout")

func clear_minigame_ui() -> void:
	progress_total_duration = 0.0  # Detener actualización de barra
	if ingredients_counter_label and is_instance_valid(ingredients_counter_label):
		ingredients_counter_label.queue_free()
		ingredients_counter_label = null
	if progress_bar and is_instance_valid(progress_bar):
		progress_bar.queue_free()
		progress_bar = null
	clear_recipe_display()

# ============ RECETA VISIBLE CON CHECKMARKS ============

func create_recipe_display(recipe_data: Dictionary) -> void:
	clear_recipe_display()

	current_recipe_ingredients = recipe_data.get("ingredients", [])
	recipe_ingredient_labels.clear()

	var viewport_size = get_viewport().get_visible_rect().size

	recipe_display = PanelContainer.new()
	# Posicionar en la esquina superior derecha, debajo del contador
	recipe_display.position = Vector2(viewport_size.x - 200, 145)
	recipe_display.z_index = 50

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.08, 0.92)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_color = Color(0.8, 0.65, 0.3)
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.content_margin_left = 16
	style.content_margin_right = 16
	recipe_display.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	recipe_display.add_child(vbox)

	# Titulo
	var title = Label.new()
	title.text = "Receta:"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	vbox.add_child(title)

	# Ingredientes de la receta
	for ing_id in current_recipe_ingredients:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		# Icono de estado (checkmark o cuadrado vacio)
		var status = Label.new()
		status.text = "[ ]"
		status.add_theme_font_size_override("font_size", 16)
		status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		status.custom_minimum_size = Vector2(30, 0)
		hbox.add_child(status)

		# Nombre del ingrediente
		var name_label = Label.new()
		name_label.text = get_ingredient_name(ing_id)
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		hbox.add_child(name_label)

		vbox.add_child(hbox)

		# Guardar referencia al label de estado
		recipe_ingredient_labels.append({
			"id": ing_id,
			"status_label": status,
			"name_label": name_label,
			"collected": false
		})

	# Añadir al UILayer del nivel
	var ui_layer_rd = $UILayer
	if ui_layer_rd:
		ui_layer_rd.add_child(recipe_display)
	else:
		add_child(recipe_display)

	# Animacion de entrada
	recipe_display.modulate.a = 0
	recipe_display.scale = Vector2(0.9, 0.9)
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(recipe_display, "modulate:a", 1.0, 0.3)
	tween.tween_property(recipe_display, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func update_recipe_checkmark(ing_id: String) -> void:
	# Buscar si el ingrediente esta en la receta
	for item in recipe_ingredient_labels:
		if item["id"] == ing_id and not item["collected"]:
			item["collected"] = true
			var status_label = item["status_label"] as Label
			var name_label = item["name_label"] as Label

			# Marcar como recolectado con checkmark verde
			status_label.text = "[v]"
			status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
			name_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))

			# Animacion de pulso
			var tween = create_tween()
			tween.tween_property(status_label, "scale", Vector2(1.3, 1.3), 0.1)
			tween.tween_property(status_label, "scale", Vector2(1.0, 1.0), 0.1)
			return

	# Si no esta en la receta, mostrar indicador de ingrediente incorrecto
	# (solo visual, no penaliza)
	show_wrong_ingredient_indicator()

func show_wrong_ingredient_indicator() -> void:
	if not recipe_display or not is_instance_valid(recipe_display):
		return

	# Flash rojo sutil en el panel
	var original_color = recipe_display.get_theme_stylebox("panel").border_color
	var style = recipe_display.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.border_color = Color(0.9, 0.3, 0.2)
	recipe_display.add_theme_stylebox_override("panel", style)

	var tween = create_tween()
	tween.tween_interval(0.15)
	tween.tween_callback(func():
		if recipe_display and is_instance_valid(recipe_display):
			var restore_style = recipe_display.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			restore_style.border_color = original_color
			recipe_display.add_theme_stylebox_override("panel", restore_style)
	)

func clear_recipe_display() -> void:
	if recipe_display and is_instance_valid(recipe_display):
		recipe_display.queue_free()
		recipe_display = null
	recipe_ingredient_labels.clear()
	current_recipe_ingredients.clear()

func get_ingredient_name(ing_id: String) -> String:
	# Mapeo simple de IDs a nombres
	var names = {
		"ing_001": "Harina",
		"ing_002": "Manzana",
		"ing_003": "Leche",
		"ing_004": "Huevo",
		"ing_005": "Azucar",
		"ing_006": "Mantequilla",
		"ing_007": "Miel",
		"ing_008": "Canela",
		"ing_009": "Vainilla",
		"ing_010": "Chocolate",
		"ing_202": "Manzana*",
		"ing_205": "Azucar*",
		"ing_207": "Miel*",
	}
	return names.get(ing_id, ing_id)

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
		# Verificar si el ingrediente es correcto
		var is_correct = current_recipe_ingredients.has(ing_id)

		if is_correct:
			# Ingrediente CORRECTO - Agregar y contar para el total
			AudioManager.play_collect_ingredient_sfx()
			create_collect_effect(area.global_position)
			GlobalManager.collected_ingredients.append(ing_id)

			# Actualizar checkmark en la receta
			update_recipe_checkmark(ing_id)
		else:
			# Ingrediente INCORRECTO - Solo penalizar, NO agregar
			AudioManager.play_wrong_recipe_sfx()
			create_wrong_ingredient_effect(area.global_position)
			# Penalización de tiempo (quitar 5 segundos)
			GlobalManager.apply_penalty(5)

		# Animacion de recoleccion (para ambos casos)
		var tween = create_tween()
		tween.tween_property(area, "scale", Vector2(1.5, 1.5), 0.1)
		tween.tween_property(area, "modulate:a", 0.0, 0.15)
		tween.tween_callback(area.queue_free)

		# Remover de la lista
		active_ingredients.erase(area)

		# Actualizar contador (solo cuenta ingredientes correctos)
		update_ingredients_counter()

		# Verificar si ya no quedan ingredientes y no se recolectaron todos los necesarios
		if active_ingredients.size() == 0 and GlobalManager.collected_ingredients.size() < total_ingredients_needed:
			# Timeout: se acabaron los ingredientes sin completar la receta
			print("⚠️ NIVEL: No quedan ingredientes, emitiendo timeout")
			minigame_active = false
			clear_minigame_ui()
			emit_signal("ingredients_timeout")
			return

		# Preparar automáticamente cuando tiene todos los ingredientes CORRECTOS necesarios
		if GlobalManager.collected_ingredients.size() >= total_ingredients_needed:
			auto_prepare_dish()

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

func auto_prepare_dish() -> void:
	if not minigame_active:
		return

	print("🍳 Auto-preparando platillo con ingredientes recolectados")
	AudioManager.play_click_sfx()
	GlobalManager.recipe_started = true
	minigame_active = false

	# Limpiar ingredientes y UI
	clear_ingredients()
	clear_minigame_ui()

	# Hacer que Newton cocine
	GameController.make_newton_cook()

func stop_ingredients_minigame() -> void:
	minigame_active = false
	clear_ingredients()
	clear_minigame_ui()

# ============ EFECTOS VISUALES ============

func create_collect_effect(pos: Vector2) -> void:
	# Flash blanco
	var flash = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.6)
	flash.size = Vector2(80, 80)
	flash.position = pos - Vector2(40, 40)
	flash.z_index = 100
	add_child(flash)

	var flash_tween = create_tween()
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.15)
	flash_tween.tween_callback(flash.queue_free)

	# Partículas simples
	for i in range(5):
		var particle = ColorRect.new()
		particle.color = Color(1, 0.9, 0.3)  # Amarillo dorado
		particle.size = Vector2(8, 8)
		particle.position = pos - Vector2(4, 4)
		particle.z_index = 99
		add_child(particle)

		var angle = randf() * TAU
		var distance = randf_range(30, 60)
		var target_pos = pos + Vector2(cos(angle), sin(angle)) * distance

		var p_tween = create_tween()
		p_tween.set_parallel(true)
		p_tween.tween_property(particle, "position", target_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		p_tween.tween_property(particle, "modulate:a", 0.0, 0.3)
		p_tween.set_parallel(false)
		p_tween.tween_callback(particle.queue_free)

func create_wrong_ingredient_effect(pos: Vector2) -> void:
	# Flash rojo para ingrediente incorrecto
	var flash = ColorRect.new()
	flash.color = Color(1, 0.2, 0.2, 0.7)  # Rojo
	flash.size = Vector2(100, 100)
	flash.position = pos - Vector2(50, 50)
	flash.z_index = 100
	add_child(flash)

	var flash_tween = create_tween()
	flash_tween.tween_property(flash, "modulate:a", 0.0, 0.2)
	flash_tween.tween_callback(flash.queue_free)

	# Partículas rojas
	for i in range(6):
		var particle = ColorRect.new()
		particle.color = Color(1, 0.3, 0.2)  # Rojo
		particle.size = Vector2(10, 10)
		particle.position = pos - Vector2(5, 5)
		particle.z_index = 99
		add_child(particle)

		var angle = randf() * TAU
		var distance = randf_range(40, 70)
		var target_pos = pos + Vector2(cos(angle), sin(angle)) * distance

		var p_tween = create_tween()
		p_tween.set_parallel(true)
		p_tween.tween_property(particle, "position", target_pos, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		p_tween.tween_property(particle, "modulate:a", 0.0, 0.4)
		p_tween.set_parallel(false)
		p_tween.tween_callback(particle.queue_free)

	# Símbolo X grande
	var x_label = Label.new()
	x_label.text = "✗"
	x_label.add_theme_font_size_override("font_size", 48)
	x_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	x_label.position = pos - Vector2(24, 30)
	x_label.z_index = 101
	add_child(x_label)

	var x_tween = create_tween()
	x_tween.tween_property(x_label, "position:y", x_label.position.y - 40, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	x_tween.parallel().tween_property(x_label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	x_tween.tween_callback(x_label.queue_free)

func show_life_lost_animation(pos: Vector2) -> void:
	# Crear corazón roto que flota hacia arriba
	var heart = Label.new()
	heart.text = "💔"
	heart.add_theme_font_size_override("font_size", 64)
	heart.position = pos + Vector2(-32, -80)  # Arriba del cliente
	heart.z_index = 150
	add_child(heart)

	# Animación: flota hacia arriba y desaparece
	var heart_tween = create_tween()
	heart_tween.set_parallel(true)
	heart_tween.tween_property(heart, "position:y", heart.position.y - 120, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	heart_tween.tween_property(heart, "modulate:a", 0.0, 1.2).set_delay(0.3)
	heart_tween.tween_property(heart, "scale", Vector2(1.5, 1.5), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	heart_tween.set_parallel(false)
	heart_tween.tween_callback(heart.queue_free)

	# Partículas de corazón roto
	for i in range(8):
		var shard = Label.new()
		shard.text = "💔"
		shard.add_theme_font_size_override("font_size", 24)
		shard.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 0.8))
		shard.position = pos + Vector2(-12, -60)
		shard.z_index = 149
		add_child(shard)

		var angle = (TAU / 8) * i + randf_range(-0.3, 0.3)
		var distance = randf_range(40, 80)
		var target_pos = shard.position + Vector2(cos(angle), sin(angle)) * distance

		var shard_tween = create_tween()
		shard_tween.set_parallel(true)
		shard_tween.tween_property(shard, "position", target_pos, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		shard_tween.tween_property(shard, "rotation", randf_range(-PI, PI), 0.8)
		shard_tween.tween_property(shard, "modulate:a", 0.0, 0.8).set_delay(0.2)
		shard_tween.tween_property(shard, "scale", Vector2(0.5, 0.5), 0.8)
		shard_tween.set_parallel(false)
		shard_tween.tween_callback(shard.queue_free)

	# Texto "-1 VIDA" flotante
	var text = Label.new()
	text.text = "-1 VIDA"
	text.add_theme_font_size_override("font_size", 28)
	text.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	text.add_theme_constant_override("shadow_offset_x", 3)
	text.add_theme_constant_override("shadow_offset_y", 3)
	text.position = pos + Vector2(-60, -40)
	text.z_index = 151
	add_child(text)

	var text_tween = create_tween()
	text_tween.set_parallel(true)
	text_tween.tween_property(text, "position:y", text.position.y - 80, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	text_tween.tween_property(text, "modulate:a", 0.0, 1.0).set_delay(0.4)
	text_tween.set_parallel(false)
	text_tween.tween_callback(text.queue_free)

func create_celebration_effect(pos: Vector2) -> void:
	# Estrellas y particulas de celebracion (estilo Club Penguin)
	var colors = [
		Color(1, 0.85, 0.2),   # Dorado
		Color(1, 0.5, 0.2),    # Naranja
		Color(0.2, 0.8, 0.4),  # Verde
		Color(0.4, 0.7, 1),    # Azul claro
	]

	if colors.size() == 0:
		return

	# Crear estrellas
	for i in range(8):
		var star = Label.new()
		star.text = "*"
		star.add_theme_font_size_override("font_size", randi_range(24, 40))
		star.add_theme_color_override("font_color", colors[i % colors.size()])
		star.position = pos
		star.z_index = 150
		add_child(star)

		var angle = (TAU / 8) * i + randf_range(-0.2, 0.2)
		var distance = randf_range(80, 150)
		var target_pos_star = pos + Vector2(cos(angle), sin(angle)) * distance

		var s_tween = create_tween()
		s_tween.set_parallel(true)
		s_tween.tween_property(star, "position", target_pos_star, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		s_tween.tween_property(star, "rotation", randf_range(-PI, PI), 0.6)
		s_tween.tween_property(star, "modulate:a", 0.0, 0.6).set_delay(0.3)
		s_tween.set_parallel(false)
		s_tween.tween_callback(star.queue_free)

	# Circulos de celebracion
	for i in range(12):
		var circle = ColorRect.new()
		circle.size = Vector2(randf_range(6, 14), randf_range(6, 14))
		circle.color = colors[i % colors.size()]
		circle.position = pos
		circle.z_index = 149
		add_child(circle)

		var angle = randf() * TAU
		var distance = randf_range(60, 120)
		var target_pos_circle = pos + Vector2(cos(angle), sin(angle)) * distance
		var up_offset = Vector2(0, randf_range(-50, -100))

		var c_tween = create_tween()
		c_tween.set_parallel(true)
		c_tween.tween_property(circle, "position", target_pos_circle + up_offset, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		c_tween.tween_property(circle, "modulate:a", 0.0, 0.8).set_delay(0.2)
		c_tween.set_parallel(false)
		c_tween.tween_callback(circle.queue_free)
