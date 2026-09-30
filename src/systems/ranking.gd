class_name Ranking
extends RefCounted
## Deterministic rank computation.
##
## Hard rule from the design: ranks are NEVER random and never hidden. The
## formula is a pure function of the run, and every term is surfaced in the
## results screen so the player can see exactly why they got the rank they
## got. Target times come from level content data, so each level is balanced
## against its own par instead of a global constant.

## Time-equivalent cost of a death, in seconds. A death is worse than the
## time it costs you, because it also costs momentum and routing.
const DEATH_PENALTY_SECONDS := 5.0

## Each death beyond the first is progressively cheaper to forgive, so a
## single early mistake in a long level is not fatal to the rank.
const DEATH_PENALTY_DECAY := 0.75

## Bonus per full 10% of collectibles collected, as a fraction of the S time.
const COLLECTIBLE_BONUS_PER_DECILE := 0.022

## Bonus per secret area found, as a fraction of the S time.
const SECRET_BONUS := 0.03

## Score contributes a small nudge so a greedy, risky run can out-rank a
## merely safe one of identical time.
const SCORE_BONUS_PER_10K := 0.008

const SCORE_BONUS_CAP := 0.05

const RANK_ORDER: Array[String] = ["D", "C", "B", "A", "S"]

const DEFAULT_TARGETS := {"s": 45.0, "a": 60.0, "b": 80.0, "c": 105.0, "d": 140.0}


## Target times for a level, validated so the ladder can never be inverted.
## Content data is authored by humans, so it gets defensively normalised here
## instead of producing nonsense ranks.
static func normalized_targets(raw: Dictionary) -> Dictionary:
	var targets := DEFAULT_TARGETS.duplicate()
	for key in targets.keys():
		if raw.has(key):
			targets[key] = maxf(1.0, float(raw[key]))
	# Enforce a strictly increasing ladder: s < a < b < c < d
	var ladder: Array[String] = ["s", "a", "b", "c", "d"]
	for i in range(1, ladder.size()):
		var previous: float = targets[ladder[i - 1]]
		if targets[ladder[i]] <= previous:
			targets[ladder[i]] = previous * 1.25
	return targets


## Time-equivalent penalty a run carries. This is the single number that
## decides the rank, and it is fully explainable.
static func effective_time(result: GameTypes.LevelResult, targets: Dictionary) -> float:
	var ladder := normalized_targets(targets)
	var base: float = maxf(0.0, result.attempt_time)

	# Death penalty with decay.
	var death_cost := 0.0
	var factor := 1.0
	for i in result.deaths:
		if i > 0:
			factor *= DEATH_PENALTY_DECAY
		death_cost += DEATH_PENALTY_SECONDS * factor

	# Collectible bonus, capped so 100% collection cannot trivialise time.
	var completion: float = clampf(result.completion_ratio(), 0.0, 1.0)
	var collectible_bonus: float = completion * 10.0 * COLLECTIBLE_BONUS_PER_DECILE * float(ladder["s"])

	# Secret bonus.
	var secret_ratio: float = clampf(result.secret_ratio(), 0.0, 1.0)
	var secret_bonus: float = secret_ratio * 3.0 * SECRET_BONUS * float(ladder["s"])

	# Score nudge, capped.
	var score_ratio: float = clampf(float(result.score) / 100000.0, 0.0, 1.0)
	var score_bonus: float = minf(SCORE_BONUS_CAP, score_ratio * 10.0 * SCORE_BONUS_PER_10K) * float(ladder["s"])

	return base + death_cost - collectible_bonus - secret_bonus - score_bonus


## The rank for a run. Returns GameTypes.Rank (D=0 .. S=4).
static func compute_rank(result: GameTypes.LevelResult, targets: Dictionary) -> int:
	if not result.completed:
		return GameTypes.Rank.D
	var ladder := normalized_targets(targets)
	var score := effective_time(result, targets)
	# Best (fastest) rank whose threshold the run clears.
	if score <= float(ladder["s"]):
		return GameTypes.Rank.S
	if score <= float(ladder["a"]):
		return GameTypes.Rank.A
	if score <= float(ladder["b"]):
		return GameTypes.Rank.B
	if score <= float(ladder["c"]):
		return GameTypes.Rank.C
	return GameTypes.Rank.D


static func rank_letter(rank: int) -> String:
	if rank < 0 or rank >= RANK_ORDER.size():
		return "D"
	return RANK_ORDER[rank]


## 0..1 completion rating, used for progress bars and the map's star pips.
## 1.0 means the run hit S par or better.
static func rating(result: GameTypes.LevelResult, targets: Dictionary) -> float:
	var ladder := normalized_targets(targets)
	var score := effective_time(result, targets)
	if score <= float(ladder["s"]):
		return 1.0
	var worst: float = maxf(float(ladder["d"]), score)
	return clampf(1.0 - (score - float(ladder["s"])) / (worst - float(ladder["s"])), 0.0, 1.0)


## Per-term breakdown for the results screen. Every number the player sees in
## the rank explanation is produced by this single function.
static func explain(result: GameTypes.LevelResult, targets: Dictionary) -> Dictionary:
	var ladder := normalized_targets(targets)
	var effective := effective_time(result, targets)
	var reached := "D"
	if effective <= float(ladder["s"]):
		reached = "S"
	elif effective <= float(ladder["a"]):
		reached = "A"
	elif effective <= float(ladder["b"]):
		reached = "B"
	elif effective <= float(ladder["c"]):
		reached = "C"

	var next_target := -1.0
	var next_label := ""
	match reached:
		"S": next_target = float(ladder["s"]); next_label = "S"
		"A": next_target = float(ladder["a"]); next_label = "A"
		"B": next_target = float(ladder["b"]); next_label = "B"
		"C": next_target = float(ladder["c"]); next_label = "C"
		_: next_target = float(ladder["d"]); next_label = "D"

	return {
		"raw_time": result.attempt_time,
		"death_penalty": _death_penalty(result.deaths),
		"effective_time": effective,
		"rank": reached,
		"next_rank": next_label,
		"next_target": next_target,
		"deficit": maxf(0.0, effective - next_target) if reached != "S" else 0.0,
		"targets": ladder,
	}


static func _death_penalty(deaths: int) -> float:
	var total := 0.0
	var factor := 1.0
	for i in deaths:
		if i > 0:
			factor *= DEATH_PENALTY_DECAY
		total += DEATH_PENALTY_SECONDS * factor
	return total
