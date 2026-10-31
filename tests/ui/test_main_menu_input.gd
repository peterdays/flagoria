extends "res://tests/helpers/test_helpers.gd"
## Main menu input without log spam.


func _test_main_menu_input_no_log_spam() -> int:
	## Unhandled input on the main menu must not log InputMap errors (the menu
	## checks a "quit" action that is not mapped). Runs tests/menu_input_probe.gd
	## in a separate headless process, because engine errors cannot be read back
	## in-process. --quit-after bounds the run.
	print("-- test_main_menu_input_no_log_spam")
	var output := []
	var code := OS.execute(
		OS.get_executable_path(),
		[
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--quit-after", "600", "--script", "res://tests/menu_input_probe.gd",
		],
		output,
		true
	)
	var log_text: String = "".join(output)
	var fail := 0
	if code != 0 or not log_text.contains("MENU_INPUT_PROBE_OK"):
		printerr("FAIL main_menu_input_no_log_spam probe exit=%s" % code)
		fail += 1
	var errors := 0
	for line in log_text.split("\n"):
		if line.contains("InputMap action"):
			errors += 1
	if errors > 0:
		printerr("FAIL main_menu_input_no_log_spam: %s InputMap errors in the log" % errors)
		fail += 1
	if fail == 0:
		print("PASS test_main_menu_input_no_log_spam")
	return fail
