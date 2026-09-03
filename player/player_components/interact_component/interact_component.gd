extends Node3D
## Компонент игрока InteractComponent
class_name InteractComponent

## Прототип механики при обнаружение обьекта 1) выводим инфу о нем и кем он является
## Items / Button / Door / другие
## 2) если PickupItem c "can_carry" цепляем его в пространство PickupSlot (оно будет впереди игрока)
## если обьект "can_carry"/ «can_store_in_inventory»/ «can_throw»
## то можно его сложить в инвентарь из PickupSlot или выкинуть если "can_throw"

##Подбираемые и переносимые объекты:
##PickupItem﻿ (можно параметром отмечать «can_carry», «can_store_in_inventory», «can_throw»).

@onready var player: CharacterBody3D = get_parent() ## cсылка на игрока
@onready var dymamic_cursor_ui: MouseCursorUI = $"../DynamicCursorUI"
## в случае если захотим визуально что-то менять с курсором при интерактивности
@onready var player_focus_cast: ShapeCast3D = $PlayerFocusCast
## Этот шейпкаст служит для обнаружения интерактивных обьектов в фокусе
## перед игроком по группе "Interactable" и по слою "Interactable"

@onready var pickup_slot: Node3D = $"../PickupSlot"
## прототип-набросок куда цепляется предмет (потом можно сделать - аттачить к Bone руки)

@onready var debug_label: Label = $Label
## через него видем какой обьект в фокусе, name, его возможности, количество

## What the player is aimed at, and whether they can already reach it.
## `object` is null when nothing is targeted.
##
## `in_reach` is the SAME question try_interact() asks before deciding whether
## to walk: distance <= pickup_distance. Deliberately not "which tier found
## it" — PlayerFocusCast reaches about 1.8 m while pickup_distance is 0.9, so
## a focus-cast hit can still need an approach, and a display keyed to the
## tier would say "in reach" where the character is about to walk. Sharing the
## expression is what keeps the two from drifting apart.
##
## Emitted on a change of EITHER value, so walking up to an already-chosen
## object is an edge too.
signal interact_target_changed(object: InteractableObject, in_reach: bool)

@export_group("Intent")
## Radius of the INTENT search, metres — the second detection tier, used when
## PlayerFocusCast finds nothing.
##
## The focus cast is a capsule reaching ~1.8 m forward with radius 0.4, and it
## has to physically overlap the object's own Area. That makes pickup a
## positioning exercise: the player lines the character up for the UI rather
## than for the fiction. This radius is the answer to "what is the player
## plausibly reaching for", and F acts on it — see try_interact().
##
## Deliberately on the CHARACTER, not on each item's Area. The Area is what an
## object offers to be found by; growing every future item's box to 5 m to be
## reachable is the per-item spelling of a rule that belongs here once.
@export var intent_radius: float = 2.5
## Full angular width of the intent cone, degrees, centred on facing. 240°
## means anything except a rear arc — generous enough that aiming is not a
## skill, tight enough that F never turns the character round to grab
## something behind them.
@export var intent_angle_deg: float = 240.0

@export_group("Approach")
## How close the character walks before acting. Also the threshold that
## decides whether F acts immediately or walks first.
@export var pickup_distance: float = 0.9
## Seconds before an approach gives up. Not optional: this project has no
## NavigationRegion3D (NavigationComponent logs it at every boot and falls
## back to a straight line), so a walk into geometry would otherwise never
## end.
@export var approach_timeout: float = 4.0

var current_interactable: InteractableObject = null
## The target as of the last interact_target_changed emit. Declared here from
## the start and never actually written until that signal existed; it is what
## makes the signal an edge instead of a per-frame report.
var previous_interactable: InteractableObject = null
var carried_item: InteractableObject = null
var closest_distance: float = INF
var detected_count: int = 0

## The object F was pressed on, while the character is still walking to it.
## Null whenever no approach is in flight — which is also how every abort
## path (timeout, the player taking over, the object being freed) reports
## itself: it clears this and nothing else.
## Last value emitted through interact_target_changed, so the signal stays an
## edge rather than a per-frame report.
var _last_in_reach: bool = false
## Instance id of the target at that same emit, 0 for none.
##
## An id and NOT the reference, because in Godot a freed Object compares
## EQUAL to null: picking something up frees it, so "the thing we were
## pointing at is gone" read as "nothing changed" and left the candidate
## decal sitting on an empty patch of ground. Only visible when the pickup
## happened without in_reach also flipping, which is exactly what an
## auto-approach does.
var _last_target_id: int = 0

