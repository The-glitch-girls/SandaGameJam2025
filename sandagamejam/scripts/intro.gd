extends Node2D

@onready var btn_start: TextureButton = $Comenzar_Game
@onready var text_intro: Label = $TextureRect/text_intro
@onready var btn_back: Button = $BtnBack if has_node("BtnBack") else null 
@onready var btn_omit_intro: Button = $OmitIntro


var json_texts = {
	"es":
		[
			"¡Bienvenido a mi cafeteria! Te preguntarás qué hace Isaac Newton con un mandil y preparando pasteles.",
			"Pues, descubrí mi pasión por la pastelería cuando me cayó una manzana en la cabeza mientras descansaba bajo un manzanero.",
			"Durante los siguientes minutos, llegaran mis mejores clientes para degustar de mis deliciosas preparaciones a base de mi fruta favorita, la manzana.",
			"¡Es hora de abrir!, aquí viene nuestro primer comensal "
		],
	"en":
		[
			"Welcome to my pastry! You might be wondering what Isaac Newton is doing wearing an apron and baking pastries.",
			"Well, I discovered my passion for baking when an apple fell on my head while I was resting under an apple tree.",
			"Over the next few minutes, my best customers will arrive to enjoy my delicious creations made with my favorite fruit: the apple.",
			"It's time to open! Here comes our first guest."
		],
	"fr":
		[
			"Bienvenue dans mon café!. Tu te demandes peut-être ce que fait Isaac Newton avec un tablier, en train de préparer des pâtisseries.",
			"Eh bien, j'ai découvert ma passion pour la pâtisserie quand une pomme m'est tombée sur la tête pendant que je me reposais sous un pommier.",
			"Dans les prochaines minutes, mes meilleurs clients arriveront pour savourer mes délicieuses créations à base de mon fruit préféré : la pomme.",
			"Il est temps d’ouvrir ! Voici notre premier invité.",
		]
}

var texts = []
var typing_speed := 0.05
var skip_labels = {
	"es": "Omitir intro >",
	"en": "Skip intro >",
	"fr": "Passer l'intro >"
}
var typing_timer: Timer
var full_text := ""
var char_index := 0
var current_index = 0
var is_typing := false

func _ready():
	texts = json_texts[GlobalManager.game_language]
	# animación de tipeo
	typing_timer = Timer.new()
	typing_timer.wait_time = typing_speed
	typing_timer.one_shot = false
	typing_timer.timeout.connect(Callable(self, "_on_typing_timeout"))
	add_child(typing_timer)

	_show_text(texts[current_index])

	# Configurar texto del botón omitir según idioma
	if btn_omit_intro:
		btn_omit_intro.text = skip_labels.get(GlobalManager.game_language, skip_labels["es"])

	btn_start.pressed.connect(_on_btn_start_pressed)
	if has_node("BtnBack"):
		btn_back.pressed.connect(_on_btn_back_pressed)

func _show_text(new_text: String):
	full_text = new_text
	char_index = 0
	text_intro.text = ""
	is_typing = true
	typing_timer.start()
	
func _on_typing_timeout():
	if char_index < full_text.length():
		text_intro.text += full_text[char_index]
		char_index += 1
	else:
		typing_timer.stop()
		is_typing = false

func _on_btn_start_pressed():
	AudioManager.play_click_sfx()
	
	if is_typing:
		text_intro.text = full_text
		typing_timer.stop()
		is_typing = false
		return
		
	current_index += 1
	if current_index < texts.size():
		_show_text(texts[current_index])
	else:
		# Tercer clic → iniciar juego
		var level_1_path = "res://scenes/levels/PastryLevel1.tscn"
		GlobalManager.start_game()
		GameController.load_level(level_1_path)
		GameController.show_newton_layer()

func _on_btn_back_pressed():
	AudioManager.play_click_sfx()
	get_tree().change_scene_to_file("res://scenes/menus/MainMenu.tscn")

func _on_omit_intro_pressed():
	AudioManager.play_click_sfx()
	var level_1_path = "res://scenes/levels/PastryLevel1.tscn"
	GlobalManager.start_game()
	GameController.load_level(level_1_path)
	GameController.show_newton_layer()
