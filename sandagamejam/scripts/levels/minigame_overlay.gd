
extends Node2D

signal ingredients_minigame_started
signal ingredients_minigame_timeout

@onready var menu_container : Control = $TextureRect/MenuContainer
@onready var recipe_container : Control = $TextureRect/RecipeContainer
@onready var recollect_container : Control = $TextureRect/RecollectContainer
@onready var btn_prepare : TextureButton = $TextureRect/BtnPrepareRecipe

var minigame_started := false
var active_tweens := []

func _ready():
	load_menu_data()
	load_btn_labels()

func hide_menu_container():
	menu_container.visible = false

func show_menu_container():
	load_menu_data()
	menu_container.visible = true

func hide_recipe_container():
	recipe_container.visible = false

func show_recipe_container():
	recipe_container.visible = true

func hide_recollect_container():
	recollect_container.visible = false

func show_recollect_container():
	recollect_container.visible = true

func fill_ingredients_textrect(instance: Node) -> void:
	if not instance:
		return

	var center = instance.get_node("TextureRect/CenterContainer")
	if not center:
		print("No se encontró el CenterContainer en IngredientsMenu")
		return

	for child in center.get_children():
		child.queue_free()

	var recipe = GlobalManager.current_level_recipes[GlobalManager.selected_recipe_idx]
	var ingredients = recipe["ingredients"]

	var grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center.add_child(grid)

	var column_gap = 25 

	for i in range(ingredients.size()):
		var ing_id = ingredients[i]
		var tex_path = "res://assets/pastry/ingredients/%s.png" % ing_id
		if not ResourceLoader.exists(tex_path):
			print("No existe asset:", tex_path)
			continue

		var tex = load(tex_path)
		var tex_rect = TextureRect.new()
		tex_rect.texture = tex
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.expand = true
		tex_rect.custom_minimum_size = Vector2(40, 40)

		var label = Label.new()
		label.text = "x1"

		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		hbox.add_child(tex_rect)

		var spacer = Control.new()
		spacer.custom_minimum_size = Vector2(4, 0)
		hbox.add_child(spacer)

		hbox.add_child(label)

		var wrapper = MarginContainer.new()
		wrapper.add_child(hbox)
		if i % 2 == 0:
			wrapper.add_theme_constant_override("margin_right", column_gap)

		grid.add_child(wrapper)

func show_ingredients_textrect() -> Node:
	var scene = preload("res://scenes/minigames/IngredientsMenu.tscn")
	var instance = scene.instantiate()
	
	var root = get_parent() # ubicado en pastry level.tscn
	if root:
		root.add_child(instance)
		instance.position = Vector2(100,45)
		instance.visible = true
		return instance
	else:
		print("No se encontró el nodo padre para agregar el TextRect")
		return null

func show_selected_recipe(idx: int) -> void:
	GlobalManager.selected_recipe_idx = idx
	load_selected_recipe_data(idx)
	load_ingredients_assets()
	hide_menu_container()
	show_recipe_container()

func load_menu_data() -> void:
	var recipe_buttons = [
		menu_container.get_node("Recipe1"),
		menu_container.get_node("Recipe2"),
		menu_container.get_node("Recipe3"),
		menu_container.get_node("Recipe4")
	]
	
	for i in range(GlobalManager.current_level_recipes.size()):
		var recipe_data = GlobalManager.current_level_recipes[i]
		var recipe_id = recipe_data["id"]
		var path = "res://assets/pastry/recipes/%s.png" % recipe_id
		if not ResourceLoader.exists(path):
			print("No existe asset:", path)
			continue
		
		var tex = load(path)
		if i < recipe_buttons.size():
			var button = recipe_buttons[i]
			var sprite = button.get_node("Sprite2D") 
			if sprite:
				sprite.texture = tex
		
func load_btn_labels() -> void:
	var continue_label = recipe_container.get_node("BtnContinue/Label")
	var back_label = recipe_container.get_node("BtnBack/Label")
	var cook_label = btn_prepare.get_node("Label")
	continue_label.text = GlobalManager.btn_choose_recipe_label
	back_label.text = GlobalManager.btn_reject_recipe_label
	cook_label.text = GlobalManager.btn_cook_recipe_label
	
