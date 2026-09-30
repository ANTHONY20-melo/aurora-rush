class_name Synth
extends RefCounted
## Runtime audio synthesis.
##
## The project ships no audio files. Every effect and music track is rendered
## into an AudioStreamWAV from a small JSON recipe, which keeps the repository
## asset-free and legally clean while still producing real, layered audio.
##
## A recipe is data:
##   {
##     "type": "tone" | "noise" | "metal" | "music",
##     "wave": "sine" | "square" | "saw" | "triangle",
##     "freq_start": 440, "freq_end": 880,   // sweep, in Hz
##     "duration": 0.2,                       // seconds
##     "attack": 0.005, "decay": 0.12,        // seconds
##     "gain": 0.7, "noise": 0.0,             // noise mix 0..1
##     "pitch_drop": 0.0                      // extra downward sweep multiplier
##   }

const NOTE_OFFSETS := {
	"C": -9, "C#": -8, "Db": -8, "D": -7, "D#": -6, "Eb": -6, "E": -5,
	"F": -4, "F#": -3, "Gb": -3, "G": -2, "G#": -1, "Ab": -1, "A": 0,
	"A#": 1, "Bb": 1, "B": 2,
}

## Semitone -> frequency, e.g. A4 = 440 Hz.
static func note_frequency(note: String) -> float:
	var text := note.strip_edges().to_upper()
	var octave_text := ""
	var name_text := text
	if text.length() > 1 and text.substr(text.length() - 1).is_valid_int():
		octave_text = text.substr(text.length() - 1)
		name_text = text.substr(0, text.length() - 1)
	if not NOTE_OFFSETS.has(name_text):
		return 440.0
	var semitones: int = NOTE_OFFSETS[name_text] + (int(octave_text) - 4) * 12
	return 440.0 * pow(2.0, float(semitones) / 12.0)


## Frequency for a semitone offset from A4.
static func semitone_frequency(offset: int) -> float:
	return 440.0 * pow(2.0, float(offset) / 12.0)


static func _oscillator(wave: String, phase: float) -> float:
	match wave:
		"square":
			return 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
		"saw":
			return 2.0 * fmod(phase, 1.0) - 1.0
		"triangle":
			var t := fmod(phase, 1.0)
			return 4.0 * absf(t - 0.5) - 1.0
		_:
			return sin(phase * TAU)


## Amplitude envelope: fast attack, exponential decay to silence.
static func _envelope(t: float, duration: float, attack: float, decay: float) -> float:
	if attack > 0.0 and t < attack:
		return t / attack
	var release_start: float = maxf(attack, duration - decay)
	if t <= release_start:
		return 1.0
	if decay <= 0.0:
		return 1.0
	var progress: float = (t - release_start) / decay
	return clampf(1.0 - progress, 0.0, 1.0)


## Fast deterministic noise. A seeded generator keeps sounds identical between
## runs, which matters for reproducible tests.
static func _noise_sample(index: int, seed_value: int) -> float:
	var hashed: int = (index * 1103515245 + seed_value * 12345) & 0x7FFFFFFF
	hashed = (hashed ^ (hashed >> 13)) * 1274126177 & 0x7FFFFFFF
	return float(hashed % 20001) / 10000.0 - 1.0


