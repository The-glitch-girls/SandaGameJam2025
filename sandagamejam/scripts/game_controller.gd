#GameController.tscn maneja Newton, los niveles y el minigame overlay.
extends Node

signal ingredients_minigame_started
signal ingredients_minigame_timeout
signal ingredients_minigame_finished

@onready var current_scene_container: Node2D = $CurrentSceneContainer
@onready var minigame_overlay = $MiniGameOverlay
@onready var newton_layer = $NewtonLayer
@onready var newton_ready_sprite: Sprite2D = $NewtonLayer/NewtonReadySprite
@onready var newton_moods_sprite: Sprite2D = $NewtonLayer/NewtonMoodsSprite
@onready var correct_recipe_sprite: Sprite2D = $NewtonLayer/CorrectRecipeSprite
@onready var wrong_recipe_sprite: Sprite2D = $NewtonLayer/WrongRecipeSprite
@onready var gravitational_recipe_sprite: Sprite2D = $NewtonLayer/GravitationalRecipeSprite
@onready var feedback_message: RichTextLabel = $NewtonLayer/FeedbackMessage
@onready var outcome_message: RichTextLabel = $NewtonLayer/OutcomeMessage
@onready var continue_button: TextureButton = $NewtonLayer/ContinueBtn
@onready var overlay_layer = $OverlayLayer
var final_screen: Node = null

const IS_TESTING = false
const SCREEN_WIDTH = 1152.0
const SECONDS_TO_LOSE = 30
const SECONDS_TO_LOSE_NOT_PREPARED = 42
const SECONDS_TO_GAIN = 15
var LIVES = 1 if IS_TESTING else 4
var MAX_LIVES = 2 if IS_TESTING else 4
var ING_ARR_SIZE = 20 #Debe disminuir si el nivel aumenta
var TIME_LEFT = 180.0
var global_ranking: Array = []

var is_success: bool = false
var current_level: Node = null
var current_minigame: Node = null
var newton_original_scale: Vector2 = Vector2(0.22, 0.22)
var newton_original_pos: Vector2 = Vector2(978.0, 472)
var pending_final_state : Variant = null

# Diccionario de equivalencias normales → gravitacionales
var gravitational_equivalents = {
	"ing_002": ["ing_202"],  # Apple → Falling Apple
	"ing_005": ["ing_205"],  # Sugar → Gravity Sugar
	"ing_007": ["ing_207"]   # Honey → Sticky Fall Honey
}

func _ready():
	newton_layer.visible = false
	newton_ready_sprite.visible = false
	GlobalManager.connect("time_up", Callable(self, "_on_time_up"))
	GlobalManager.connect("game_over", Callable(self, "_on_game_over"))
	GlobalManager.connect("win", Callable(self, "_on_win"))

func show_newton_layer():
	newton_layer.visible = true
	newton_ready_sprite.visible = false
# Cargar Main Menu: Jugar, Opciones, Creditos
func load_main_menu():
	# Limpiar cualquier escena previa
	free_children(current_scene_container)
	
	# Instanciar MainMenu
	var main_menu = load("res://scenes/menus/MainMenu.tscn").instantiate()
	current_scene_container.add_child(main_menu)
	
	# Ajustar tamaño y posición si es Control
	if main_menu is Control:
		main_menu.position = Vector2.ZERO

		newton_layer.visible = false
		pass
	
# Cargar cualquier nivel
func load_level(level_path: String) -> void:
	if current_level and is_instance_valid(current_level):
		current_level.queue_free()
		current_level = null
	
	var scene = load(level_path)
	if not scene:
		push_error("No se encontró la escena: " + level_path)
		return
	
	current_level = scene.instantiate()
	current_scene_container.add_child(current_level)
	
	# conectar el final del nivel
	if current_level.has_signal("level_cleared"):
		current_level.connect("level_cleared", Callable(self, "_on_level_cleared"))