var _pending_interactable: InteractableObject = null
var _approach_elapsed: float = 0.0
## The body stopped while an approach was pending. NOT itself a cancel: the
## path ending normally emits the same signal as the player interrupting, and
## _update_approach() is the only place that can tell them apart — by asking
## whether we are in reach. Deciding here instead silently swallowed pickups
## whose walk finished a few centimetres outside the arrival radius.
var _approach_body_stopped: bool = false

## Screen prompt, resolved by group and cached. Null is a normal state, not
## an error: the widget is decoration over an interaction that has to keep
## working either way, so every call site null-checks and nothing here waits
## for it. Same relationship ComicEffectSystem consumers have with the words.
var _hold_prompt: HoldPrompt = null

func _ready() -> void:
	## вкл допом программно
	player_focus_cast.enabled = true
	player_focus_cast.collision_mask = CollisionLayers.INTERACTABLES
	player_focus_cast.collide_with_areas = true
	player_focus_cast.collide_with_bodies = true
	
	## Проверка debug_label
	if debug_label:
		debug_label.visible = true
		debug_label.text = "🔍 Поиск объектов..."
	else:
		print("❌ ОШИБКА: debug_label не найден!")

	## Компонент сам решает, актуален ли он сейчас (только ON_FOOT) —
	## InputSystems лишь сообщает о нажатии, ни о чём не спрашивая.
	InputSystems.interact_pressed.connect(_on_interact_pressed)

	## The player giving a movement order of their own abandons an approach.
	## In ISOMETRIC a left click calls stop_moving(); in TPS player.gd clears
	## the scripted path the moment WASD is touched. Both end in this signal,
	## so one subscription covers both views.
	if player != null and player.has_signal(&"movement_stopped"):
		player.movement_stopped.connect(_on_player_movement_stopped)

func _on_interact_pressed() -> void:
	if PlayerState.mode != PlayerState.Mode.ON_FOOT:
		return
	try_interact()
	
func _physics_process(delta: float) -> void:
	detect_interactable()
	_update_approach(delta)
	_update_affordance()
	update_debug_label()
	
func detect_interactable() -> void:
	## A picked-up object is freed, and in Godot a freed Object compares EQUAL
	## to null. So "new is null, current is freed" reads as "nothing changed"
	## further down, the reference sticks forever, and every consumer is handed
	## a dead object that also claims to be null. Normalise first and the rest
	## of this function — including on_lost_by_player() — sees an honest null.
	if not is_instance_valid(current_interactable):
		current_interactable = null
	if not is_instance_valid(previous_interactable):
		previous_interactable = null

	var new_interactable: InteractableObject = null  # ✅ Всегда null по умолчанию
	closest_distance = INF
	detected_count = 0
	
	## Обнаружение коллайдеров
	if player_focus_cast.is_colliding():
		var collision_count = player_focus_cast.get_collision_count()
		
		for i in range(collision_count):
			var collider = player_focus_cast.get_collider(i)
			var potential_item: InteractableObject = null
			
			## 1. Если нашли сам InteractableObject (RigidBody)
			if collider is InteractableObject:
				potential_item = collider
			
			## 2. Если нашли Area, проверяем её родителя
			elif collider is Area3D:
				if collider.get_parent() is InteractableObject:
					potential_item = collider.get_parent()
			
			if potential_item:
				## ⚠️ Игнорируем объект, который уже в руках
				if potential_item == carried_item:
					continue
				
				detected_count += 1
				var distance = player.global_position.distance_to(potential_item.global_position)
				
				if distance < closest_distance:
					closest_distance = distance
					new_interactable = potential_item
	
	## Second tier. The focus cast answers "what is right in front of the
	## hands"; when it answers nothing, this asks the wider question "what is
	## this player plausibly reaching for" — see intent_radius. Run only on a
	## miss, so anything actually in focus still wins and the cast's own
	## reach stays the deliberate gameplay choice player.tscn says it is.
	if new_interactable == null:
		new_interactable = _find_intent_target()

	## 🔥 КРИТИЧНО! Этот блок теперь ВСЕГДА выполняется, даже если is_colliding() == false
	## Обработка смены объекта в фокусе
	if new_interactable != current_interactable:
		## Уведомляем старый объект, что он больше не в фокусе
		if current_interactable and current_interactable != carried_item:
			current_interactable.on_lost_by_player()
			print("🚫 Объект потерян из фокуса: ", current_interactable.name_interactable_object)
		
		## Уведомляем новый объект, что он обнаружен
		if new_interactable:
			new_interactable.on_detected_by_player()
			print("👁️ Объект обнаружен: ", new_interactable.name_interactable_object)
		
		current_interactable = new_interactable

	_emit_target_if_changed()


