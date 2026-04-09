# res://UI/ingame_ui.gd
extends Control

@onready var _phase_button: Button = $MarginContainer/PhaseToggleButton/Button
@onready var _clock_label: Label = $ClockAnchor/ClockPanel/ClockLabel
@onready var _clock_panel: Panel = $ClockAnchor/ClockPanel

var _time_sim: Node

const _COL_PLANNING := Color(0.22, 0.58, 0.4, 1.0)
const _COL_EXECUTING := Color(0.75, 0.38, 0.16, 1.0)
const _COL_IDLE := Color(0.38, 0.38, 0.42, 1.0)


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_clock_panel.focus_mode = Control.FOCUS_NONE
	_clock_label.focus_mode = Control.FOCUS_NONE
	_phase_button.focus_mode = Control.FOCUS_NONE
	_phase_button.pressed.connect(_on_phase_button_pressed)
	if not GameStateManager.phase_changed.is_connected(_on_phase_changed):
		GameStateManager.phase_changed.connect(_on_phase_changed)
	_refresh_phase_button(GameStateManager.get_phase())
	_time_sim = get_node_or_null("/root/TimeSimulator")
	if _time_sim:
		if not _time_sim.time_advanced.is_connected(_on_sim_time_advanced):
			_time_sim.time_advanced.connect(_on_sim_time_advanced)
		if not _time_sim.time_expired.is_connected(_on_sim_time_expired):
			_time_sim.time_expired.connect(_on_sim_time_expired)
	_style_clock_panel()
	_update_clock_display()


func _on_sim_time_advanced(_new_time: float) -> void:
	_update_clock_display()


func _on_sim_time_expired() -> void:
	_update_clock_display()


func _on_phase_changed(_new_phase: GameStateManager.GamePhase) -> void:
	_refresh_phase_button(GameStateManager.get_phase())
	_update_clock_display()


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
		_:
			_phase_button.disabled = true
			_phase_button.text = "—"
			_apply_phase_style(_COL_IDLE)


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
