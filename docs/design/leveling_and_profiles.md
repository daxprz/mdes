# Character Leveling & Persistent Profiles - Design Document

## Overview

Two interconnected systems:
1. **Skill-based leveling** - abilities improve through effective use
2. **Persistent profiles** - progress saves between sessions

---

## Leveling System

### Core Principle
"You get better at what you DO." Landing hits improves your attack.
Blocking improves your defense. Healing improves your healing.
No passive XP - every point is earned through action.

### XP Sources

| Action | XP Gained | Skill Affected |
|--------|-----------|---------------|
| Basic attack lands | 1-3 (scales with enemy tier) | Attack |
| Special ability hits/heals | 5-10 | Special |
| Charge attack damage | 1 per 5 damage dealt | Charge |
| Block incoming hit | 3 | Block |
| Perfect parry | 15 | Block |
| Kill enemy | 10 bonus (overall) | Overall |
| Defeat boss | 50-100 bonus (overall) | Overall |
| Heal ally (Healer) | 0.5 per HP healed | Special |
| Donut buddy damage (Summoner) | 1 per hit | Special |

### XP Curve

| Level | XP Required | Cumulative |
|-------|-------------|------------|
| 1 | 100 | 100 |
| 2 | 250 | 350 |
| 3 | 450 | 800 |
| 4 | 700 | 1500 |
| 5 | 1000 | 2500 |
| 10 | 3000 | ~15000 |
| 15 | 6000 | ~40000 |
| 20 (max) | 10000 | ~75000 |

Formula: `xp_for_level = 100 * level * (level + 1) / 2`

### Skill Level Benefits

**Per skill level:**
| Skill | Bonus Per Level |
|-------|----------------|
| Attack | +2% damage |
| Special | -2% cooldown, +1% effect power |
| Charge | +3% charge speed, +2% max damage |
| Block | +1% damage reduction, +0.02s parry window per 5 levels |

**Milestone unlocks (visual/audio):**
- Level 5: Attack gets brighter particle trail
- Level 10: Special gets enhanced VFX color
- Level 15: Charge attack gets screen shake
- Level 20: All attacks get golden particle aura

### Overall Character Level
- Calculated as: `floor(average of all skill levels)`
- Grants: +5 max HP per level, +3 max mana per level
- Displayed as "Lv.X" next to player name

---

## Persistent Profile System

### Profile Data Structure (JSON)

```json
{
  "profiles": [
    {
      "id": "uuid-here",
      "name": "Dax",
      "created": "2026-03-14T10:30:00",
      "last_played": "2026-03-14T15:45:00",
      "class_preferences": ["MELEE", "DEMOLITIONIST", "ROGUE", "RANGED", "MAGE", "SUMMONER", "HEALER"],
      "per_class": {
        "MELEE": {
          "sub_name": "BladeMaster",
          "skill_xp": {
            "attack": 1250,
            "special": 800,
            "charge": 450,
            "block": 300
          },
          "total_kills": 347,
          "total_muffins": 1203,
          "boss_kills": 5,
          "playtime_seconds": 7200
        },
        "DEMOLITIONIST": {
          "sub_name": "BoomBoy",
          "skill_xp": { ... },
          ...
        }
      },
      "lifetime_stats": {
        "total_playtime": 14400,
        "total_muffins": 2500,
        "total_kills": 890,
        "bosses_defeated": 12,
        "towers_completed": 28,
        "perfect_parries": 45
      }
    }
  ]
}
```

### Save File Location
- `user://profiles.json` (Godot user data directory)
- Auto-saves on: tower complete, boss defeat, quit to menu
- Loads on game launch

### Profile Creation Flow

```
Controller Connected
       |
       v
[SELECT PROFILE]  or  [CREATE NEW]
       |                    |
  Pick from list     Step 1: Enter Name (3-16 chars)
       |                    |
       v              Step 2: Rank Classes (drag to reorder)
  Join Game                 |
                      Step 3: Name Sub-Characters (optional)
                            |
                      Step 4: Confirm Summary
                            |
                        Join Game
```

### Pause Menu Profile Display

```
+----------------------------------+
|           PAUSED                 |
|                                  |
|  [Avatar]  Dax - Melee Lv.12    |
|                                  |
|  ====== SKILLS ======           |
|  Attack   Lv.14  ████████░░     |
|  Special  Lv.11  ██████░░░░     |
|  Charge   Lv.9   █████░░░░░     |
|  Block    Lv.8   ████░░░░░░     |
|                                  |
|  ====== SESSION ======          |
|  Muffins: 47  Kills: 23         |
|  Artifacts: Gingerbread Shield   |
|                                  |
|  > RESUME                        |
|    QUIT TO MENU                  |
|    QUIT GAME                     |
+----------------------------------+
```