## Announces what is targeted and whether it is already within arm's reach.
## Called every frame but emits only on an edge — the object changing, or the
## player crossing pickup_distance without changing target.
##
## SILENT WHILE THE KEY IS CLAIMED, and that is what makes the affordance have
## one owner rather than two. At a hover door the claimant puts up its own
## prompt and its own decal; this component is blind to the key at that moment
## (InputSystems does not deliver it here), so it must be blind to the DISPLAY
## too or two markers argue about one button. _update_affordance() carries
## the same rule for what is drawn.
func _emit_target_if_changed() -> void:
	var claimed: bool = InputSystems.is_interact_claimed()
	## A freed target answers false here and 0 below, so a picked-up object
	## reports as "nothing targeted" rather than being dereferenced.
	var in_reach := not claimed and current_interactable != null \
			and _flat_distance_to(current_interactable) <= pickup_distance
	var target_id: int = 0 if claimed else (
		current_interactable.get_instance_id() if current_interactable else 0
	)
	if target_id == _last_target_id and in_reach == _last_in_reach:
		return
	## The reach edge, told to the OBJECT as well as to the signal. The tick
	## sprite over it is driven by on_detected/on_lost, and both of those fire
	## on a change of TARGET — so walking up to something already targeted was
	## silent, and the tick stayed up under the F badge. Only on a genuine
	## change of reach for the SAME target: a new target already carries its
	## own on_detected_by_player(), and calling this there too would replay the
	## entrance a second time in one frame.
	var same_target: bool = target_id == _last_target_id and target_id != 0
	previous_interactable = current_interactable
	_last_target_id = target_id
	_last_in_reach = in_reach
	if same_target and is_instance_valid(current_interactable):
		current_interactable.on_reach_changed(in_reach)
	interact_target_changed.emit(null if claimed else current_interactable, in_reach)


## Whether the current candidate is already within arm's reach, i.e. whether F
## acts now or walks over first. Public because the DISPLAY needs the same
## answer and must not re-derive it — a second copy of the distance rule is
## how the decal and the behaviour drift apart. Written by
## _emit_target_if_changed(), which is where the rule lives.
func is_target_in_reach() -> bool:
	return _last_in_reach


## Puts the key panel over the candidate, or takes it away. The decal under it
## is the other half of the same affordance and is raised by HUDComponent,
## which READS this component every physics frame — the dependency points that
## way on purpose: what finds things does not know who draws them.
##
## SILENT — not "hides" — WHILE THE KEY IS CLAIMED, and that distinction was a
## real bug rather than a nicety. This used to call hide_prompt() on every
## claimed frame, stomping the panel the claim holder had raised one frame
## earlier, so a hover door showed nothing at all however long the player
## stood in it (measured 2026-09-02: key claimed, no panel, no decal). A claim
## means someone else owns the display too; this component neither shows nor
## hides.
func _update_affordance() -> void:
	if InputSystems.is_interact_claimed():
		return

	var prompt: HoldPrompt = _resolve_hold_prompt()
	if prompt == null:
		return
	## THE REACH TEST SEQUENCES THE AFFORDANCE, and that is the whole of this
	## gate. Far: the tick sprite floats over the object and knocks — "there is
	## something here" — and this badge stays down. In reach: the tick lifts
	## away (InteractableObject.on_reach_changed) and the badge rises out of
	## the ground decal in its place — "and F acts on it now".
	##
	## Before this gate both came up together the moment anything entered
	## intent_radius, 2.5 m, and physically overlapped: measured on a render
	## frame 2026-09-03 at 2.00 m, the tick sits inside the F plate.
	##
	## The cost, stated because it is a real one: F is hidden from 2 m even
	## though pressing it there WORKS — try_interact() walks the character over
	## first. The tick carries that half of the message now.
	if current_interactable == null or not is_target_in_reach():
		prompt.hide_prompt()
		return
	## HoldPrompt ignores a repeat show for the same node, so the entrance
	## still plays exactly once per candidate.
	prompt.show_prompt(current_interactable)


