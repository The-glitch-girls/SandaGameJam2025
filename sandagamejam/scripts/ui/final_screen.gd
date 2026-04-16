extends Control

@export var leaderboard_internal_name: String

@onready var anim = $AnimationPlayer
@onready var bg = $Background
@onready var message = $Message
@onready var message_label = $Message/Label
@onready var score_panel = $ScorePanel
@onready var newton = $Newton
@onready var score_container = $ScoreContainer
@onready var score_label = $ScoreContainer/Score
@onready var name_label = $ScoreContainer/Name
@onready var ranking_container = $RankingContainer
@onready var play_again_btn = $BtnPlayAgain
@onready var back_to_menu_btn = $BtnBackToMenu
@onready var recipe_texture = $Recipe
@onready var loading_label = $LoadingLabel


@export var dot_speed: float = 0.5 
@export var max_dots: int = 3

var current_dots: int = 0
var base_text: String = GlobalManager.loading_label
var timer: Timer


@onready var bg_win   = preload("res://assets/backgrounds/good_score_bg.png")
@onready var bg_fail  = preload("res://assets/backgrounds/bad_score_bg.png")
@onready var newton_fail = preload("res://assets/sprites/newtown/newton_sad.png")
@onready var newton_win = preload("res://assets/sprites/newtown/newton_happy.png")
@onready var recipe_fail = preload("res://assets/pastry/recipes/recipe_003_wrong.png")
@onready var recipe_win = preload("res://assets/pastry/recipes/recipe_003.png")
@onready var ranking_label_settings: LabelSettings = preload("res://custom_resources/Ranking.tres")

var add_new_score: bool = false
var name_entered: bool = false
var score: int = 100
var max_name_length: int = 6
var current_name: Array = []
var cached_entries: Array = []
var ranking: Array = []
var menu_labels = GlobalManager.menu_labels[GlobalManager.game_language]
var settings_instance = preload("res://custom_resources/Ranking.tres").duplicate()

# Efectos de celebracion
var confetti_container: Node2D = null
var confetti_timer: Timer = null
var newton_bounce_tween: Tween = null
var current_state: GlobalManager.GameState

func _ready():
	AudioManager.play_end_music()
	if GlobalManager.satisfied_customers.size() == 0:
		score = 0
	else:
		score = (round(GlobalManager.time_left) * 10) + (GlobalManager.lives * 100)
	
	settings_instance.font_size = 50
	message_label.label_settings = settings_instance

	score_label.text = menu_labels["ranking"]["score"] + " " + str(score)
	add_new_score = await is_player_in_ranking(score)
	show_name_label()
	
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and add_new_score:
		#a-z y A-Z
		if (event.unicode >= 65 and event.unicode <=90) or (event.unicode >= 97 and event.unicode <= 122):
			var char_typed = char(event.unicode).to_upper()
			if current_name.size() < max_name_length:
				current_name.append(char_typed)
				show_name_label()
		
		elif event.keycode == KEY_BACKSPACE and current_name.size() > 0:
				current_name.pop_back()
				show_name_label()
			
		elif event.keycode == KEY_ENTER and current_name.size() > 0 and not name_entered:
			hide_player_score_labels()
			animate_loading_label()
			await store_in_talo("".join(current_name), score)
			stop_loading_animation()
			show_ranking()
			name_entered = true
	
# state puede ser: "win", "lose", "timeup"
func show_final_screen(state: GlobalManager.GameState):
	current_state = state
	AudioManager.stop_game_music()
	score_panel.visible = false
	recipe_texture.texture = recipe_fail

	match state:
		GlobalManager.GameState.TIMEUP:
			bg.texture = bg_fail
			newton.texture = newton_fail
			message_label.text = menu_labels["final_screen"]["time_up"]
			AudioManager.play_time_up_sfx()
		GlobalManager.GameState.WIN:
			bg.texture = bg_win
			recipe_texture.texture = recipe_win
			newton.texture = newton_win
			message_label.text = menu_labels["final_screen"]["win"]
			AudioManager.play_win_sfx()
			# Iniciar confeti y celebracion
			start_confetti_celebration()
		GlobalManager.GameState.GAMEOVER:
			bg.texture = bg_fail
			newton.texture = newton_fail
			message_label.text = menu_labels["final_screen"]["game_over"]
			AudioManager.play_game_over_sfx()

	anim.play("final_sequence")

	# Iniciar animacion de Newton despues de que entre
	await get_tree().create_timer(3.5).timeout
	start_newton_animation(state)
	
