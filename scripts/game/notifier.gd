extends RefCounted
## Local notifications. Godot has no built-in Android notifications, so this
## schedules through a plugin when one is installed and does nothing otherwise.
## The game decides what and when (Sim.upcoming_notifications); this only delivers.
##
## To enable: install an Android local-notification plugin in the editor and
## make PLUGIN_SINGLETON match its singleton name and methods below.

const PLUGIN_SINGLETON := "LocalNotification"

static var last_scheduled: Array = []   ## for tests and the dev menu


## `items`: [{at_unix, text}]. Replaces anything scheduled before.
static func schedule(items: Array) -> void:
	last_scheduled = items
	if not Engine.has_singleton(PLUGIN_SINGLETON):
		return
	var plugin := Engine.get_singleton(PLUGIN_SINGLETON)
	plugin.call("cancel_all")
	for i in items.size():
		var delay := int(items[i].at_unix - Time.get_unix_time_from_system())
		if delay > 0:
			plugin.call("show", "Mobile Idle Sim", items[i].text, delay, i)


static func cancel_all() -> void:
	last_scheduled = []
	if Engine.has_singleton(PLUGIN_SINGLETON):
		Engine.get_singleton(PLUGIN_SINGLETON).call("cancel_all")