func _resolve_hold_prompt() -> HoldPrompt:
	if is_instance_valid(_hold_prompt):
		return _hold_prompt
	_hold_prompt = get_tree().get_first_node_in_group(
		HoldPrompt.GROUP_HOLD_PROMPT
	) as HoldPrompt
	return _hold_prompt

func update_debug_label() -> void:
	if not debug_label:
		return
	
	## Статус работы ShapeCast
	var status_line = ""
	if player_focus_cast.enabled:
		var shape_detecting = player_focus_cast.is_colliding()
		status_line += "🔷 ShapeCast: " + ("✅ Активен" if shape_detecting else "⚫ Нет объектов")
		if shape_detecting:
			status_line += " (Обнар: " + str(detected_count) + ")"
			## Если обнаружено больше 1 объекта! - указываем что показываем ближайший!
			if detected_count > 1:
				status_line += " - Ближайший"
	else:
		status_line += "🔷 ShapeCast: ❌ Выключен"
	
	## Показываем инфу о предмете в руках
	if carried_item:
		status_line += "\n✋ В руках: " + carried_item.name_interactable_object
	
	## Если есть текущий интерактивный объект
	if current_interactable:
		var info_text = status_line + "\n\n"
		info_text += "📦 Объект: " + current_interactable.name_interactable_object + "\n"
		info_text += "📏 Дистанция: " + ("%.2f" % closest_distance) + " м\n"
		info_text += "🏷️ Тип: " + get_interaction_type_name(current_interactable.interaction_type) + "\n"
		
		## Показываем возможности объекта
		var abilities = []
		
		match current_interactable.interaction_type:
			InteractableObject.InteractionType.BUTTON:
				abilities.append("🔘 Активировать")
			InteractableObject.InteractionType.CARRY_ONLY:
				abilities.append("✋ Поднять")
			InteractableObject.InteractionType.INVENTORY_ONLY:
				abilities.append("🎒 Взять в инвентарь")
			InteractableObject.InteractionType.CARRY_AND_INVENTORY:
				abilities.append("✋ Поднять")
				abilities.append("🎒 В инвентарь")
			InteractableObject.InteractionType.VEHICLE:
				abilities.append("🚗 Войти в машину")
		
		if current_interactable.can_throw:
			abilities.append("💨 Бросить")
		
		if current_interactable.can_use_in_hands:
			abilities.append("⚡ Использовать")
		
		info_text += "⚙️ Действия:\n   • " + "\n   • ".join(abilities)
		
		debug_label.text = info_text
		debug_label.visible = true
	else:
		## Показываем только статус работы кастов
		debug_label.text = status_line
		debug_label.visible = true
		
		
## Nearest interactable inside intent_radius and inside the forward cone, or
## null. One shape query per physics frame, and only on a focus-cast miss.
##
## Queries the same Area3Ds the focus cast does — CollisionLayers.INTERACTABLES,
## areas only — so an object needs nothing new to be found this way, and an
## object that deliberately has no Area is still invisible to both tiers.
func _find_intent_target() -> InteractableObject:
	if player == null or intent_radius <= 0.0:
		return null

	var shape := SphereShape3D.new()
	shape.radius = intent_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, player.global_position)
	query.collision_mask = CollisionLayers.INTERACTABLES
	query.collide_with_areas = true
	query.collide_with_bodies = false

	## get_facing_direction(), not the basis: this project's visual forward is
	## +Z, and deriving it from the basis gets the sign backwards — see that
	## method's own comment in player.gd.
	var facing: Vector3 = player.get_facing_direction()
	var half_angle := deg_to_rad(intent_angle_deg) * 0.5

	var best: InteractableObject = null
	var best_distance: float = INF
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 32):
		var object := _interactable_from(hit.get("collider"))
		if object == null or object == carried_item:
			continue
		var to_object: Vector3 = object.global_position - player.global_position
		to_object.y = 0.0
		var distance := to_object.length()
		if distance > intent_radius or distance >= best_distance:
			continue
		## A target directly on top of the player has no direction to judge,
		## and is plainly in reach either way.
		if distance > 0.01 and facing.angle_to(to_object / distance) > half_angle:
			continue
		best = object
		best_distance = distance
	return best


