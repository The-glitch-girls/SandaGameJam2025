# customer.gd
extends Node2D

signal arrived_at_center(customer : Node2D)
signal listen_customer_pressed
	
@onready var sprite : Sprite2D = $Sprite2D
@onready var btn_listen : TextureButton = $BtnListen
@onready var sfx_entering : AudioStreamPlayer = $SFXEntering
@export var speed: float = 300.0

const BASE_VIEWPORT = Vector2(1152, 648)
const BASE_START_X = -200
const BASE_OFFSET_Y = 80
const BASE_OFFSET_X = 100
const SPRITE_POSITION_Y = 414
const SPRITE_POSITION_X = 1152.0/2.0 + -80

var target_y_ratio := 0.05
var relative_x: float = 0.5
var customer_scale: float = 0.165 #escala de referencia
var character_id: String
var mood_id: String
var texts: Dictionary
var language: String

var state = GlobalManager.State.ENTERING

# Animaciones de espera
var idle_tween: Tween = null
var mood_timer: Timer = null
var wait_time: float = 0.0
var current_patience_level: int = 0  # 0=feliz, 1=neutral, 2=impaciente, 3=molesto
const PATIENCE_THRESHOLDS = [8.0, 16.0, 24.0]  # Segundos para cada nivel de impaciencia

func _ready():
	pass

func _process(delta: float) -> void:
	# Actualizar tiempo de espera solo cuando el cliente esta sentado
	if state == GlobalManager.State.SEATED:
		wait_time += delta
		update_patience_expression()
	
# Setup: Preparar, reinicializar data del cliente
func setup(data: Dictionary, lang: String):
	await ready
	character_id = data["character_id"]
	mood_id = data["mood_id"]
	texts = data["texts"]
	language = lang
	# Buscar el botón de forma segura (sin depender de @onready aún)
	btn_listen.visible = false

# Desde CafeLevel1 se llama a:
func move_to(target_position: Vector2) -> void:
	sfx_entering.play()
	
	var dist := (target_position - position).length()
	var tween = get_tree().create_tween()
	tween.tween_property(self, "position", target_position, dist / speed)
	
	# Cuando termine el tween (cliente en el centro) → emitir señal
	tween.finished.connect(customer_positioned)

func customer_positioned():
	sfx_entering.stop()
	set_state(GlobalManager.State.SEATED)

	var label = btn_listen.get_node("Label")
	label.text = GlobalManager.btn_listen_customer_label
	btn_listen.visible = true

	# Iniciar animacion de espera
	start_idle_animation()
	wait_time = 0.0

	emit_signal("arrived_at_center", self)

func set_state(new_state: GlobalManager.State):
	state = new_state
	match state:
		GlobalManager.State.ENTERING:
			var path := "res://assets/sprites/customers/%s_entering.png" % character_id
			var alt_path := "res://assets/sprites/customers/adalovelace_entering.png"
			load_customer_texture(path, alt_path)
		GlobalManager.State.SEATED:
			var path := "res://assets/sprites/customers/%s_%s.png" % [character_id, mood_id]
			var alt_path := "res://assets/sprites/customers/adalovelace_sleepy.png"
			load_customer_texture(path, alt_path)
		GlobalManager.State.FAIL:
			var path := "res://assets/sprites/customers/%s_%s_fail.png" % [character_id, mood_id]
			var alt_path := "res://assets/sprites/customers/%s_%s.png" % [character_id, mood_id]
			load_customer_texture(path, alt_path)
		GlobalManager.State.SUCCESS:
			var path := "res://assets/sprites/customers/%s_happy.png" % character_id
			var alt_path := "res://assets/sprites/customers/adalovelace_happy.png"
			load_customer_texture(path, alt_path)

	if sprite.texture:
		position_listen_button()

# Colocar el botón justo arriba del sprite
func position_listen_button():
	if sprite and sprite.texture:
		var texture_size = get_sprite_size()
		var btn_size = btn_listen.size
		
		# centrar en X, arriba en Y
		var x = -btn_size.x / 2
		var y = -texture_size.y/2 - btn_size.y - 10
		
		btn_listen.position = Vector2(x, y)

#Cargar sprite y aplicar escala.
func get_sprite_size() -> Vector2:
	if sprite.texture:
		return sprite.texture.get_size() * sprite.scale
	return Vector2.ZERO

func get_initial_position() -> Vector2:
	return Vector2(BASE_START_X, SPRITE_POSITION_Y)

func get_target_position() -> Vector2:
	return Vector2(SPRITE_POSITION_X, SPRITE_POSITION_Y)
	
