extends RefCounted
class_name GameHudPresenter

var _status_value: Label
var _debug_value: Label
var _stop_command_button: Button
var _produce_command_button: Button


func setup(
	status_value: Label,
	debug_value: Label,
	stop_command_button: Button,
	produce_command_button: Button
) -> void:
	_status_value = status_value
	_debug_value = debug_value
	_stop_command_button = stop_command_button
	_produce_command_button = produce_command_button


func refresh(
	frame: Dictionary,
	selection: GameSelectionState,
	unit_count: int,
	latest_diagnostic: String
) -> void:
	var map := FrontendFrame.map(frame)
	var resources := FrontendFrame.resources(frame)
	var commands := FrontendFrame.commands(frame)
	var room := FrontendFrame.room(frame)

	refresh_command_controls(selection)
	_status_value.text = "map=%s mode=%s room=%s resources=%s control=%s status=%s server_tick=%s client_tick=%s units=%s selected=%s" % [
		map.get("title", "unknown"),
		FrontendFrame.mode(frame),
		_room_summary(room),
		_resource_summary(resources),
		_control_mode_summary(selection),
		FrontendFrame.status(frame),
		FrontendFrame.server_tick(frame),
		FrontendFrame.client_tick(frame),
		unit_count,
		_selected_unit_summary(selection),
	]

	var debug_lines := [
		"move=%s" % _movement_command_summary(selection),
		"production=%s" % _production_command_summary(selection),
		"sync=%s" % _lightyear_prediction_summary(commands),
		"commands=%s" % _command_lifecycle_summary(commands),
	]
	if !latest_diagnostic.is_empty():
		debug_lines.append("diag=%s" % latest_diagnostic)
	_debug_value.text = "\n".join(debug_lines)


func refresh_command_controls(selection: GameSelectionState) -> void:
	_stop_command_button.disabled = !selection.selected_unit_can_stop()
	var build_option := selection.selected_unit_primary_build_option()
	if build_option.is_empty():
		_produce_command_button.text = "Produce"
	else:
		_produce_command_button.text = "Produce %s" % _short_unit_name(str(build_option.get("display_name", build_option.get("unit", "unit"))))
	_produce_command_button.disabled = !selection.selected_unit_can_produce()


func disable_stop_command() -> void:
	_stop_command_button.disabled = true


func disable_produce_command() -> void:
	_produce_command_button.disabled = true


func _control_mode_summary(selection: GameSelectionState) -> String:
	var controllable_count := selection.controllable_unit_count()
	if controllable_count == 0:
		return "readonly"
	if selection.selected_unit_id != 0:
		if selection.selected_unit_can_control():
			return "owned"
		return "readonly"
	return "owned:%s" % controllable_count


func _room_summary(room: Dictionary) -> String:
	var phase := str(room.get("phase", "lobby"))
	var local_team_id := int(room.get("local_team_id", -1))
	var player_slots := FrontendFrame.array(room, "player_slots")
	var local_team := "none"
	if local_team_id >= 0:
		local_team = str(local_team_id)
	return "phase:%s team:%s slots:%s" % [phase, local_team, player_slots.size()]


func _resource_summary(resources: Dictionary) -> String:
	var team_id := int(resources.get("team_id", -1))
	if team_id < 0:
		return "none"

	var amounts := FrontendFrame.array(resources, "amounts")
	if amounts.is_empty():
		return "team:%s empty" % team_id

	var parts := PackedStringArray()
	for amount_value in amounts:
		if typeof(amount_value) != TYPE_DICTIONARY:
			continue
		var amount: Dictionary = amount_value
		parts.append("%s=%s" % [
			_short_resource_name(str(amount.get("resource", "unknown"))),
			amount.get("amount", 0),
		])

	if parts.is_empty():
		return "team:%s empty" % team_id
	return "team:%s %s" % [team_id, " ".join(parts)]


