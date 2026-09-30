class_name GameTypes
extends RefCounted
## Shared value types passed across system boundaries (EventBus payloads,
## SaveManager records, ContentDB lookups).
##
## Kept in one dependency-free file so any module can reference them without
## creating import cycles.


## Result of a single level attempt. Produced by LevelRunner, consumed by the
## results screen, the ranking system and the save manager.
class LevelResult extends RefCounted:
	var level_id: String = ""
	var zone_id: String = ""
	var attempt_time: float = 0.0
	var deaths: int = 0
	var collectibles_collected: int = 0
	var collectibles_total: int = 0
	var enemies_defeated: int = 0
	var score: int = 0
	var secrets_found: int = 0
	var secrets_total: int = 0
	var completed: bool = false
	var best_time: float = -1.0
	var best_score: int = -1
	var is_new_time_record: bool = false
	var is_new_score_record: bool = false
	var is_new_rank_record: bool = false
	var powers_used: PackedStringArray = PackedStringArray()
	var damage_taken: int = 0

	func completion_ratio() -> float:
		if collectibles_total <= 0:
			return 1.0
		return float(collectibles_collected) / float(collectibles_total)

	func secret_ratio() -> float:
		if secrets_total <= 0:
			return 1.0
		return float(secrets_found) / float(secrets_total)

	## Stable human-readable time, matching the HUD format MM:SS.cc
	func formatted_time() -> String:
		return Fmt.time(self.attempt_time)

	static func from_dict(data: Dictionary) -> LevelResult:
		var result := LevelResult.new()
		result.level_id = String(data.get("level_id", ""))
		result.zone_id = String(data.get("zone_id", ""))
		result.attempt_time = float(data.get("attempt_time", 0.0))
		result.deaths = int(data.get("deaths", 0))
		result.collectibles_collected = int(data.get("collectibles_collected", 0))
		result.collectibles_total = int(data.get("collectibles_total", 0))
		result.enemies_defeated = int(data.get("enemies_defeated", 0))
		result.score = int(data.get("score", 0))
		result.secrets_found = int(data.get("secrets_found", 0))
		result.secrets_total = int(data.get("secrets_total", 0))
		result.completed = bool(data.get("completed", false))
		result.best_time = float(data.get("best_time", -1.0))
		result.best_score = int(data.get("best_score", -1))
		return result

	func to_dict() -> Dictionary:
		return {
			"level_id": level_id,
			"zone_id": zone_id,
			"attempt_time": attempt_time,
			"deaths": deaths,
			"collectibles_collected": collectibles_collected,
			"collectibles_total": collectibles_total,
			"enemies_defeated": enemies_defeated,
			"score": score,
			"secrets_found": secrets_found,
			"secrets_total": secrets_total,
			"completed": completed,
			"best_time": best_time,
			"best_score": best_score,
		}


## Quality tier awarded at the end of a level.
enum Rank { D = 0, C = 1, B = 2, A = 3, S = 4 }


## Coarse difficulty label attached to content for progression balancing.
enum Difficulty { EASY, MODERATE, HARD, VERY_HARD, CHALLENGE }


## How a level is meant to be played. Drives mode-specific rules and HUD copy.
enum LevelKind {
	STANDARD,      ## Classic run: reach the goal.
	TIME_ATTACK,   ## Minimum time, generous checkpoints, leaderboard focus.
	CHALLENGE,     ## Explicit modifier set declared by the level data.
	HUNT,          ## A pursuer hunts the player; survive/escape.
	SURVIVAL,     ## Hold out for a duration.
	SCORE,         ## Score attack, no strict time pressure.
	PRECISION,     ## Deliberately tight jumps, low tolerance.
}


## Runtime state of the player, consumed by the animator and audio.
enum PlayerState {
	IDLE, RUN, SPRINT, JUMP, FALL, DASH, ATTACK, ATTACK_AIR, HURT, DEAD, VICTORY, WALL_SLIDE
}


## How the player is currently bound to an enemy interaction, if at all.
enum CombatState { FREE, ATTACKING, ATTACKING_AIR, DASHING, HURT, DEAD }


## Persisted per-level record.
class LevelRecord extends RefCounted:
	var level_id: String = ""
	var completed: bool = false
	var times: PackedFloat32Array = PackedFloat32Array()  ## every completion, best last
	var best_time: float = -1.0
	var best_score: int = -1
	var best_rank: int = -1
	var stars_collected: PackedStringArray = PackedStringArray()
	var secrets_found: PackedStringArray = PackedStringArray()
	var deaths: int = 0
	var attempts: int = 0
	var challenge_cleared: bool = false

	func to_dict() -> Dictionary:
		var time_list: Array = []
		for t in self.times:
			time_list.append(t)
		return {
			"level_id": level_id,
			"completed": completed,
			"times": time_list,
			"best_time": best_time,
			"best_score": best_score,
			"best_rank": best_rank,
			"stars_collected": Array(self.stars_collected),
			"secrets_found": Array(self.secrets_found),
			"deaths": deaths,
			"attempts": attempts,
			"challenge_cleared": challenge_cleared,
		}

	static func from_dict(data: Dictionary) -> LevelRecord:
		var record := LevelRecord.new()
		record.level_id = String(data.get("level_id", ""))
		record.completed = bool(data.get("completed", false))
		for t in data.get("times", []):
			record.times.append(float(t))
		record.best_time = float(data.get("best_time", -1.0))
		record.best_score = int(data.get("best_score", -1))
		record.best_rank = int(data.get("best_rank", -1))
		for s in data.get("stars_collected", []):
			record.stars_collected.append(String(s))
		for s in data.get("secrets_found", []):
			record.secrets_found.append(String(s))
		record.deaths = int(data.get("deaths", 0))
		record.attempts = int(data.get("attempts", 0))
		record.challenge_cleared = bool(data.get("challenge_cleared", false))
		return record
