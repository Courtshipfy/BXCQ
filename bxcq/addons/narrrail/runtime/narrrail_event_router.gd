class_name NarrRailEventRouter
extends RefCounted

signal event_type_handled(event_type: String, payload: Dictionary)
signal event_unhandled(event_type: String, payload: Dictionary)

var _type_handlers: Dictionary = {}

func register_type(event_type: String, handler: Callable) -> void:
	var normalized_type := event_type.strip_edges()
	if normalized_type.is_empty():
		push_error("[NarrRail] Cannot register an empty event type.")
		return
	if not handler.is_valid():
		push_error("[NarrRail] Cannot register invalid handler for event type: %s" % normalized_type)
		return
	_type_handlers[normalized_type] = handler

func unregister_type(event_type: String) -> void:
	_type_handlers.erase(event_type.strip_edges())

func clear() -> void:
	_type_handlers.clear()

func has_type_handler(event_type: String) -> bool:
	return _type_handlers.has(event_type.strip_edges())

func dispatch(payload: Dictionary) -> bool:
	var event_type := String(payload.get("eventType", "")).strip_edges()
	if not event_type.is_empty() and _type_handlers.has(event_type):
		var type_handler: Callable = _type_handlers[event_type]
		if type_handler.is_valid():
			type_handler.call(payload)
			event_type_handled.emit(event_type, payload)
			return true

	event_unhandled.emit(event_type, payload)
	return false