## An InteractableObject from whatever a query returned — the object itself,
## or the Area3D that belongs to one. Same two cases detect_interactable()
## already handles for the focus cast, pulled out so both tiers agree on what
## counts as a hit.
func _interactable_from(collider: Variant) -> InteractableObject:
	if collider is InteractableObject:
		return collider
	if collider is Area3D and collider.get_parent() is InteractableObject:
		return collider.get_parent()
	return null


## Horizontal distance from the player to an object. Horizontal because the
## character walks on the ground: an item on the floor is a metre below the
## chest and that is not distance to cover.
func _flat_distance_to(object: Node3D) -> float:
	var to_object: Vector3 = object.global_position - player.global_position
	to_object.y = 0.0
	return to_object.length()


## F states an INTENT: "interact with that". It no longer requires the
## character to already be standing correctly — if the target is further away
## than pickup_distance, the character walks over first and the interaction
## runs on arrival.
##
## The alternative was widening every object's detection Area until standing
## anywhere near counted as standing on it, which only moves the positioning
## problem into level authoring.
func try_interact() -> void:
	## Если уже что-то в руках - выбрасываем
	if carried_item:
		_cancel_approach()
		_drop_item()
		return
	
	if not current_interactable:
		return

	## Already there — act now, with no walk and no delay. This is the path
	## every interaction took before the approach existed, and the one it
	## still takes whenever the player has done the positioning themselves.
	if _flat_distance_to(current_interactable) <= pickup_distance:
		_cancel_approach()
		_perform_interaction(current_interactable)
		return

	_begin_approach(current_interactable)


## What F actually does, once the character is in reach. Extracted from
## try_interact() so the immediate path and the on-arrival path run the SAME
## code — a second copy of this match is how the two would drift apart.
func _perform_interaction(object: InteractableObject) -> void:
	if object == null or not is_instance_valid(object):
		return

	## The tap payoff, fired here rather than in try_interact() for the same
	## reason the match below lives here: this is the ONE point both the
	## immediate path and the on-arrival path pass through.
	var prompt: HoldPrompt = _resolve_hold_prompt()
	if prompt != null:
		prompt.instant_complete()

	## Проверяем тип взаимодействия
	match object.interaction_type:
		InteractableObject.InteractionType.CARRY_ONLY, \
		InteractableObject.InteractionType.CARRY_AND_INVENTORY:
			_pickup_item(object)
		InteractableObject.InteractionType.BUTTON:
			_activate_button(object)
		InteractableObject.InteractionType.VEHICLE:  # flying car
			_enter_vehicle(object)
		InteractableObject.InteractionType.INVENTORY_ONLY:
			_store_item(object)


## Sends the character walking to a point in front of the target.
##
## The stop point is on the line FROM the object TOWARD where the player is
## already standing, at pickup_distance — approaching from where you are is
## what makes it read as walking over rather than being routed around. It is
## then dropped onto the ground by a downward ray, the same method the
## carbine's own world placement uses; without that, an item on a slope
## produces a target floating above or buried under the terrain.
##
## Reuses the click-to-move contract exactly (set_movement_speed +
## move_to_position) rather than driving the body from here — that path is
## already the one navigation uses, and player.gd already turns the
## body toward the point it is walking to, so the character arrives facing
## the target with nothing extra to do.
func _begin_approach(object: InteractableObject) -> void:
	if player == null or not player.is_movement_enabled():
		return

	var from_object: Vector3 = player.global_position - object.global_position
	from_object.y = 0.0
	if from_object.length() < 0.01:
		return
	## Aimed slightly INSIDE the arrival radius, not exactly on it. The walk
	## ends when _handle_navigation() gets within 5 cm of the point, and the
	## ground snap below moves it again — landing exactly on the boundary
	## makes arrival a coin flip.
	var stop_point: Vector3 = object.global_position \
			+ from_object.normalized() * (pickup_distance * 0.75)
	stop_point.y = _ground_height_at(stop_point, player.global_position.y)

	_pending_interactable = object
	_approach_elapsed = 0.0
	_approach_body_stopped = false
	## Walk, never run. Two metres at run_speed reads as lunging, and this is
	## a deliberate act rather than an escape.
	player.set_movement_speed(player.walk_speed)
	player.move_to_position(stop_point)