func load_selected_recipe_data(idx: int) -> void:
	var lang = GlobalManager.game_language
	var recipe_selected = GlobalManager.current_level_recipes[idx]
	var rec_name = recipe_selected["name"][lang]
	
	var riddle = recipe_selected["riddle"][lang]
	var text = "[center][font_size=35]" + rec_name + "[/font_size][/center]\n\n"
	text += "[font_size=36] " + riddle + "[/font_size]"

	var rich_label_text = recipe_container.get_node("RichTextLabel")
	rich_label_text.bbcode_enabled = true
	rich_label_text.text = text
	
func load_ingredients_assets():
	var recipe_selected = GlobalManager.current_level_recipes[GlobalManager.selected_recipe_idx]
	var ingredients = recipe_selected["ingredients"]

	
	var ing_container = recipe_container.get_node("IngredientsContainer")
	clear_children(ing_container)

	for i in range(ingredients.size()):
		var ing_id = ingredients[i]
		var wrapper = create_ingredient_wrapper(ing_id)
		ing_container.add_child(wrapper)


func start_ingredient_minigame():
	print("START MINIGAME... ")
	emit_signal("ingredients_minigame_started")
	minigame_started = true
	var recipe_selected = GlobalManager.current_level_recipes[GlobalManager.selected_recipe_idx]
	GlobalManager.selected_recipe_data = recipe_selected
	
	var array_size = GlobalManager.ingredientes_array_size
	var ingredients = recipe_selected["ingredients"]
	var ingr_loop = generate_arr(ingredients, array_size)
	animate_ingredients(ingr_loop)
	btn_prepare.visible = true

func animate_ingredients(ingr_loop: Array) -> void:
	print("🥣 INICIO CAÍDA FÍSICA: ", ingr_loop)
	var container := recollect_container
	
	
	clear_children_except_bowl(container)

	
	var start_y := -100.0
	var end_y := container.size.y + 150.0
	var min_x := 50.0
	var max_x := container.size.x - 50.0
	var duration := 3.0
	var spawn_interval := 0.8

	for i in range(ingr_loop.size()):
		var ing_id = ingr_loop[i]
		
	
		var new_ing = create_ingredient_physics(ing_id)
		if not new_ing: continue
		
		container.add_child(new_ing)
		

		
		var random_x = randf_range(min_x, max_x)
		new_ing.position = Vector2(random_x, start_y)

	
		var tween := create_tween()
		tween.tween_property(new_ing, "position:y", end_y, duration) \
			.set_trans(Tween.TRANS_LINEAR) \
			.set_delay(spawn_interval * i)
			
		tween.tween_callback(Callable(new_ing, "queue_free"))
		active_tweens.append(tween)
	
		
		if i == ingr_loop.size() - 1:
			tween.finished.connect(func():
				emit_signal("ingredients_minigame_timeout")
			)
			
func clear_children(node: Node) -> void:
	for child in node.get_children():
		child.queue_free()
		
func clear_children_except_bowl(container: Node) -> void:
	for child in container.get_children():
		if child.name != "Bowl":
			child.queue_free()

func create_ingredient_wrapper(ingredient_id: String, is_clickable: bool = false):
	var path = "res://assets/pastry/ingredients/%s.png" % ingredient_id
	if not ResourceLoader.exists(path):
		print("No existe asset:", path)

	var tex = load(path)
		
	
	var wrapper = Control.new()
	wrapper.custom_minimum_size = tex.get_size() * 0.35 if is_clickable else tex.get_size() * 0.25
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var sprite = TextureRect.new()
	sprite.texture = tex
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.anchor_right = 1
	sprite.anchor_bottom = 1
	sprite.size_flags_horizontal = Control.SIZE_FILL
	sprite.size_flags_vertical = Control.SIZE_FILL
	
	if is_clickable:
		sprite.mouse_filter = Control.MOUSE_FILTER_STOP
		sprite.connect("gui_input", Callable(self, "_on_ingredient_clicked").bind(wrapper, ingredient_id))

	wrapper.add_child(sprite)
	return wrapper


func generate_arr(base: Array, base_len: int) -> Array:
	var result = base.duplicate()

	
	add_random_ingredients(result, GlobalManager.fake_ingredients)

	
	if GlobalManager.lives < GlobalManager.max_lives:
		add_random_ingredients(result, GlobalManager.gravitational_ingredients)
	
	
	while result.size() < base_len:
		var rand = base[randi() % base.size()]
		result.append(rand)
	
	shuffle_array(result)

	return result

