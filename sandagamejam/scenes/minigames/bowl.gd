extends Node2D

@onready var detector: Area2D = $IngredientArea
var min_x_global: float = 100.0
var max_x_global: float = 1050.0

func _ready() -> void:
	detector.area_entered.connect(_on_area_entered)

func _process(delta: float) -> void:

	var mouse_pos = get_global_mouse_position()
	

	global_position.x = clamp(mouse_pos.x, min_x_global, max_x_global)

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("ingredients"):
		var ing_id = area.get_meta("id")
		collect_ingredient(ing_id)
		area.queue_free()

func collect_ingredient(ing_id):
	GlobalManager.collected_ingredients.append(ing_id)
	AudioManager.play_collect_ingredient_sfx()

	var overlay = get_tree().get_first_node_in_group("minigame_overlay")
	if overlay and overlay.has_method("check_prepare_button"):
		overlay.check_prepare_button()