## Ground height under a point, or the fallback when nothing is below it.
func _ground_height_at(point: Vector3, fallback_y: float) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(point.x, fallback_y + 2.0, point.z),
		Vector3(point.x, fallback_y - 5.0, point.z),
		CollisionLayers.GROUND
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit["position"].y if not hit.is_empty() else fallback_y


## Drives an approach to its end, one of three ways: arrived, gave up, or the
## target stopped existing.
##
## Arrival is measured as DISTANCE TO THE TARGET, never "the path ended". A
## right-click move order in ISOMETRIC replaces the path underneath us, and a
## path-ended test would then fire the interaction at wherever that order
## went. Distance cannot be fooled that way.
func _update_approach(delta: float) -> void:
	if _pending_interactable == null:
		return

	if not is_instance_valid(_pending_interactable) or player == null:
		_cancel_approach()
		return

	## Distance decides, and it is asked FIRST — before the body-stopped and
	## timeout branches — so a walk that ended right on the boundary still
	## counts as having arrived rather than as having been interrupted.
	if _flat_distance_to(_pending_interactable) <= pickup_distance + 0.05:
		var target := _pending_interactable
		_cancel_approach()
		player.stop_moving(true)
		_perform_interaction(target)
		return

	if _approach_body_stopped:
		## Stopped short: either the player gave an order of their own, or
		## the path ran out without getting there.
		_cancel_approach()
		return

	_approach_elapsed += delta
	if _approach_elapsed >= approach_timeout:
		## Walked into something and stopped making progress. There is no
		## navmesh in this project, so this is a real outcome rather than a
		## defensive branch — see approach_timeout.
		_cancel_approach()
		player.stop_moving(true)


## Forgets a pending approach without touching the body. Callers that also
## want the character to stop say so themselves — _drop_item() and a fresh
## interact both continue moving on purpose.
func _cancel_approach() -> void:
	_pending_interactable = null
	_approach_elapsed = 0.0
	_approach_body_stopped = false


## The body stopped. Deliberately does NOT cancel: this same signal fires
## when the path simply ran out, and only _update_approach() knows whether
## that happened in reach of the target or short of it. Recording the fact
## and letting the distance test rule next frame is what keeps a walk that
## ended on the boundary from silently losing the pickup.
func _on_player_movement_stopped() -> void:
	if _pending_interactable != null:
		_approach_body_stopped = true

## INVENTORY_ONLY: предмет уходит на игрока напрямую, минуя руки.
## При отказе остаётся в мире нетронутым.
##
## This component no longer decides WHERE the item ends up — it only says the
## player wants it. store_item() on the player picks worn-vs-carried, because
## that order is a decision about the character's belongings and neither
## EquipmentComponent nor InventoryComponent should have to know the other
## exists. Freeing the world object stays here: that an interactable was
## consumed is interaction's own business.
##
## Duck-typed through has_method(), the same idiom on_world_ready(),
## get_actor_id() and the save contract already use — player.gd carries no
## class_name, so there is no type to hold it by.
func _store_item(object: InteractableObject) -> void:
	if player == null or not player.has_method(&"store_item"):
		push_warning("[Interact] player has no store_item() — %s left in the world" % object.name)
		return
	if player.call(&"store_item", object.item):
		_play_pickup_gesture(object)
		object.queue_free()