func show_name_label():
	var display = ""

	if not add_new_score:
		name_label.text = display
		# Si no califica para ranking, mostrar botones directamente
		show_buttons()
		return

	for i in range(max_name_length):
		if i < current_name.size():
			display += current_name[i] + ""
		else:
			display += "_ "
	name_label.text =  menu_labels["ranking"]["name"] + "\n" + display

func show_buttons():
	var label = play_again_btn.get_node("Label")
	label.text = menu_labels["play_again"]
	var back_label = back_to_menu_btn.get_node("Label")
	back_label.text = menu_labels.get("back_to_menu", "Menú principal")
	play_again_btn.visible = true
	back_to_menu_btn.visible = true 
	

func animate_loading_label():
	loading_label.visible = true
	loading_label.text = base_text
	if timer == null:
		timer = Timer.new()
		add_child(timer)
		timer.wait_time = dot_speed
		timer.timeout.connect(update_dots)
	timer.start()

func update_dots():
	current_dots = (current_dots + 1) % (max_dots + 1)
	loading_label.text = base_text + ".".repeat(current_dots)

func stop_loading_animation():
	if timer and not timer.is_stopped():
		timer.stop()
	loading_label.visible = false
	current_dots = 0


func store_in_talo(username: String, score_value: int) -> void:
	await Talo.players.identify("username", username)
	
	await Talo.leaderboards.add_entry(leaderboard_internal_name, score_value)
	_build_entries()

func load_entries_from_talo() -> void:
	var page = 0
	var done = false

	while !done:
		var options := Talo.leaderboards.GetEntriesOptions.new()
		options.page = page
		
	
		var res = await Talo.leaderboards.get_entries(leaderboard_internal_name, options)

		
		if res == null:
			print("Talo devolvió null")
			done = true 
			break
		
		var is_last_page: bool = res.is_last_page
		if is_last_page:
			done = true
		else:
			page += 1
	
	_build_entries()


func is_player_in_ranking(score_value: int) -> bool:
	await load_entries_from_talo()
	
	
	if cached_entries.size() == 0:
		return true
		
	
	if cached_entries.size() < 10:
		return true


	var last_child_idx = cached_entries.size()
	var lower_score = cached_entries[last_child_idx - 1].score
	
	return score_value > lower_score

func show_ranking():
	loading_label.visible = false
	ranking_container.visible = true
	show_buttons()
	
	
func _on_AnimationPlayer_animation_finished(anim_name):
	if anim_name == "final_sequence":
		score_panel.visible = true
		score_panel.modulate.a = 0
		score_panel.create_tween().tween_property(score_panel, "modulate:a", 1.0, 0.4)

func _on_btn_play_again_pressed() -> void:
	queue_free()
	AudioManager.play_click_sfx()
	GameController.reset_game()

func _on_btn_back_to_menu_pressed() -> void:
	queue_free()
	AudioManager.play_click_sfx()
	GameController.load_main_menu()
	
func _build_entries() -> void:
	free_container_children()
	
	
	cached_entries = Talo.leaderboards.get_cached_entries(leaderboard_internal_name)
	if cached_entries.size() > 10:
		cached_entries = cached_entries.slice(0, 10)
	
	for entry in cached_entries:
		_create_entry(entry)
	
func _create_entry(entry: TaloLeaderboardEntry) -> void:
	
	var player_label = Label.new()
	player_label.text = str(entry.position)+". " + entry.player_alias.identifier +" - " + str(int(entry.score))
	player_label.label_settings = ranking_label_settings
	ranking_container.add_child(player_label)
	
# helpers
func free_container_children():
	for child in ranking_container.get_children():
		child.queue_free() 

func hide_player_score_labels():
	message.visible = false
	score_container.visible = false

# ============ EFECTOS DE CELEBRACION ============

func start_confetti_celebration() -> void:
	# Crear contenedor para confeti
	if confetti_container and is_instance_valid(confetti_container):
		confetti_container.queue_free()

	confetti_container = Node2D.new()
	confetti_container.name = "ConfettiContainer"
	confetti_container.z_index = 50
	add_child(confetti_container)

	# Timer para crear confeti continuamente
	if confetti_timer and is_instance_valid(confetti_timer):
		confetti_timer.queue_free()

	confetti_timer = Timer.new()
	confetti_timer.wait_time = 0.05
	confetti_timer.autostart = true
	add_child(confetti_timer)
	confetti_timer.timeout.connect(create_confetti_particle)

	# Detener confeti despues de unos segundos
	await get_tree().create_timer(5.0).timeout
	stop_confetti()