func show_minigame(path: String):
	var new_scale = 0.15
	var new_scale_vector = Vector2(new_scale, new_scale)
	
	slide_minigame_overlay(path)
	slide_current_level("left")
	resize_newton_ready(new_scale_vector)
	GlobalManager.is_minigame_overlay_visible = true
		
func finish_minigame():
	emit_signal("ingredients_minigame_finished")
	slide_current_level("right")
	reset_newton_ready()
	
	# Si existe minigame_instance guardado, animar antes de eliminarlo
	if self.current_minigame and is_instance_valid(self.current_minigame):
		var tween = create_tween()
		tween.tween_property(self.current_minigame, "modulate:a", 0.0, 0.5)
		tween.finished.connect(_on_minigame_hidden)
	else:
		_cleanup_minigames()
	
	# Invertir colores del timer cuando cierre el minijuego
	var ui_layer = get_tree().get_first_node_in_group("UILayer")
	if ui_layer:
		ui_layer.revert_label_colors_from_minigame()
		
func free_children(parent: Node):
	for child in parent.get_children():
		child.queue_free()

# Slide Minigame Overlay
func slide_minigame_overlay(path: String):
	const TARGET_X = SCREEN_WIDTH - 700
	
	var tween = create_tween()
	
	var minigame_instance = load(path).instantiate()
	minigame_overlay.add_child(minigame_instance)
	minigame_instance.scale = Vector2(1,1)
	minigame_instance.z_index = 50
	

	if minigame_instance.has_signal("ingredients_minigame_started"):
		minigame_instance.connect("ingredients_minigame_started", Callable(self, "_on_overlay_minigame_started"))
		
	if minigame_instance.has_signal("ingredients_minigame_timeout"):
		minigame_instance.connect("ingredients_minigame_timeout", Callable(self, "_on_overlay_minigame_timeout"))

	self.current_minigame = minigame_instance
	
	# Conectar la señal con el nivel actual
	if current_level and current_level.has_method("_on_ingredients_minigame_started"):
		minigame_instance.ingredients_minigame_started.connect(
			Callable(current_level, "_on_ingredients_minigame_started")
		)
	
	# Posición inicial: fuera de la pantalla (derecha)
	minigame_instance.position = Vector2(SCREEN_WIDTH, 0)
	# Posición final: borde izquierdo del Node2D en la mitad de la pantalla
	var target_pos = Vector2(TARGET_X, 0)
	# Tween para entrada del overlay
	tween.tween_property(minigame_instance, "position", target_pos, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


# Slide Level scene
func slide_current_level(direction: String = "left", duration: float = 0.5):
	var tween = create_tween()

	var start_scene_pos = current_scene_container.position
	var offset = Vector2(SCREEN_WIDTH/4, 0)
	var target_scene_pos
	if direction == "left":
		target_scene_pos = start_scene_pos - offset
	elif direction == "right":
		target_scene_pos = start_scene_pos + offset
	else:
		push_warning("Dirección inválida: " + direction)
		return
	
	tween.tween_property(current_scene_container, "position", target_scene_pos, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Empezar a cocinar
# print("🧑🏽‍🍳 Newton esta cocinando")
func make_newton_cook():	
	newton_ready_sprite.visible = false
	newton_moods_sprite.visible = true
	AudioManager.play_whisking_sfx()
	
	# Hacer flip horizontal repetidamente
	var flip_timer := Timer.new()
	flip_timer.wait_time = 0.2 # cada 0.2 segundos cambia de lado
	flip_timer.autostart = true
	flip_timer.one_shot = false
	add_child(flip_timer)

	flip_timer.timeout.connect(func():
		newton_moods_sprite.flip_h = !newton_moods_sprite.flip_h
	)
	
	# Detener animación después de 2 segundos
	var tween := get_tree().create_timer(2.0)
	tween.timeout.connect(func():
		flip_timer.stop()
		flip_timer.queue_free()
		AudioManager.stop_whisking_sfx()
		# Obtener los resultados
		var result = check_recipe()
		# Mostrar mensajes inmediatos
		feedback_message.text = result["feedback"]
		outcome_message.text = result["outcome"]
		await show_recipe_result_with_delay(result)
		show_netown_feedback()
	)

func show_netown_feedback():
	var continue_btn_label = continue_button.get_node("Label")
	outcome_message.visible = true
	newton_ready_sprite.visible = false
	newton_moods_sprite.visible = true
	
	# Cambiar sprite según resultado
	if is_success:
		AudioManager.play_correct_recipe_sfx()
		newton_moods_sprite.texture = preload("res://assets/sprites/newtown/newton_happy.png")
	else:
		AudioManager.play_wrong_recipe_sfx()
		newton_moods_sprite.texture = preload("res://assets/sprites/newtown/newton_sad.png")
	
	continue_btn_label.text = GlobalManager.btn_continuar_label
	continue_button.visible = true

func hide_continue_btn():
	continue_button.visible = false

func check_recipe() -> Dictionary:
	var selected_recipe_ingredients = GlobalManager.selected_recipe_data["ingredients"]
	var selected_recipe_mood = GlobalManager.selected_recipe_data["mood"]
	var collected_ingredients = GlobalManager.collected_ingredients
	var customer_mood = GlobalManager.current_customer["mood_id"]

	# Selecciono receta correcta?
	var correct_recipe_selected = true if selected_recipe_mood == customer_mood else false
	# Recolectó todos los ingredientes?
	var is_exact_match = arrays_match_with_gravity(collected_ingredients, selected_recipe_ingredients)
	is_success = correct_recipe_selected and is_exact_match
	var gravitational = is_gravitational(collected_ingredients, selected_recipe_ingredients)

	# Determinar respuesta y reglas
	var sprite_id = GlobalManager.selected_recipe_data["id"]
	var response_type
	var sprite_to_show : Sprite2D
	
	if not GlobalManager.recipe_started:
		response_type = GlobalManager.ResponseType.RECIPE_NOT_PREPARED
	elif not correct_recipe_selected:
		wrong_recipe_sprite.texture = load("res://assets/pastry/recipes/%s_wrong.png" % sprite_id)
		sprite_to_show = wrong_recipe_sprite
		response_type = GlobalManager.ResponseType.RECIPE_WRONG
	elif not is_exact_match:
		wrong_recipe_sprite.texture = load("res://assets/pastry/recipes/%s_wrong.png" % sprite_id)
		sprite_to_show = wrong_recipe_sprite
		response_type = GlobalManager.ResponseType.INGREDIENTS_WRONG
	elif is_success:
		if gravitational:
			gravitational_recipe_sprite.texture = load("res://assets/pastry/recipes/%s_gravitational.png" % sprite_id)
			sprite_to_show = gravitational_recipe_sprite
			response_type = GlobalManager.ResponseType.GRAVITATIONAL
		else:
			correct_recipe_sprite.texture = load("res://assets/pastry/recipes/%s_correct.png" % sprite_id)
			sprite_to_show = correct_recipe_sprite
			response_type = GlobalManager.ResponseType.RECIPE_CORRECT
	
	var result = GlobalManager.get_response_texts(response_type)
	
	return {
		"type": response_type,
		"sprite": sprite_to_show,
		"feedback": result[0],
		"outcome": result[1]
	}

func show_recipe_result_with_delay(result: Dictionary) -> void:	
	AudioManager.play_recipe_ready_sfx()
	await apply_recipe_result(result, true, true)
	show_netown_feedback()

func reset_newton_ready() -> void:
	# Restaurar Newton
	newton_moods_sprite.texture = preload("res://assets/sprites/newtown/newton_cooking.png")
	newton_ready_sprite.visible = false
	newton_moods_sprite.visible = false
	
	var tween = create_tween()
	tween.tween_property(newton_ready_sprite, "position", newton_original_pos, 0.5)
	tween.tween_property(newton_ready_sprite, "scale", newton_original_scale, 0.5)
	
func resize_newton_ready(new_scale_vector: Vector2) -> void:
	var tween = create_tween()
	
	# Escalar con animación
	tween.tween_property(newton_ready_sprite, "scale", new_scale_vector, 0.5)
	
	# Mover con animación (20px más abajo/derecha de su posición actual)
	#var new_pos = newton_ready_sprite.position + Vector2(84,100)
	#tween.tween_property(newton_ready_sprite, "position", new_pos, 0.5)

func arrays_match_with_gravity(collected: Array, recipe: Array) -> bool:	
	for recipe_id in recipe: #["ing_001", "ing_002", "ing_005", "ing_003"]
		# IDs válidos = ingrediente normal + versiones gravitacionales
		var valid_ids = [recipe_id] #gravitational_equivalents[recipe_id] if gravitational_equivalents.has(recipe_id) else [recipe_id]
		if gravitational_equivalents.has(recipe_id):
			valid_ids += gravitational_equivalents[recipe_id]
		# Verificar si al menos uno está en collected
		var matched = false
		for id in valid_ids:
			if collected.has(id):
				matched = true
				break
		if not matched:
			return false
	return true

# Detectar si la receta contiene algún ingrediente gravitacional
func is_gravitational(collected: Array, recipe: Array) -> bool:
	for recipe_id in recipe:
		if gravitational_equivalents.has(recipe_id):
			for grav_id in gravitational_equivalents[recipe_id]:
				if collected.has(grav_id):
					return true
	return false

# Función común para mostrar resultados y aplicar consecuencias
func apply_recipe_result(result: Dictionary, show_sprite: bool = false, delayed: bool = false) -> void:
	#print("result..", result)
	var msg: String = result["feedback"]
	var response_type: int = result["type"]
	var sprite: Sprite2D = result.get("sprite", null)

	# Mostrar feedback
	newton_moods_sprite.visible = false
	feedback_message.visible = true
	feedback_message.text = msg
	outcome_message.text = result["outcome"]

	if show_sprite and sprite:
		sprite.visible = true
		sprite.scale = Vector2(0.2, 0.2)

		# Animación "pop"
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2(1, 1), 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Si es con delay → esperar antes de aplicar consecuencias
	if delayed:
		var timer := get_tree().create_timer(1.5)
		await timer.timeout

	# Aplicar consecuencias
	match response_type:
		GlobalManager.ResponseType.RECIPE_WRONG:
			GlobalManager.lose_life()
		GlobalManager.ResponseType.RECIPE_NOT_PREPARED:
			GlobalManager.apply_penalty(SECONDS_TO_LOSE_NOT_PREPARED)
		GlobalManager.ResponseType.INGREDIENTS_WRONG:
			GlobalManager.apply_penalty(SECONDS_TO_LOSE)
		GlobalManager.ResponseType.RECIPE_CORRECT:
			GlobalManager.apply_penalty(-SECONDS_TO_GAIN)
		GlobalManager.ResponseType.GRAVITATIONAL:
			GlobalManager.gain_life()
		_:
			print(">> response_type no coincide con ninguna opción:", response_type)

	# Ocultar sprite al final si lo hubo
	if show_sprite and sprite:
		sprite.visible = false

# Controles

func reset_game():
	print("reseteando nivel...")
	# Reset de variables globales (vidas, tiempo, arrays…)
	GlobalManager.reset()
	
	# Cargar nivel inicial
	load_level("res://scenes/levels/PastryLevel1.tscn")
	
	# Reset de UI
	UILayerManager.init_ui_layer()
	UILayerManager.show_hud()
	
	if UILayerManager.ui_layer_instance:
		UILayerManager.ui_layer_instance.reset_timer_colors()
	
	# Reset mensajes globales
	if feedback_message:
		feedback_message.text = ""
	if outcome_message:
		outcome_message.text = ""
	
# Senales
func _on_ingredients_minigame_timeout():
	# Obtener los resultados
	var result = check_recipe()
	
	# Forzar feedback negativo si no presionaron preparar
	is_success = false
	await apply_recipe_result(result, false, false)
	show_netown_feedback()

func _on_minigame_hidden():
	if self.current_minigame and is_instance_valid(self.current_minigame):
		self.current_minigame.queue_free()
		self.current_minigame = null
	
	_cleanup_minigames()
	
func _on_continue_btn_pressed() -> void:
	feedback_message.visible = false
	outcome_message.visible = false
	hide_continue_btn()
	
	# Restaurar Newton
	reset_newton_ready()
	# Ocultar minijuegos
	finish_minigame()
	# Avisar al nivel que muestre reacción del cliente
	get_tree().call_group("levels", "show_customer_reaction", is_success)
	
	if pending_final_state != null:
		_go_to_final_screen()

func _cleanup_minigames():
	# Liberar lo que esté dentro del overlay
	for child in minigame_overlay.get_children():
		child.queue_free()
	
	# Resetear flags globales
	GlobalManager.is_minigame_overlay_visible = false
	# Resetear también ingredientes recolectados, recetas, etc.
	GlobalManager.collected_ingredients.clear()
	GlobalManager.selected_recipe_idx = -1

func _on_level_cleared():
	print(">>>> Nivel completado desde GameController")
	GlobalManager.check_win_condition()

func _on_win():
	_prepare_final(GlobalManager.GameState.WIN)
	#load_final_screen(GlobalManager.GameState.WIN)
	
func _on_time_up():
	_prepare_final(GlobalManager.GameState.TIMEUP)
	#load_final_screen(GlobalManager.GameState.TIMEUP)

func _on_game_over():
	_prepare_final(GlobalManager.GameState.GAMEOVER)
	#load_final_screen(GlobalManager.GameState.GAMEOVER)

func _on_overlay_minigame_started():
	emit_signal("ingredients_minigame_started")

func _on_overlay_minigame_timeout():
	emit_signal("ingredients_minigame_timeout")
	_on_ingredients_minigame_timeout() # sigue llamando tu lógica actual

func _prepare_final(state: GlobalManager.GameState):
	print("preparing... ", state )
	pending_final_state = state
	
	# Mostrar feedback (si el overlay está visible)
	if GlobalManager.is_minigame_overlay_visible:
	#	is_success = (state == GlobalManager.GameState.WIN)
		show_netown_feedback()
	else:
		_go_to_final_screen()

func _go_to_final_screen():
	load_final_screen(pending_final_state)
	pending_final_state = null
	
func load_final_screen(state: GlobalManager.GameState):
	# 1 Ocultar Newton, no eliminar el minijuego aun
	newton_layer.visible = false
	#if current_minigame and is_instance_valid(current_minigame):
	#	current_minigame.visible = false
	
	# 2️ Limpiar pantalla final previa
	if final_screen and is_instance_valid(final_screen):
		final_screen.queue_free()
		
	# 3️ Instanciar pantalla final
	final_screen = load("res://scenes/ui/FinalScreen.tscn").instantiate()
	overlay_layer.add_child(final_screen)
	
	# 4 Fade in
	final_screen.modulate = Color(1,1,1,0)
	var tween = create_tween()
	tween.tween_property(final_screen, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	
	# 5 Mostrar la pantalla según el estado ("win", "time_up", "game_over")
	final_screen.show_final_screen(state)
	
	# 6 Limpiar minijuegos y resetear Newton **después** de fade-in
	tween.finished.connect(func():
		print("TWEEN FINISHED")
		#_cleanup_minigames()
		#hide_continue_btn()
		
		# Restaurar Newton
		#reset_newton_ready()
		# Ocultar minijuegos
		#finish_minigame()
	
	)
