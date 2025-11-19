extends Node2D

@onready var detector: Area2D = $IngredientArea


var margin: float = 60.0 


var base_scale: Vector2 

var bounce_tween: Tween 

func _ready() -> void:
	detector.area_entered.connect(_on_area_entered)
	
	
	base_scale = scale 

func _process(delta: float) -> void:
	var mouse_pos = get_global_mouse_position()
	var parent_container = get_parent()
	
	var limit_min = 0.0
	var limit_max = 1152.0 
	
	if parent_container is Control:
		limit_min = parent_container.global_position.x + margin
		limit_max = parent_container.global_position.x + parent_container.size.x - margin
	
	global_position.x = clamp(mouse_pos.x, limit_min, limit_max)

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("ingredients"):
		var ing_id = area.get_meta("id")
		collect_ingredient(ing_id)
		area.queue_free()

func collect_ingredient(ing_id):
	GlobalManager.collected_ingredients.append(ing_id)
	AudioManager.play_collect_ingredient_sfx()
	
	
	if bounce_tween and bounce_tween.is_valid():
		bounce_tween.kill()
		scale = base_scale 
	
	bounce_tween = create_tween()
	

	bounce_tween.tween_property(self, "scale", base_scale * Vector2(1.15, 0.85), 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		
	
	bounce_tween.tween_property(self, "scale", base_scale, 0.08) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	


	var overlay = get_tree().get_first_node_in_group("minigame_overlay")
	if overlay and overlay.has_method("check_prepare_button"):
		overlay.check_prepare_button()