## Asks the player to animate the pickup, passing WHERE the thing was — the
## player picks the clip from its height (play_pickup_gesture()). This
## component says what happened, not what it should look like: the same split
## _store_item() already makes for where the item ends up.
##
## Fired on success only, and after the store: a refused pickup must not
## produce a reach for something that stayed on the ground. Duck-typed
## through has_method(), the same idiom store_item() above uses — player.gd
## carries no class_name, so there is no type to hold it by.
##
## The object's global_position is read BEFORE queue_free() — a freed node
## has no transform to ask.
func _play_pickup_gesture(object: InteractableObject) -> void:
	if player == null or not player.has_method(&"play_pickup_gesture"):
		return
	player.call(&"play_pickup_gesture", object.global_position)
			
func _pickup_item(item: InteractableObject) -> void:
	if carried_item: return
	
	carried_item = item
	
	## Same gesture as an inventory pickup, and for the same reason: what
	## the hands do depends on where the thing was, not on which of the two
	## routes it takes afterwards.
	_play_pickup_gesture(item)
	
	## даем знать item, что он подобран
	item.on_picked_up()
	
	## 1. Отключаем физику (теперь это сам item)
	item.freeze = true
	
	## 2. Отключаем коллизии физического тела, чтобы не толкал игрока
	item.collision_layer = 0
	item.collision_mask = 0
	
	## 3. Отключаем зону детекции
	if item.interaction_area:
		item.interaction_area.monitorable = false

	## Анимация и аттач
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(item, "global_position", pickup_slot.global_position, 0.3)
	tween.parallel().tween_property(item, "global_rotation", pickup_slot.global_rotation, 0.3)
	tween.tween_callback(_attach_to_slot.bind(item))
	
func _attach_to_slot(item: InteractableObject) -> void:
	## аттачим перед игрок к ноде ПикапСлот
	item.reparent(pickup_slot)
	item.position = Vector3.ZERO
	item.rotation = Vector3.ZERO
	
## Was an empty stub — InteractableObject.activated already existed and
## already documented "doors/lifts/terminals subscribe to this signal", but
## nothing ever emitted it, so BUTTON never actually did anything on
## interact. Filled in, not bypassed: LodgingRoom's BedPoint (world/lodging/)
## is the first real BUTTON consumer and goes through this same path, per
## its own brief ("не заводи отдельный путь ввода для кровати").
func _activate_button(current_interactable: InteractableObject) -> void:
	current_interactable.activated.emit(player)
	
func _drop_item() -> void:
	if not carried_item: return
	
	var item = carried_item
	carried_item = null
	
	item.on_dropped()
	
	## Отцепляем от игрока
	item.reparent(get_tree().current_scene)
	
	## Позиция броска
	var forward = player.global_transform.basis.z 
	item.global_position = player.global_position + forward * 1.5
	
	# Восстанавливаем слои физики (чтобы он мог стукаться)
	item.collision_layer = CollisionLayers.PHYSICS_OBJECTS
	item.collision_mask = CollisionLayers.INTERACTION
	
	## Сила броска
	var throw_force = forward * 2.5 + Vector3.UP * 1.0 ## можно больше поставить
	var spin = Vector3(randf(), randf(), randf()) * 2.0 ## тут закрутить сильно можно
	
	## Запуск
	item.throw_self(throw_force, spin)
	
# заглушка — сюда придёт логика угона
func _enter_vehicle(vehicle: InteractableObject) -> void:
	print("🚗 Взаимодействие с транспортом: ", vehicle.name_interactable_object)
	if get_parent().visible == true:
		get_parent().visible = false
		get_parent().set_physics_process(false)
	else:
		get_parent().visible = true
		get_parent().set_physics_process(true)
	# TODO: передать управление PlayerDriver

func get_interaction_type_name(type: InteractableObject.InteractionType) -> String:
	match type:
		InteractableObject.InteractionType.BUTTON:
			return "Кнопка/Терминал"
		InteractableObject.InteractionType.CARRY_ONLY:
			return "Переносимый предмет"
		InteractableObject.InteractionType.INVENTORY_ONLY:
			return "Инвентарный предмет"
		InteractableObject.InteractionType.CARRY_AND_INVENTORY:
			return "Переносимый + Инвентарь"
		InteractableObject.InteractionType.VEHICLE:
			return "Транспортное средство"
	return "Неизвестно"
