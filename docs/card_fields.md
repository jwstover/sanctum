- [x] attack
- [x] attack_cost
- [ ] attack_star
- [ ] back_flavor
- [ ] back_name
- [ ] back_text
- [x] base_threat
- [ ] base_threat_fixed
- [x] boost
- [x] boost_star
- [x] card_set
- [x] code
- [x] cost
- [ ] cost_per_hero
- [x] deck_limit
- [ ] deck_requirements
- [x] defense
- [x] defense_star
- [ ] double_sided
- [ ] duplicate_of
- [ ] errata
- [x] escalation_threat
- [ ] escalation_threat_fixed
- [ ] escalation_threat_star
- [ ] faction
- [ ] faction2
- [ ] flavor
- [x] hand_size
- [x] health
- [x] health_per_hero
- [ ] health_star
- [ ] illustrator
- [x] is_unique
- [ ] linked_to
- [ ] meta
- [x] name
- [ ] pack
- [x] permanent
- [ ] position
- [ ] quantity
- [x] recover
- [x] recover_star
- [x] resource_energy
- [x] resource_mental
- [x] resource_physical
- [x] resource_wild
- [x] scheme
- [x] scheme_acceleration
- [x] scheme_amplify
- [x] scheme_crisis
- [x] scheme_hazard
- [ ] scheme_star
- [ ] set_position
- [x] stage
- [x] subname
- [ ] subtype
- [x] text
- [x] threat
- [x] threat_fixed
- [x] threat_star
- [x] thwart
- [x] thwart_cost
- [ ] thwart_star
- [x] traits
- [ ] type



# Schema

- Encounter
    - id
    - name
    - villian_cards
    - encounter_cards
    - recommended_modular_sets

- Modular Set
    - id
    - name
    - encounter_cards

- Game
    - id
    - encounter
    - encounter_deck
    - encounter_discard
    - villain
        - card_id
        - stage
        - max_health
        - current_health
    - main_scheme
        - card_id
        - stage
        - max_threat
        - current_threat
    - players

- Player
    - id
    - name
    - deck
    - discard
    - hero
    - max_health
    - current_health
    - hand_size

---

## Enhanced Schema Recommendations

Based on codebase analysis and Marvel Champions game requirements:

### Core Tables

**Scenario** (scenario definition)
- id (uuid)
- name (text)
- villain_cards (jsonb array of card_ids) - Fixed spelling from "villian"
- encounter_cards (jsonb array of card_ids)
- recommended_modular_sets (jsonb array of modular_set_ids)
- nemesis_sets (jsonb array of modular_set_ids) - Hero-specific nemesis sets

**ModularSet** (reusable encounter card sets)
- id (uuid)
- name (text)
- set_code (text, references cards.card_set)
- description (text, nullable)

**Game** (instance of play)
- id (uuid)
- encounter_id (references encounters)
- status (:setup, :player, :villain, :encounter, :completed)
- current_phase (enum)
- current_player_id (references players)
- round_number (integer)
- created_at, updated_at

### Game State Tables

**GameCard** (represents any card instance in the game)
- id (uuid)
- game_id (references games)
- card_id (references cards)
- owner_id (references players, nullable for encounter cards)
- zone (enum: :deck, :hand, :discard, :play, :removed, :encounter_deck, :encounter_discard)
- zone_position (integer, for ordering)
- status (enum: :ready, :exhausted, :stunned, :confused, :tough)
- counters (jsonb: {damage: 0, threat: 0, generic: 0, acceleration: 0})
- attachments (jsonb array of GameCard ids)
- face_up (boolean, for facedown encounter cards)

**GameVillain** (villain state in game)
- id (uuid)
- game_id (references games)
- card_id (references cards)
- stage (integer)
- current_health (integer)
- status (jsonb: {stunned: false, confused: false, tough: 0})
- attachments (jsonb array of GameCard ids)

**GameScheme** (scheme state in game)
- id (uuid)
- game_id (references games)
- card_id (references cards)
- current_threat (integer)
- is_main_scheme (boolean)
- stage (integer, nullable for side schemes)
- attachments (jsonb array of GameCard ids)

**GamePlayer** (player state in game)
- id (uuid)
- game_id (references games)
- player_id (references players, from auth system)
- hero_card_id (references cards)
- alter_ego_card_id (references cards)
- current_health (integer)
- current_hand_size (integer)
- form (enum: :hero, :alter_ego)
- status_effects (jsonb: {stunned: false, confused: false, tough: 0})

### Zone Definitions

Cards exist as GameCard records with these zones:
- **:hero_deck** - Player's deck
- **:hero_hand** - Player's hand (private)
- **:hero_discard** - Player's discard pile
- **:hero_play** - Player's play area
- **:villain_play** - Villain's play area (minions, attachments)
- **:encounter_deck** - Encounter deck
- **:encounter_discard** - Encounter discard pile
- **:main_scheme** - Current main scheme
- **:side_scheme** - Side schemes in play
- **:removed_from_game** - Cards removed from game

### Key Design Principles

1. **GameCard Instances**: Every card in the game exists as a GameCard record, allowing multiple copies with different states
2. **JSONB Flexibility**: Use JSONB for variable data (status effects, counters) to avoid schema changes
3. **Normalized Encounters**: Encounters are templates, Games are instances
4. **Zone-based Management**: Single approach for all card locations
5. **Extensible Counters**: Generic counter system supports all Marvel Champions token types

### Query Examples

```elixir
# Get player's hand
def player_hand(game_id, player_id) do
  from(gc in GameCard, 
    where: gc.game_id == ^game_id and gc.owner_id == ^player_id and gc.zone == :hand,
    order_by: gc.zone_position)
end

# Get all cards in play
def cards_in_play(game_id) do
  from(gc in GameCard,
    where: gc.game_id == ^game_id and gc.zone in [:hero_play, :villain_play],
    preload: [:card])
end
```

### Migration Strategy

1. Fix "villian" → "villain" spelling throughout codebase
2. Expand existing Encounter model
3. Create new ModularSet, GameCard, GameVillain, GameScheme, GamePlayer models
4. Migrate existing Game data to new structure
5. Add proper indexes on (game_id, zone, owner_id) combinations













