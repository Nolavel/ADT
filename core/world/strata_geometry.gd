# =============================================================================
# strata_geometry.gd — StrataGeometry
# class_name: StrataGeometry  (чистые константы + статические функции, без состояния)
#
# ЕДИНЫЙ ИСТОЧНИК ИСТИНЫ по вертикальной раскладке страт: технические полосы
# (глухие — ни этажей, ни палуб) и играбельные полосы (только внутри них живут
# визуальные этажи и палубы).
#
# Почему отдельный class_name, а не константы в WorldSystems:
#   • WorldSystems — автолоад (extends Node) без class_name; из EditorScript
#     (генераторы блоков) его константы не достать — отсюда исторические дубли
#     STRATA_* в block_library_generator / block_placer с пометкой «править
#     вручную». class_name-глобал доступен и в рантайме, и в редакторных
#     скриптах, поэтому дубли больше не нужны. При правке геометрии мира —
#     правим ТОЛЬКО здесь (и держим синхронно с WorldSystems.STRATA_*).
#
# Границы страт (совпадают с WorldSystems.STRATA_*):
#   Doggerland 0–1000, Manifold 1000–2000, Glare 2000–3200.
# Техполоса = 100 м. У каждой страты она снизу и сверху, КРОМЕ Glare:
#   у Glare техполоса только снизу, верх открыт до потолка мира (3200), сами
#   верхушки башен рваные (обрезаются фактической высотой башни).
# =============================================================================
extends RefCounted
class_name StrataGeometry

const GAMEPLAY_HEIGHT: float = 3200.0
const TECH_BAND:       float = 100.0

## Полные границы страт [низ, верх].
const STRATA_DOGGERLAND: Vector2 = Vector2(0.0,    1000.0)
const STRATA_MANIFOLD:   Vector2 = Vector2(1000.0, 2000.0)
const STRATA_GLARE:      Vector2 = Vector2(2000.0, 3200.0)

const DOGGERLAND: String = "Doggerland"
const MANIFOLD:   String = "Manifold"
const GLARE:      String = "Glare"


## Играбельная полоса страты [низ, верх] — где разрешены этажи и палубы.
## Doggerland [100,900], Manifold [1100,1900], Glare [2100, верх башни].
## У Glare верх играбельной полосы НЕ фиксирован геометрией страты — он
## обрезается фактической высотой конкретной башни (tower_top), поэтому
## передаётся аргументом. Для остальных страт tower_top игнорируется.
static func playable_band(stratum: String, tower_top: float = GAMEPLAY_HEIGHT) -> Vector2:
	match stratum:
		DOGGERLAND:
			return Vector2(STRATA_DOGGERLAND.x + TECH_BAND, STRATA_DOGGERLAND.y - TECH_BAND)
		MANIFOLD:
			return Vector2(STRATA_MANIFOLD.x + TECH_BAND, STRATA_MANIFOLD.y - TECH_BAND)
		GLARE:
			# Только нижняя техполоса; верх — по высоте башни, но не выше потолка мира.
			return Vector2(STRATA_GLARE.x + TECH_BAND, minf(tower_top, GAMEPLAY_HEIGHT))
		_:
			push_error("[StrataGeometry] Неизвестная страта: %s" % stratum)
			return Vector2.ZERO


## Список страт, которых достаёт башня высотой height (снизу вверх).
static func strata_reached(height: float) -> Array[String]:
	var result: Array[String] = [DOGGERLAND]
	if height > STRATA_DOGGERLAND.y:
		result.append(MANIFOLD)
	if height > STRATA_MANIFOLD.y:
		result.append(GLARE)
	return result


## Паттерн ритма привязан к страте — глобальная подпись мира.
## Doggerland → A (варрен), Manifold → B (утилитарная), Glare → C (атриум).
static func pattern_key(stratum: String) -> String:
	match stratum:
		DOGGERLAND: return "A"
		MANIFOLD:   return "B"
		GLARE:      return "C"
		_:          return "A"
