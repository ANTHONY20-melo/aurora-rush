class_name Fmt
extends RefCounted
## Pure formatting helpers.
##
## Every string the player sees is produced here so that time, score and
## rank formatting stay identical across HUD, results screen, map, pause
## menu and save file. One place to change the format, one place to test it.


## Seconds -> "MM:SS.cc" (the in-game timer format).
## Always two digit minutes, always hundredths: 95.2 -> "01:35.20"
##
## Hundredths are derived from a single rounded integer count of hundredths,
## never from fmod of the fractional part. Doing it the naive way loses a digit
## to float error (3599.99 renders as 59:59.98), which the timer would then
## show on every single run.
static func time(seconds: float) -> String:
	var safe: float = maxf(0.0, seconds)
	var total_hundredths: int = int(round(safe * 100.0))
	var hundredths: int = total_hundredths % 100
	var total_seconds: int = total_hundredths / 100
	var secs: int = total_seconds % 60
	var minutes: int = total_seconds / 60
	return "%02d:%02d.%02d" % [minutes, secs, hundredths]


## Seconds -> "MM:SS" (compact, for menus and lists).
static func time_short(seconds: float) -> String:
	var safe: float = maxf(0.0, seconds)
	var total_int: int = int(floor(safe))
	return "%02d:%02d" % [total_int / 60, total_int % 60]


## Score -> "48.520" (thousands separated with a dot, pt-BR convention).
static func score(value: int) -> String:
	var negative: bool = value < 0
	var digits: String = str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "." + out
	return ("-" + out) if negative else out


## Float ratio in 0..1 -> "87%" style, for completion meters.
static func percent(ratio: float, decimals: int = 0) -> String:
	return String.num(ratio * 100.0, decimals) + "%"


## Multiplier -> "x3.5"
static func multiplier(value: float) -> String:
	return "x" + String.num(value, 1)


## Duration in seconds -> "1.5s"
static func duration(seconds: float) -> String:
	return String.num(seconds, 1) + "s"


## Seconds -> "2:30" / "45s" for achievement timestamps.
static func ago(seconds: float) -> String:
	if seconds < 60.0:
		return "%ds" % int(seconds)
	if seconds < 3600.0:
		return "%dm" % (int(seconds) / 60)
	return "%dh" % (int(seconds) / 3600)
