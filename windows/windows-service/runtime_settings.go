package main

// runtimeNetworkSettings keeps logon sync from applying preferences saved for
// the next service start to the currently running core.
func runtimeNetworkSettings(settings map[string]any) map[string]any {
	current := make(map[string]any, len(settings))
	for key, value := range settings {
		current[key] = value
	}
	if mode, ok := settings["runningNetworkMode"].(string); ok && (mode == "tun" || mode == "proxy") {
		current["networkMode"] = mode
	}
	if bypass, ok := settings["runningBypassLanEnabled"].(bool); ok {
		current["bypassLanEnabled"] = bypass
	}
	return current
}