func create_confetti_particle() -> void:
	if not confetti_container or not is_instance_valid(confetti_container):
		return

	var colors = [
		Color(1, 0.3, 0.3),    # Rojo
		Color(1, 0.8, 0.2),    # Amarillo
		Color(0.3, 0.8, 0.3),  # Verde
		Color(0.3, 0.6, 1),    # Azul
		Color(1, 0.5, 0.8),    # Rosa
		Color(0.8, 0.4, 1),    # Morado
	]

	var viewport_size = get_viewport().get_visible_rect().size

	if colors.size() == 0:
		return

	var confetti = ColorRect.new()
	confetti.size = Vector2(randf_range(8, 16), randf_range(4, 8))
	confetti.color = colors[randi() % colors.size()]
	confetti.position = Vector2(randf_range(0, viewport_size.x), -20)
	confetti.rotation = randf() * TAU
	confetti_container.add_child(confetti)

	# Animacion de caida con movimiento lateral
	var end_y = viewport_size.y + 50
	var lateral_offset = randf_range(-100, 100)
	var duration = randf_range(2.0, 4.0)

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(confetti, "position:y", end_y, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(confetti, "position:x", confetti.position.x + lateral_offset, duration)
	tween.tween_property(confetti, "rotation", confetti.rotation + randf_range(-TAU, TAU), duration)
	tween.set_parallel(false)
	tween.tween_callback(confetti.queue_free)

func stop_confetti() -> void:
	if confetti_timer and is_instance_valid(confetti_timer):
		confetti_timer.stop()
		confetti_timer.queue_free()
		confetti_timer = null

func start_newton_animation(state: GlobalManager.GameState) -> void:
	if newton_bounce_tween and newton_bounce_tween.is_running():
		newton_bounce_tween.kill()

	var original_scale = newton.scale

	match state:
		GlobalManager.GameState.WIN:
			# Animacion de celebracion: bounce y rotacion
			newton_bounce_tween = create_tween().set_loops()
			newton_bounce_tween.tween_property(newton, "scale", original_scale * 1.1, 0.2).set_trans(Tween.TRANS_SINE)
			newton_bounce_tween.tween_property(newton, "scale", original_scale * 0.95, 0.2).set_trans(Tween.TRANS_SINE)
			newton_bounce_tween.tween_property(newton, "scale", original_scale, 0.1)

			# Rotacion suave
			var rotation_tween = create_tween().set_loops()
			rotation_tween.tween_property(newton, "rotation", deg_to_rad(5), 0.15)
			rotation_tween.tween_property(newton, "rotation", deg_to_rad(-5), 0.3)
			rotation_tween.tween_property(newton, "rotation", 0, 0.15)

		GlobalManager.GameState.TIMEUP, GlobalManager.GameState.GAMEOVER:
			# Animacion de tristeza: movimiento lento y llorando
			newton_bounce_tween = create_tween().set_loops()
			newton_bounce_tween.tween_property(newton, "position:y", newton.position.y + 5, 1.0).set_trans(Tween.TRANS_SINE)
			newton_bounce_tween.tween_property(newton, "position:y", newton.position.y - 5, 1.0).set_trans(Tween.TRANS_SINE)

			# Lagrimas (particulas)
			create_tear_effect()

func create_tear_effect() -> void:
	var tear_timer = Timer.new()
	tear_timer.wait_time = 0.8
	tear_timer.autostart = true
	add_child(tear_timer)

	tear_timer.timeout.connect(func():
		if not newton or not is_instance_valid(newton):
			tear_timer.queue_free()
			return

		var tear = ColorRect.new()
		tear.size = Vector2(4, 8)
		tear.color = Color(0.5, 0.7, 1, 0.8)
		tear.position = newton.position + Vector2(randf_range(-20, 20), 30)
		tear.z_index = 51
		add_child(tear)

		var tween = create_tween()
		tween.tween_property(tear, "position:y", tear.position.y + 60, 0.8)
		tween.parallel().tween_property(tear, "modulate:a", 0.0, 0.8)
		tween.tween_callback(tear.queue_free)
	)

	# Detener lagrimas despues de un tiempo
	await get_tree().create_timer(6.0).timeout
	if tear_timer and is_instance_valid(tear_timer):
		tear_timer.queue_free()