func _short_resource_name(resource: String) -> String:
	var separator_index := resource.find(":")
	if separator_index < 0 || separator_index == resource.length() - 1:
		return resource
	return resource.substr(separator_index + 1)


func _short_unit_name(unit: String) -> String:
	var separator_index := unit.find(":")
	if separator_index < 0 || separator_index == unit.length() - 1:
		return unit
	return unit.substr(separator_index + 1)


func _selected_unit_summary(selection: GameSelectionState) -> String:
	var unit := selection.selected_unit()
	if unit.is_empty():
		return "none"

	return "%s hp:%s/%s team:%s" % [
		unit.get("display_name", unit.get("kind", "unit")),
		unit.get("health", 0),
		unit.get("max_health", 0),
		unit.get("team", 0),
	]


func _movement_command_summary(selection: GameSelectionState) -> String:
	var moving_count := selection.moving_unit_count()
	if moving_count == 0:
		return "none"
	return "moving:%s" % moving_count


func _production_command_summary(selection: GameSelectionState) -> String:
	var queue := selection.selected_unit_production_queue()
	if !queue.is_empty() && typeof(queue[0]) == TYPE_DICTIONARY:
		var entry: Dictionary = queue[0]
		return "%s %.1fs" % [
			_short_unit_name(str(entry.get("display_name", entry.get("unit", "unit")))),
			float(entry.get("remaining_seconds", 0.0)),
		]

	var build_option := selection.selected_unit_primary_build_option()
	if build_option.is_empty():
		return "none"

	var cost_parts := PackedStringArray()
	for amount_value in FrontendFrame.array(build_option, "cost"):
		if typeof(amount_value) != TYPE_DICTIONARY:
			continue
		var amount: Dictionary = amount_value
		cost_parts.append("%s=%s" % [
			_short_resource_name(str(amount.get("resource", "unknown"))),
			amount.get("amount", 0),
		])

	var cost_summary := "free"
	if !cost_parts.is_empty():
		cost_summary = " ".join(cost_parts)
	return "%s %.1fs %s" % [
		_short_unit_name(str(build_option.get("display_name", build_option.get("unit", "unit")))),
		float(build_option.get("build_time_seconds", 0.0)),
		cost_summary,
	]


func _command_lifecycle_summary(commands: Dictionary) -> String:
	var result_status := str(commands.get("last_result_status", ""))
	var rejected_reason := str(commands.get("last_rejected_reason", ""))
	var replay_summary := _replay_summary(commands)
	if result_status == "rejected" && rejected_reason != "":
		return "pending:%s ack:%s result:%s rejected:%s %s %s %s" % [
			commands.get("pending_count", 0),
			commands.get("acknowledged_count", 0),
			result_status,
			rejected_reason,
			replay_summary,
			_reconciliation_summary(commands),
			_prediction_history_summary(commands),
		]
	return "pending:%s ack:%s result:%s applied:%s/%s %s %s %s" % [
		commands.get("pending_count", 0),
		commands.get("acknowledged_count", 0),
		result_status,
		commands.get("last_applied_command_id", 0),
		commands.get("last_applied_sequence", 0),
		replay_summary,
		_reconciliation_summary(commands),
		_prediction_history_summary(commands),
	]


func _replay_summary(commands: Dictionary) -> String:
	var replay_count := int(commands.get("replay_command_count", 0))
	if replay_count == 0:
		return "replay:none"

	return "replay:%s base:%s units:%s seq:%s-%s" % [
		replay_count,
		commands.get("replay_base_server_tick", 0),
		commands.get("replay_base_unit_count", 0),
		commands.get("replay_first_sequence", 0),
		commands.get("replay_last_sequence", 0),
	]


