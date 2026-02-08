# ~/Gameplay/Input/player_keybind.gd
extends Node

var SELECT_GROUND_KEY: String = "select_ground"
var SELECT_UNIT_KEY: String = "select_unit"
var TOGGLE_EXECUTION_KEY: String = "toggle_execution"
var REWIND_KEY: String = "rewind"
var RESET_GAME_KEY: String = "reset_game"

const CONFIG_PATH = "user://keybinds.cfg"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_ensure_action_exist()
	load_keybinds()

func _ensure_action_exist() -> void:
	var keybinds = [
		SELECT_GROUND_KEY,
		SELECT_UNIT_KEY,
		TOGGLE_EXECUTION_KEY,
		REWIND_KEY,
		RESET_GAME_KEY
	]
	
	for keybind in keybinds:
		if ! InputMap.has_action(keybind):
			InputMap.add_action(keybind)

func load_keybinds() -> void:
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	if err != OK:
		apply_default_keybinds()
		save_keybinds()
		return
	
	SELECT_GROUND_KEY = config.get_value("keybinds", "select_ground", "select_ground")
	SELECT_UNIT_KEY = config.get_value("keybinds", "select_unit", "select_unit")
	TOGGLE_EXECUTION_KEY = config.get_value("keybinds", "toggle_execution", "toggle_execution")
	REWIND_KEY = config.get_value("keybinds", "rewind", "rewind")
	RESET_GAME_KEY = config.get_value("keybinds", "reset_game", "reset_game")
	
	_load_keybind_events_from_config(config)

func apply_default_keybinds() -> void:
	_ensure_action_exist()
	
	_set_action_key(SELECT_GROUND_KEY, MOUSE_BUTTON_LEFT)
	_set_action_key(SELECT_UNIT_KEY, MOUSE_BUTTON_LEFT)
	_set_action_key(TOGGLE_EXECUTION_KEY, KEY_SPACE)
	_set_action_key(REWIND_KEY, KEY_BACKSPACE)
	_set_action_key(RESET_GAME_KEY, KEY_R)

func _load_keybind_events_from_config(config: ConfigFile) -> void:
	for action_name in [SELECT_GROUND_KEY, SELECT_UNIT_KEY, TOGGLE_EXECUTION_KEY, REWIND_KEY, RESET_GAME_KEY]:
		var events_data = config.get_value("input_events", action_name, [])
		
		if events_data.is_empty():
			match action_name:
				SELECT_GROUND_KEY, SELECT_UNIT_KEY:
					_set_action_key(action_name, MOUSE_BUTTON_LEFT)
				TOGGLE_EXECUTION_KEY:
					_set_action_key(action_name, KEY_SPACE)
				REWIND_KEY:
					_set_action_key(action_name, KEY_BACKSPACE)
				RESET_GAME_KEY:
					_set_action_key(action_name, KEY_F5)
		else:
			InputMap.action_erase_events(action_name)
			for event_data in events_data:
				var event = _dict_to_event(event_data)
				if event:
					InputMap.action_add_event(action_name, event)

func _set_action_key(keybind: String, key: int) -> void:
	if !InputMap.has_action(keybind):
		InputMap.add_action(keybind)
	
	InputMap.action_erase_events(keybind)
	
	var event: InputEvent
	if key >= MOUSE_BUTTON_LEFT && key <= MOUSE_BUTTON_XBUTTON2:
		event = InputEventMouseButton.new()
		event.button_index = key
	else:
		event = InputEventKey.new()
		event.keycode = key
	
	InputMap.action_add_event(keybind, event)

func _dict_to_event(dict: Dictionary) -> InputEvent:
	var event: InputEvent
	if dict.is_empty(): return null
	
	match dict.get("type", ""):
		"key":
			event = InputEventKey.new()
			var key_event = event as InputEventKey
			key_event.keycode = dict.get("keycode", 0)
			key_event.physical_keycode = dict.get("physical_keycode", 0)
		"mouse_button":
			event = InputEventMouseButton.new()
			var mouse_event = event as InputEventMouseButton
			mouse_event.button_index = dict.get("button_index", 0)
	
	return event

func save_keybinds() -> void:
	var config = ConfigFile.new()
	
	config.set_value("keybinds", "select_ground", SELECT_GROUND_KEY)
	config.set_value("keybinds", "select_unit", SELECT_UNIT_KEY)
	config.set_value("keybinds", "toggle_execution", TOGGLE_EXECUTION_KEY)
	config.set_value("keybinds", "rewind", REWIND_KEY)
	config.set_value("keybinds", "reset_game", RESET_GAME_KEY)
	
	for action_name in [SELECT_GROUND_KEY, SELECT_UNIT_KEY, TOGGLE_EXECUTION_KEY, REWIND_KEY, RESET_GAME_KEY]:
		var events = []
		if InputMap.has_action(action_name):
			for event in InputMap.action_get_events(action_name):
				events.append(_event_to_dict(event))
		config.set_value("input_events", action_name, events)
		
	config.save(CONFIG_PATH)

func _event_to_dict(event: InputEvent) -> Dictionary:
	var dict = {}
	
	if event is InputEventKey:
		var key = event as InputEventKey
		dict["type"] = "key"
		dict["keycode"] = key.keycode
		dict["physical_keycode"] = key.physical_keycode
	elif event is InputEventMouseButton:
		var mouseKey = event as InputEventMouseButton
		dict["type"] = "mouse_button"
		dict["button_index"] = mouseKey.button_index
	
	return dict

func rebind_key(action_name: String, new_event: InputEvent) -> void:
	if ! InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	
	InputMap.action_erase_events(action_name)
	InputMap.action_add_event(action_name, new_event)
	
	match action_name:
		SELECT_GROUND_KEY, "select_ground":
			SELECT_GROUND_KEY = action_name
		SELECT_UNIT_KEY, "select_unit":
			SELECT_UNIT_KEY = action_name
		TOGGLE_EXECUTION_KEY, "toggle_execution":
			TOGGLE_EXECUTION_KEY = action_name
		REWIND_KEY, "rewind":
			REWIND_KEY = action_name
		RESET_GAME_KEY, "reset_game":
			RESET_GAME_KEY = action_name
	
	save_keybinds()

func get_keybind_display_name(action_name: String) -> String:
	if ! InputMap.has_action(action_name): return "Not Set"
	
	var events = InputMap.action_get_events(action_name)
	if events.is_empty(): return "Not Set"
	
	var event = events[0]
	if event is InputEventKey:
		var key_event = event as InputEventKey
		return OS.get_keycode_string(key_event.keycode)
	elif event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT: return "Left Click"
			MOUSE_BUTTON_RIGHT: return "Right Click"
			MOUSE_BUTTON_MIDDLE: return "Middle Click"
			MOUSE_BUTTON_XBUTTON1: return "Mouse Side 1"
			MOUSE_BUTTON_XBUTTON2: return "Mouse Side 2"
			MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
			MOUSE_BUTTON_WHEEL_LEFT: return "Wheel Left"
			MOUSE_BUTTON_WHEEL_RIGHT: return "Wheel Right"
			_: return "Mouse Button " + str(mouse_event.button_index)
	return "Unknown"
