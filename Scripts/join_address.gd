extends RefCounted
## Join address field: a hostname or an IPv4 address, with an optional :port.
## The default port matches flagoria_main.gd PORT. A form with more than one
## colon (such as ::1) is rejected whole, so it is never split into a host
## and a port.

const DEFAULT_PORT := 9786
const PORT_MIN := 1
const PORT_MAX := 65535

const ERROR_ADDRESS := "Enter a hostname or an IPv4 address, and an optional port from 1 to 65535."
const ERROR_PORT := "Enter a port from 1 to 65535."
const ERROR_UNSUPPORTED := "Addresses with more than one colon are not supported. Enter a hostname or an IPv4 address, and an optional port from 1 to 65535."


static func parse(text: String) -> Dictionary:
	## {ok, host, port, explicit, endpoint, error}. Blank text is localhost
	## on the default port. endpoint is the text Join shows in a failure
	## (the typed address, or "localhost" when the field was blank).
	var trimmed := text.strip_edges()
	var result := {
		"ok": false,
		"host": "",
		"port": DEFAULT_PORT,
		"explicit": false,
		"endpoint": "localhost" if trimmed == "" else trimmed,
		"error": "",
	}
	if trimmed == "":
		result["ok"] = true
		result["host"] = "localhost"
		return result
	if trimmed.count(":") > 1 or trimmed.contains("[") or trimmed.contains("]"):
		result["error"] = ERROR_UNSUPPORTED
		return result
	var host := trimmed
	var port := DEFAULT_PORT
	var explicit := false
	if trimmed.contains(":"):
		var colon := trimmed.find(":")
		host = trimmed.substr(0, colon)
		var port_text := trimmed.substr(colon + 1)
		if host == "" or port_text == "" or not port_text.is_valid_int():
			result["error"] = ERROR_ADDRESS
			return result
		port = port_text.to_int()
		if port < PORT_MIN or port > PORT_MAX:
			result["error"] = ERROR_PORT
			return result
		explicit = true
	if not _hostname_ok(host):
		result["error"] = ERROR_ADDRESS
		return result
	result["ok"] = true
	result["host"] = host
	result["port"] = port
	result["explicit"] = explicit
	result["endpoint"] = trimmed
	return result


static func _hostname_ok(host: String) -> bool:
	## Letters, digits, hyphens and dots: hostname labels or an IPv4 address.
	if host.is_empty() or host.length() > 253:
		return false
	if host.begins_with(".") or host.ends_with("."):
		return false
	for label in host.split("."):
		if label.is_empty() or label.length() > 63:
			return false
		if label.begins_with("-") or label.ends_with("-"):
			return false
		for i in label.length():
			var c := label.unicode_at(i)
			var digit := c >= 48 and c <= 57
			var lower := c >= 97 and c <= 122
			var upper := c >= 65 and c <= 90
			if not (digit or lower or upper or c == 45):
				return false
	return true