func _lightyear_prediction_summary(commands: Dictionary) -> String:
	var predicted_count := int(commands.get("lightyear_predicted_unit_count", 0))
	var replicated_count := int(commands.get("replicated_unit_count", 0))
	if replicated_count == 0:
		return "ly:none"

	var predicted_ids := PackedStringArray()
	for unit_value in FrontendFrame.array(commands, "replicated_units"):
		if typeof(unit_value) != TYPE_DICTIONARY:
			continue
		var unit: Dictionary = unit_value
		if bool(unit.get("is_lightyear_predicted", false)):
			predicted_ids.append(str(unit.get("unit_id", 0)))

	if predicted_ids.is_empty():
		return "ly:%s/%s ids:none" % [predicted_count, replicated_count]
	return "ly:%s/%s ids:%s" % [predicted_count, replicated_count, ",".join(predicted_ids)]


func _reconciliation_summary(commands: Dictionary) -> String:
	var reconciled_count := int(commands.get("reconciled_command_count", 0))
	var mismatch_count := int(commands.get("reconciliation_mismatch_count", 0))
	var status := str(commands.get("last_reconciliation_status", ""))
	if reconciled_count == 0 && status.is_empty():
		return "rec:none"

	var command_id := int(commands.get("last_reconciled_command_id", 0))
	var sequence := int(commands.get("last_reconciled_sequence", 0))
	var round_trip_ticks := int(commands.get("last_reconciliation_round_trip_ticks", 0))
	var target_error := float(commands.get("last_reconciliation_target_error", 0.0))
	var position_error := float(commands.get("last_reconciliation_position_error", 0.0))
	var correction := str(commands.get("last_reconciliation_correction", ""))
	var error := str(commands.get("last_reconciliation_error", ""))
	if !error.is_empty():
		return "rec:%s/%s last:%s/%s status:%s rt:%s corr:%s pos_err:%.2f error:%s" % [
			reconciled_count,
			mismatch_count,
			command_id,
			sequence,
			status,
			round_trip_ticks,
			correction,
			position_error,
			error,
		]
	return "rec:%s/%s last:%s/%s status:%s rt:%s corr:%s target_err:%.2f pos_err:%.2f" % [
		reconciled_count,
		mismatch_count,
		command_id,
		sequence,
		status,
		round_trip_ticks,
		correction,
		target_error,
		position_error,
	]


func _prediction_history_summary(commands: Dictionary) -> String:
	var history_count := int(commands.get("prediction_history_count", 0))
	if history_count == 0:
		return "pred:none"

	var history := FrontendFrame.array(commands, "prediction_history")
	if !history.is_empty():
		var entries := PackedStringArray()
		for entry_value in history:
			if typeof(entry_value) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_value
			entries.append("#%s/%s u:%s err:%.2f corr:%s" % [
				entry.get("command_id", 0),
				entry.get("sequence", 0),
				entry.get("entity_id", 0),
				float(entry.get("position_error", 0.0)),
				str(entry.get("correction", "")),
			])
		if !entries.is_empty():
			return "pred:%s recent:%s" % [history_count, " | ".join(entries)]

	var command_id := int(commands.get("last_prediction_command_id", 0))
	var sequence := int(commands.get("last_prediction_sequence", 0))
	var entity_id := int(commands.get("last_prediction_entity_id", 0))
	var predicted := Vector2(
		float(commands.get("last_prediction_x", 0.0)),
		float(commands.get("last_prediction_y", 0.0))
	)
	var authoritative := Vector2(
		float(commands.get("last_prediction_authoritative_x", 0.0)),
		float(commands.get("last_prediction_authoritative_y", 0.0))
	)
	var position_error := float(commands.get("last_prediction_position_error", 0.0))
	var correction := str(commands.get("last_prediction_correction", ""))
	return "pred:%s last:%s/%s unit:%s p:(%.1f,%.1f) a:(%.1f,%.1f) err:%.2f corr:%s" % [
		history_count,
		command_id,
		sequence,
		entity_id,
		predicted.x,
		predicted.y,
		authoritative.x,
		authoritative.y,
		position_error,
		correction,
	]
