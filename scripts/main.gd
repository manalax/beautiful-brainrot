## Root node and scene switcher.
##
## Owns whichever screen is currently live (menu, game, ...) as its only child. Screens never
## swap themselves; they signal upward and Main does the swapping.
##
## Boots into the menu and swaps between it and the play scene (GAME_DESIGN.md §11).
extends Node

const MAIN_MENU := preload("res://scenes/ui/main_menu.tscn")
const GAME := preload("res://scenes/game/game.tscn")

var _current: Node = null


func _ready() -> void:
	show_menu()


func show_menu() -> void:
	# A run that quits from its own pause overlay leaves the tree paused otherwise.
	get_tree().paused = false
	var menu := change_scene(MAIN_MENU) as MainMenu
	menu.play_pressed.connect(start_game)


func start_game() -> void:
	var game := change_scene(GAME) as Game
	game.quit_to_menu.connect(show_menu)


## Replaces the live screen with an instance of `scene`, and returns it. Pass null to clear.
func change_scene(scene: PackedScene) -> Node:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null

	if scene == null:
		return null

	_current = scene.instantiate()
	add_child(_current)
	return _current


## The screen currently on display, or null.
func current_scene() -> Node:
	return _current