static func _to_stream(samples: PackedFloat32Array, sample_rate: int, loop: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value: float = clampf(samples[i], -1.0, 1.0)
		var encoded := int(value * 32767.0)
		bytes.encode_s16(i * 2, encoded)
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


# --- SFX --------------------------------------------------------------------

## Render a one-shot effect from a recipe dictionary.
static func sfx_from_definition(definition: Variant, sample_rate: int = 22050) -> AudioStreamWAV:
	if typeof(definition) != TYPE_DICTIONARY:
		return AudioStreamWAV.new()
	var def: Dictionary = definition
	var duration: float = maxf(0.01, float(def.get("duration", 0.2)))
	var count: int = int(duration * sample_rate)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var wave: String = String(def.get("wave", "sine"))
	var freq_start: float = float(def.get("freq_start", 440.0))
	var freq_end: float = float(def.get("freq_end", freq_start))
	var freq_start_note: String = String(def.get("freq_start_note", ""))
	var freq_end_note: String = String(def.get("freq_end_note", ""))
	if not freq_start_note.is_empty():
		freq_start = note_frequency(freq_start_note)
	if not freq_end_note.is_empty():
		freq_end = note_frequency(freq_end_note)
	var pitch_drop: float = float(def.get("pitch_drop", 0.0))
	var attack: float = maxf(0.001, float(def.get("attack", duration * 0.05)))
	var decay: float = maxf(0.0, float(def.get("decay", duration * 0.8)))
	var gain: float = float(def.get("gain", 0.6))
	var noise_mix: float = clampf(float(def.get("noise", 0.0)), 0.0, 1.0)
	var seed_value: int = int(def.get("seed", 1))
	var vibrato: float = float(def.get("vibrato", 0.0))
	var vibrato_hz: float = float(def.get("vibrato_hz", 8.0))

	var phase := 0.0
	for i in count:
		var t := float(i) / float(sample_rate)
		var progress: float = t / duration
		var freq: float = lerpf(freq_start, freq_end, progress)
		if pitch_drop != 0.0:
			freq *= pow(1.0 - pitch_drop, progress)
		if vibrato > 0.0:
			freq *= 1.0 + vibrato * sin(t * TAU * vibrato_hz)
		phase += freq / float(sample_rate)
		var tone: float = _oscillator(wave, phase)
		var sample: float = tone * (1.0 - noise_mix) + _noise_sample(i, seed_value) * noise_mix
		samples[i] = sample * _envelope(t, duration, attack, decay) * gain
	return _to_stream(samples, sample_rate, false)


# --- Music ------------------------------------------------------------------

const SCALES := {
	"minor":          [0, 2, 3, 5, 7, 8, 10],
	"major":          [0, 2, 4, 5, 7, 9, 11],
	"minor_pentatonic":[0, 3, 5, 7, 10],
	"major_pentatonic":[0, 2, 4, 7, 9],
	"phrygian":       [0, 1, 3, 5, 7, 8, 10],
	"dorian":         [0, 2, 3, 5, 7, 9, 10],
	"whole_tone":     [0, 2, 4, 6, 8, 10],
	"chromatic":      [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}

## Render a seamless looping music bed: bass line, arpeggio lead, and a
## percussion layer, all derived from one scale and tempo.
static func music_from_definition(definition: Variant, sample_rate: int = 22050) -> AudioStreamWAV:
	if typeof(definition) != TYPE_DICTIONARY:
		return AudioStreamWAV.new()
	var def: Dictionary = definition
	var bpm: float = maxf(40.0, float(def.get("bpm", 130.0)))
	var beats: int = maxi(1, int(def.get("beats", 16)))
	var root_note: String = String(def.get("root", "A2"))
	var scale_name: String = String(def.get("scale", "minor_pentatonic"))
	var scale: Array = SCALES.get(scale_name, SCALES["minor_pentatonic"])

	var beat_seconds := 60.0 / bpm
	var total_seconds: float = beat_seconds * float(beats)
	var count: int = int(total_seconds * sample_rate)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var bass_wave: String = String(def.get("bass_wave", "triangle"))
	var lead_wave: String = String(def.get("lead_wave", "square"))
	var root_freq: float = note_frequency(root_note)

	var bass_gain: float = float(def.get("bass_gain", 0.32))
	var lead_gain: float = float(def.get("lead_gain", 0.20))
	var drum_gain: float = float(def.get("drum_gain", 0.22))
	var arp_pattern: Array = def.get("arp", [0, 2, 4, 2, 5, 4, 2, 0])
	var bass_pattern: Array = def.get("bass", [0, 0, 3, 3, 5, 5, 3, 3])
	var lead_enabled: bool = bool(def.get("lead", true))
	var drums_enabled: bool = bool(def.get("drums", true))
	var swing: float = float(def.get("swing", 0.0))
	var noise_seed: int = int(def.get("seed", 7))

	var step_duration: float = beat_seconds / 2.0   # eighth notes
	var steps: int = maxi(1, int(round(total_seconds / step_duration)))

	var bass_phase := 0.0
	var lead_phase := 0.0
	var last_step := -1
	var last_bass_deg := 0
	var last_lead_deg := 0

	for i in count:
		var t := float(i) / float(sample_rate)
		var step := int(floor(t / step_duration))
		if step != last_step:
			last_step = step
			last_bass_deg = int(bass_pattern[step % bass_pattern.size()]) % scale.size()
			last_lead_deg = int(arp_pattern[step % arp_pattern.size()]) % scale.size()
			# Retrigger phases for a percussive, plucky envelope.
			bass_phase = 0.0
			lead_phase = 0.0

		var step_time: float = float(step) * step_duration
		var into_step: float = t - step_time
		# Optional swing pushes every off-beath eighth later.
		var swung_step_duration := step_duration * (1.0 + swing if step % 2 == 1 else 1.0 - swing)

		var bass_freq: float = root_freq * pow(2.0, float(scale[last_bass_deg] * 12) / 12.0)
		bass_phase += bass_freq / float(sample_rate)
		var bass_env: float = _envelope(into_step, swung_step_duration,
			step_duration * 0.08, swung_step_duration * 0.7)
		var sample: float = _oscillator(bass_wave, bass_phase) * bass_env * bass_gain

		if lead_enabled:
			var lead_freq: float = root_freq * 4.0 \
				* pow(2.0, float(scale[last_lead_deg] * 12) / 12.0)
			lead_phase += lead_freq / float(sample_rate)
			var lead_env: float = _envelope(into_step, swung_step_duration,
				step_duration * 0.12, swung_step_duration * 0.85)
			sample += _oscillator(lead_wave, lead_phase) * lead_env * lead_gain

		if drums_enabled:
			sample += _drum_sample(into_step, beat_seconds, step, noise_seed) * drum_gain

		# Crossfade the very edges so the loop point is inaudible.
		var edge: float = minf(t, total_seconds - t)
		var fade: float = clampf(edge / 0.05, 0.0, 1.0)
		samples[i] = sample * fade

	return _to_stream(samples, sample_rate, true)


static func _drum_sample(into_step: float, beat_seconds: float, step: int, seed_value: int) -> float:
	var is_downbeat: bool = step % 4 == 0
	var is_offbeat: bool = step % 2 == 1
	if is_downbeat:
		# Kick: pitch-dropping sine.
		var progress: float = clampf(into_step / (beat_seconds * 0.4), 0.0, 1.0)
		var freq: float = lerpf(150.0, 45.0, progress)
		return sin(TAU * freq * into_step) * (1.0 - progress) * 0.9
	if is_offbeat:
		# Snare/hat: filtered noise burst.
		var progress: float = clampf(into_step / (beat_seconds * 0.18), 0.0, 1.0)
		return _noise_sample(int(into_step * 22050.0), seed_value) * (1.0 - progress) * 0.45
	return 0.0
