# res://UI/ingame_ui.gd
extends Control

@onready var _phase_button: Button = $MarginContainer/PhaseToggleButton/Button
@onready var _left_controls: MarginContainer = $MarginContainer/LeftControls
@onready var _mode_button: Button = $MarginContainer/LeftControls/HBoxContainer/ModeButton
@onready var _clear_path_button: Button = $MarginContainer/LeftControls/HBoxContainer/ClearPathButton
@onready var _deselect_button: Button = $MarginContainer/LeftControls/HBoxContainer/DeselectButton
@onready var _clock_label: Label = $ClockAnchor/ClockPanel/ClockLabel
@onready var _clock_panel: Panel = $ClockAnchor/ClockPanel

var _time_sim: Node
var _input_router: Node
var _selected_unit: Node = null

const _COL_PLANNING := Color(0.22, 0.58, 0.4, 1.0)
const _COL_EXECUTING := Color(0.75, 0.38, 0.16, 1.0)
const _COL_IDLE := Color(0.38, 0.38, 0.42, 1.0)
const _COL_ACTION := Color(0.22, 0.42, 0.68, 1.0)

const _MODE_CROUCH := 0
const _MODE_STAND := 1
const _MODE_RUN := 2


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_clock_panel.focus_mode = Control.FOCUS_NONE
	_clock_label.focus_mode = Control.FOCUS_NONE
	_phase_button.focus_mode = Control.FOCUS_NONE
	_mode_button.focus_mode = Control.FOCUS_NONE
	_clear_path_button.focus_mode = Control.FOCUS_NONE
	_deselect_button.focus_mode = Control.FOCUS_NONE
	_phase_button.pressed.connect(_on_phase_button_pressed)
	_mode_button.pressed.connect(_on_mode_button_pressed)
	_clear_path_button.pressed.connect(_on_clear_path_button_pressed)
	_deselect_button.pressed.connect(_on_deselect_button_pressed)
	if not GameStateManager.phase_changed.is_connected(_on_phase_changed):
		GameStateManager.phase_changed.connect(_on_phase_changed)
	_refresh_phase_button(GameStateManager.get_phase())
	_time_sim = get_node_or_null("/root/TimeSimulator")
	_input_router = get_node_or_null("/root/InputRouter")
	if _input_router and _input_router.has_signal("unit_selected"):
		if not _input_router.unit_selected.is_connected(_on_unit_selected):
			_input_router.unit_selected.connect(_on_unit_selected)
	if _time_sim:
		if not _time_sim.time_advanced.is_connected(_on_sim_time_advanced):
			_time_sim.time_advanced.connect(_on_sim_time_advanced)
		if not _time_sim.time_expired.is_connected(_on_sim_time_expired):
			_time_sim.time_expired.connect(_on_sim_time_expired)
	_style_clock_panel()
	_apply_action_button_style(_mode_button, _COL_ACTION)
	_apply_action_button_style(_clear_path_button, _COL_EXECUTING)
	_apply_action_button_style(_deselect_button, _COL_IDLE)
	_refresh_selection_controls()
	_update_clock_display()


func _on_sim_time_advanced(_new_time: float) -> void:
	_update_clock_display()


func _on_sim_time_expired() -> void:
	_update_clock_display()


func _on_phase_changed(_new_phase: GameStateManager.GamePhase) -> void:
	_refresh_phase_button(GameStateManager.get_phase())
	_refresh_selection_controls()
	_update_clock_display()


func _on_unit_selected(unit: Node) -> void:
	_selected_unit = unit
	_refresh_selection_controls()


func _style_clock_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.14, 0.94)
	sb.border_color = Color(0.22, 0.26, 0.32, 1.0)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_clock_panel.add_theme_stylebox_override(&"panel", sb)


func _update_clock_display() -> void:
	if not _time_sim or not _clock_label:
		return
	var t: float = _time_sim.get_current_time()
	_clock_label.text = _time_sim.format_time(t)


func _on_phase_button_pressed() -> void:
	var p := GameStateManager.get_phase()
	match p:
		GameStateManager.GamePhase.PLANNING:
			GameStateManager.start_execution()
		GameStateManager.GamePhase.EXECUTING:
			GameStateManager.pause_execution()


func _on_mode_button_pressed() -> void:
	if _selected_unit == null:
		return
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		return
	var next_mode := (_unit_mode_index(_selected_unit) + 1) % 3
	_apply_mode_to_unit(_selected_unit, next_mode)
	_refresh_selected_unit_plan_after_mode_change()
	_refresh_selection_controls()


func _refresh_selected_unit_plan_after_mode_change() -> void:
	if _selected_unit == null:
		return
	var nav := get_tree().get_first_node_in_group("unit_navigation")
	if nav != null and nav.has_method("replan_unit"):
		nav.call_deferred("replan_unit", _selected_unit)


func _on_clear_path_button_pressed() -> void:
	if _input_router == null or _selected_unit == null:
		return
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		return
	if _input_router.has_method("request_clear_selected_path"):
		_input_router.call("request_clear_selected_path")


func _on_deselect_button_pressed() -> void:
	if _input_router == null:
		return
	if GameStateManager.get_phase() != GameStateManager.GamePhase.PLANNING:
		return
	if _input_router.has_method("clear_selection"):
		_input_router.call("clear_selection")