# Cambios de estados:
func react_angry():
	reset_waiting_state()
	AudioManager.play_customer_sfx(GlobalManager.current_customer.genre, GlobalManager.current_customer.mood_id, true)
	set_state(GlobalManager.State.FAIL)
	GlobalManager.return_customer()

func react_happy():
	reset_waiting_state()
	AudioManager.play_customer_sfx(GlobalManager.current_customer.genre, "happy", true)
	set_state(GlobalManager.State.SUCCESS)
	GlobalManager.mark_customer_as_satisfied()
	
func _on_btn_listen_pressed() -> void:
	AudioManager.play_click_sfx()
	if GlobalManager.current_customer.is_empty():
		print("⚠️ No hay cliente actual")
		return
		
	AudioManager.play_customer_sfx(GlobalManager.current_customer.genre, GlobalManager.current_customer.mood_id)
	emit_signal("listen_customer_pressed")

# Helper
func load_customer_texture(path: String, alt_path: String):
	var tex : Texture2D = null
			
	if ResourceLoader.exists(path, "Texture2D"):
		tex = load(path)
	else:
		tex = load(alt_path)
		
	sprite.texture = tex
	
func hide_listen_button():
	btn_listen.visible = false

# ============ ANIMACIONES DE ESPERA ============

func start_idle_animation() -> void:
	if idle_tween and idle_tween.is_running():
		return

	idle_tween = create_tween().set_loops()
	var original_y = sprite.position.y

	# Animacion de respiracion sutil (movimiento vertical)
	idle_tween.tween_property(sprite, "position:y", original_y - 3, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	idle_tween.tween_property(sprite, "position:y", original_y + 2, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func stop_idle_animation() -> void:
	if idle_tween and idle_tween.is_running():
		idle_tween.kill()
		idle_tween = null
	sprite.position.y = 0

func update_patience_expression() -> void:
	var new_level = 0

	for i in range(PATIENCE_THRESHOLDS.size()):
		if wait_time >= PATIENCE_THRESHOLDS[i]:
			new_level = i + 1

	# Solo actualizar si cambio el nivel de paciencia
	if new_level != current_patience_level:
		current_patience_level = new_level
		apply_patience_visual()

func apply_patience_visual() -> void:
	# Aplicar efectos visuales segun nivel de paciencia
	match current_patience_level:
		0:  # Feliz - normal
			sprite.modulate = Color(1, 1, 1)
		1:  # Neutral - ligeramente desaturado
			sprite.modulate = Color(0.95, 0.95, 0.9)
			show_impatience_indicator("...")
		2:  # Impaciente - mas desaturado, leve sacudida
			sprite.modulate = Color(0.9, 0.85, 0.8)
			show_impatience_indicator("?")
			shake_customer()
		3:  # Molesto - tinte rojizo, sacudida mas fuerte
			sprite.modulate = Color(1.0, 0.8, 0.75)
			show_impatience_indicator("!")
			shake_customer()

func show_impatience_indicator(symbol: String) -> void:
	# Crear indicador temporal sobre el cliente
	var indicator = Label.new()
	indicator.text = symbol
	indicator.add_theme_font_size_override("font_size", 28)
	indicator.add_theme_color_override("font_color", Color(0.8, 0.3, 0.2))
	indicator.position = Vector2(20, -get_sprite_size().y / 2 - 40)
	indicator.z_index = 100
	add_child(indicator)

	# Animacion de aparicion
	indicator.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(indicator, "modulate:a", 1.0, 0.2)
	tween.tween_property(indicator, "position:y", indicator.position.y - 15, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.5)
	tween.tween_property(indicator, "modulate:a", 0.0, 0.3)
	tween.tween_callback(indicator.queue_free)

func shake_customer() -> void:
	var original_x = sprite.position.x
	var tween = create_tween()
	tween.tween_property(sprite, "position:x", original_x + 5, 0.05)
	tween.tween_property(sprite, "position:x", original_x - 5, 0.1)
	tween.tween_property(sprite, "position:x", original_x + 3, 0.1)
	tween.tween_property(sprite, "position:x", original_x, 0.05)

func reset_waiting_state() -> void:
	wait_time = 0.0
	current_patience_level = 0
	sprite.modulate = Color(1, 1, 1)
	stop_idle_animation()

# Obtener factor uniforme para la escala
func get_scale_factor():
	var viewport_size: Vector2 = get_viewport().size
	var scale_factor = min(viewport_size.x / BASE_VIEWPORT.x, viewport_size.y / BASE_VIEWPORT.y)
	
	return scale_factor
