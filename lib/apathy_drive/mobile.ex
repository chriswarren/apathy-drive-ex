defprotocol ApathyDrive.Mobile do
  def ability_value(mobile, ability)
  def accuracy_at_level(mobile, level)
  def attack_interval(mobile)
  def attack_spell(mobile)
  def attacks_per_round(mobile)
  def attribute_at_level(mobile, attribute, level)
  def auto_attack_target(mobile, room, attack_spell)
  def caster_level(caster, target)
  def colored_name(mobile, observer)
  def confused(mobile, room)
  def crits_at_level(mobile, level)
  def description(mobile, observer)
  def die(mobile, room)
  def dodge_at_level(mobile, level)
  def enough_mana_for_spell?(mobile, spell)
  def enter_message(mobile)
  def exit_message(mobile)
  def has_ability?(mobile, ability_name)
  def heartbeat(mobile, room)
  def held(mobile)
  def hp_description(mobile)
  def look_name(mobile)
  def magical_damage_at_level(mobile, level)
  def magical_resistance_at_level(mobile, level, damage_type)
  def max_hp_at_level(mobile, level)
  def max_mana_at_level(mobile, level)
  def perception_at_level(mobile, level)
  def party_refs(mobile, room)
  def physical_damage_at_level(mobile, level)
  def physical_resistance_at_level(mobile, level, damage_type)
  def power_at_level(mobile, level)
  def regenerate_hp_and_mana(mobile, room)
  def round_length_in_ms(mobile)
  def send_scroll(mobile, html)
  def set_room_id(mobile, room_id)
  def shift_hp(mobile, percentage, room)
  def silenced(mobile, room)
  def spellcasting_at_level(mobile, level)
  def spells_at_level(mobile, level)
  def stealth_at_level(mobile, level)
  def subtract_mana(mobile, spell)
  def target_level(caster, target)
  def tracking_at_level(mobile, level)
  def update_prompt(mobile)
end