func _refresh_phase_button(phase: GameStateManager.GamePhase) -> void:
	match phase:
		GameStateManager.GamePhase.PLANNING:
			_phase_button.disabled = false
			_phase_button.text = "Execute"
			_apply_phase_style(_COL_PLANNING)
		GameStateManager.GamePhase.EXECUTING:
			_phase_button.disabled = false
			_phase_button.text = "Pause"
			_apply_phase_style(_COL_EXECUTING)
		GameStateManager.GamePhase.BRIEFING, GameStateManager.GamePhase.DEBRIEFING:
			_phase_button.disabled = true
			_phase_button.text = "—"
			_apply_phase_style(_COL_IDLE)


func _refresh_selection_controls() -> void:
	var planning := GameStateManager.get_phase() == GameStateManager.GamePhase.PLANNING
	var has_selection := _selected_unit != null
	var show_controls := planning and has_selection
	_left_controls.visible = show_controls
	_mode_button.disabled = not show_controls
	_clear_path_button.disabled = not show_controls
	_deselect_button.disabled = not show_controls
	if show_controls:
		_mode_button.text = "Mode: " + _mode_name(_unit_mode_index(_selected_unit))


func _unit_mode_index(unit: Node) -> int:
	var stance_v: Variant = unit.get("current_stance")
	var speed_v: Variant = unit.get("current_movement_speed")
	var stance := int(stance_v) if stance_v is int else int(MovementEnums.Stance.STANDING)
	var speed := int(speed_v) if speed_v is int else int(MovementEnums.MovementSpeed.WALKING)
	if stance == int(MovementEnums.Stance.CROUCHING):
		return _MODE_CROUCH
	if speed == int(MovementEnums.MovementSpeed.SPRINTING):
		return _MODE_RUN
	return _MODE_STAND


func _mode_name(mode_idx: int) -> String:
	match mode_idx:
		_MODE_CROUCH:
			return "Crouch"
		_MODE_RUN:
			return "Run"
		_:
			return "Stand"


func _apply_mode_to_unit(unit: Node, mode_idx: int) -> void:
	match mode_idx:
		_MODE_CROUCH:
			if unit.has_method("set_stance"):
				unit.call("set_stance", MovementEnums.Stance.CROUCHING)
			if unit.has_method("set_movement_speed"):
				unit.call("set_movement_speed", MovementEnums.MovementSpeed.WALKING)
		_MODE_RUN:
			if unit.has_method("set_stance"):
				unit.call("set_stance", MovementEnums.Stance.STANDING)
			if unit.has_method("set_weapon_state"):
				unit.call("set_weapon_state", MovementEnums.WeaponState.LOW)
			if unit.has_method("set_movement_speed"):
				unit.call("set_movement_speed", MovementEnums.MovementSpeed.SPRINTING)
		_:
			if unit.has_method("set_stance"):
				unit.call("set_stance", MovementEnums.Stance.STANDING)
			if unit.has_method("set_movement_speed"):
				unit.call("set_movement_speed", MovementEnums.MovementSpeed.WALKING)


func _apply_phase_style(base: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.1)
	var pressed := normal.duplicate()
	pressed.bg_color = base.darkened(0.12)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = _COL_IDLE.darkened(0.05)
	disabled.set_corner_radius_all(8)
	disabled.set_content_margin_all(10)
	_phase_button.add_theme_stylebox_override(&"normal", normal)
	_phase_button.add_theme_stylebox_override(&"hover", hover)
	_phase_button.add_theme_stylebox_override(&"pressed", pressed)
	_phase_button.add_theme_stylebox_override(&"disabled", disabled)
	_phase_button.add_theme_color_override(&"font_color", Color.WHITE)
	_phase_button.add_theme_color_override(&"font_hover_color", Color.WHITE)
	_phase_button.add_theme_color_override(&"font_pressed_color", Color(0.95, 0.95, 0.95))
	_phase_button.add_theme_color_override(&"font_disabled_color", Color(0.65, 0.65, 0.68))


func _apply_action_button_style(btn: Button, base: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = base
	normal.set_corner_radius_all(8)
	normal.set_content_margin_all(10)
	var hover := normal.duplicate()
	hover.bg_color = base.lightened(0.1)
	var pressed := normal.duplicate()
	pressed.bg_color = base.darkened(0.12)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = _COL_IDLE.darkened(0.05)
	disabled.set_corner_radius_all(8)
	disabled.set_content_margin_all(10)
	btn.add_theme_stylebox_override(&"normal", normal)
	btn.add_theme_stylebox_override(&"hover", hover)
	btn.add_theme_stylebox_override(&"pressed", pressed)
	btn.add_theme_stylebox_override(&"disabled", disabled)
	btn.add_theme_color_override(&"font_color", Color.WHITE)
	btn.add_theme_color_override(&"font_hover_color", Color.WHITE)
	btn.add_theme_color_override(&"font_pressed_color", Color(0.95, 0.95, 0.95))
	btn.add_theme_color_override(&"font_disabled_color", Color(0.65, 0.65, 0.68))
