extends Node
## Global decoupled signal bus for LANTERNFALL (Godot 4.7 GDScript 2.0 static typing).
## Zero direct cross-scene coupling; all systems communicate via typed signals.

# Player & Lantern signals
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_stamina_changed(current_stamina: float, max_stamina: float)
signal lantern_oil_changed(current_oil: float, max_oil: float)
signal player_level_changed(new_level: int, skill_points: int)
signal player_damaged(amount: int, source_pos: Vector3)
signal player_died()

# Combat & Animation feedback signals
signal hit_stop_requested(frames: int)
signal screen_shake_requested(intensity: float, duration: float)
signal floating_damage_spawned(world_pos: Vector3, amount: int, is_critical: bool, is_light_weakness: bool)
signal lock_on_target_changed(target_node: Node3D)

# World, Chunk, Beacon & Weather signals
signal chunk_entered(chunk_id: String, region_name: String)
signal beacon_lit(beacon_id: String, chunk_id: String, new_restoration_ratio: float)
signal time_of_day_changed(hour: float, phase_name: String)
signal weather_changed(weather_id: String, intensity: float)
signal boat_boarding_toggled(is_sailing: bool)
signal fast_travel_requested(target_beacon_id: String)

# Economy, Inventory & Crafting signals
signal currency_changed(koin_embun: int, pecahan_kelip: int)
signal reputation_changed(faction_id: String, new_value: int)
signal inventory_updated()
signal item_acquired(item_id: String, quantity: int)
signal item_crafted(recipe_id: String, result_item_id: String)
signal homestead_upgraded(upgrade_id: String, new_tier: int)

# Quest, Narrative & Journal signals
signal dialogue_started(npc_id: String, start_node_id: String)
signal dialogue_ended(npc_id: String)
signal quest_updated(quest_id: String, state: String, current_step: int)
signal bestiary_unlocked(enemy_id: String, kill_count: int)
signal lore_journal_unlocked(entry_id: String, title: String)
signal moral_choice_recorded(choice_key: String, chosen_option: String)
signal toast_notification(message: String, category: String)

# Settings & UI signals
signal graphics_preset_changed(preset_index: int)
signal touch_layout_updated()
signal colorblind_mode_changed(mode_index: int)