func shuffle_array(arr: Array) -> void:
	
	for i in range(arr.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = arr[i]
		arr[i] = arr[j]
		arr[j] = temp

func add_random_ingredients(result: Array, source_array: Array) -> void:
	var count = 2 #TODO: incrementar segun cada nivel, randi() % (max_count + 1)
	for i in range(count):
		var ing = source_array[randi() % source_array.size()]
		result.append(ing.id)


# Botones
func _on_recipe_1_pressed() -> void:
	AudioManager.play_click_sfx()
	show_selected_recipe(0)

func _on_recipe_2_pressed() -> void:
	AudioManager.play_click_sfx()
	show_selected_recipe(1)

func _on_recipe_3_pressed() -> void:
	AudioManager.play_click_sfx()
	show_selected_recipe(2)

func _on_recipe_4_pressed() -> void:
	AudioManager.play_click_sfx()
	show_selected_recipe(3)

func _on_btn_back_pressed() -> void:
	AudioManager.play_click_sfx()
	hide_recipe_container()
	show_menu_container()

func _on_btn_continue_pressed() -> void:
	AudioManager.play_click_sfx()
	hide_recipe_container()
	hide_menu_container()
	show_recollect_container()
	start_ingredient_minigame()
	
	var instance = show_ingredients_textrect()
	fill_ingredients_textrect(instance)
	
func _on_btn_prepare_recipe_pressed() -> void:
	AudioManager.play_click_sfx()
	AudioManager.stop_newton_humming_sfx()
	GlobalManager.recipe_started = true
	
	if minigame_started:
		 
		for t in active_tweens:
			if is_instance_valid(t):
				t.kill()
		active_tweens.clear()
		
		
		clear_children(recollect_container)
		
		minigame_started = false
		btn_prepare.visible = false
		GameController.make_newton_cook()

func _on_ingredient_clicked(event: InputEvent, wrapper: Control, ing_id: String):
	if event is InputEventMouseButton and event.pressed:
		AudioManager.play_collect_ingredient_sfx()
		
		
		var target_pos = Vector2(1000, recollect_container.position.y + recollect_container.size.y - 50)
		
		
		var tween = create_tween()
		
		tween.tween_property(wrapper, "global_position", target_pos, 0.5)\
			.set_trans(Tween.TRANS_LINEAR)\
			.set_ease(Tween.EASE_IN)
			
		tween.tween_callback(Callable(wrapper, "queue_free"))

		GlobalManager.collected_ingredients.append(ing_id)
		
		
		if GlobalManager.collected_ingredients.size() >= 2 and is_instance_valid(btn_prepare):
			btn_prepare.visible = true
			btn_prepare.disabled = false


func random_point_in_polygon(poly: PackedVector2Array) -> Vector2:
	var min_x = poly[0].x
	var max_x = poly[0].x
	var min_y = poly[0].y
	var max_y = poly[0].y

	for v in poly:
		min_x = min(min_x, v.x)
		max_x = max(max_x, v.x)
		min_y = min(min_y, v.y)
		max_y = max(max_y, v.y)

	var point = Vector2()
	var attempts = 0
	while attempts < 1000:  
		point.x = randf_range(min_x, max_x)
		point.y = randf_range(min_y, max_y)
		if Geometry2D.is_point_in_polygon(point, poly):
			return point
		attempts += 1
		
	
	return poly[0] 
	
func create_ingredient_physics(ingredient_id: String) -> Area2D:
	var path = "res://assets/pastry/ingredients/%s.png" % ingredient_id
	if not ResourceLoader.exists(path): return null

	var tex = load(path)
	
	
	var area = Area2D.new()
	area.add_to_group("ingredients") 
	area.set_meta("id", ingredient_id)
	
	
	var sprite = Sprite2D.new()
	sprite.texture = tex
	sprite.scale = Vector2(0.3, 0.3)
	area.add_child(sprite)
	
	
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 30 
	collision.shape = shape
	area.add_child(collision)
	
	
	area.z_index = 1 
	
	return area
	
func check_prepare_button() -> void:
	if GlobalManager.collected_ingredients.size() > 0:
		btn_prepare.visible = true
		btn_prepare.disabled = false
