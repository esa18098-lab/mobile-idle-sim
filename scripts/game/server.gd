extends RefCounted
## Server hooks. Empty stubs until the galaxy stage, so the calls already sit
## where they belong: the install ping, and the sanity check on long absences.

## Called once per install. Later: register the install and fetch server time.
static func ping_install() -> Dictionary:
	return {"ok": true, "server_unix": -1.0}


## Called before offline catch-up. Later: the server confirms the elapsed time
## (catches clock changes) and caps it. Now: trusts the device, never negative.
static func confirm_elapsed(_saved_unix: float, now_unix: float, claimed_seconds: float) -> float:
	return maxf(0.0, claimed_seconds)
