extends Control

@onready var btn_jugar : Area2D = $Jugar
@onready var btn_creditos : Area2D = $Creditos
@onready var btn_opciones : Area2D = $Opciones
@onready var btn_salir : TextureButton = $Salir


var cursor_hand: Texture2D
var cursor_normal: Texture2D
var hovered_btn: Area2D = null

func _ready():
	set_button_labels()
	
	# Forzar mouse filter en toda la escena para exportación
	$Fondo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# El Control raíz DEBE ser Stop para recibir input
	self.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Salir forzar que reciba input
	btn_salir.mouse_filter = Control.MOUSE_FILTER_STOP
	btn_salir.disabled = false
	
	cursor_hand = load("res://assets/UI/hand_point.png") if ResourceLoader.exists("res://assets/ui/hand_point.png") else null
	Input.set_custom_mouse_cursor(cursor_hand, Input.CURSOR_ARROW, Vector2(16, 16))
	
	if GlobalManager.has_signal("language_changed"):
		GlobalManager.language_changed.connect(_on_language_changed)

		
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("CLICK DETECTADO en: ", get_global_mouse_position())
		print("btn_salir rect: ", btn_salir.get_global_rect())
	var mouse_pos = get_global_mouse_position()
	
	# Detectar hover
	var btn_hover = _get_btn_at(mouse_pos)
	if btn_hover != hovered_btn:
		hovered_btn = btn_hover
		if hovered_btn:
			Input.set_custom_mouse_cursor(cursor_hand, Input.CURSOR_ARROW, Vector2(16, 16))
		else:
			Input.set_custom_mouse_cursor(cursor_hand, Input.CURSOR_ARROW, Vector2(16, 16))
	
	# Detectar click
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if hovered_btn == btn_jugar:
			AudioManager.play_click_sfx()
			GameController.free_children(GameController.current_scene_container)
			GameController.load_level("res://scenes/menus/intro.tscn")
		elif hovered_btn == btn_creditos:
			AudioManager.play_click_sfx()
			var credits_modal = preload("res://scenes/menus/Credits.tscn").instantiate()
			add_child(credits_modal)
		elif hovered_btn == btn_opciones:
			AudioManager.play_click_sfx()
			var opciones_modal = preload("res://scenes/OpcionesModal.tscn").instantiate()
			add_child(opciones_modal)

func _get_btn_at(mouse_pos: Vector2) -> Area2D:
	for btn in [btn_jugar, btn_opciones, btn_creditos]:
		var polygon_node = btn.get_node("CollisionPolygon2D")
		if polygon_node == null:
			continue
		
		# Convertir polígono a coordenadas globales
		var global_polygon = PackedVector2Array()
		for point in polygon_node.polygon:
			global_polygon.append(btn.global_position + polygon_node.position + point)
		
		if Geometry2D.is_point_in_polygon(mouse_pos, global_polygon):
			return btn
	
	return null

# --------------------
# LABELS
# --------------------
func set_button_labels() -> void:
	var file := FileAccess.open("res://i18n/menu_labels.json", FileAccess.READ)
	if file:
		var json_text := file.get_as_text()
		file.close()
		var data = JSON.parse_string(json_text)
		if data == null:
			push_error("Error al parsear el JSON de menu labels.")
			return
		var lang : String = GlobalManager.game_language
		if data.has(lang):
			var labels = data[lang]
			btn_jugar.get_node("CollisionPolygon2D/Label").text = labels["jugar"]
			btn_opciones.get_node("CollisionPolygon2D/Label").text = labels["opciones"]
			btn_creditos.get_node("CollisionPolygon2D/Label").text = labels["creditos"]
		else:
			push_error("Idioma no encontrado en JSON: " + lang)
	else:
		push_error("No se pudo abrir el archivo JSON.")

func _on_language_changed() -> void:
	set_button_labels()

func _on_salir_pressed():
	get_tree().quit()
