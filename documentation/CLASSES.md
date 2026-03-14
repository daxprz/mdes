# Character Classes

## Class Comparison

| Stat | Melee | Ranged | Mage | Summoner | Rogue |
|------|-------|--------|------|----------|-------|
| **Health** | 175 | 100 | 80 | 90 | 90 |
| **Mana** | 50 | 80 | 150 | 120 | 60 |
| **Speed** | 110 | 120 | 90 | 95 | 150 |
| **Mana Regen** | 1.0/s | 1.5/s | 3.0/s | 2.0/s | 1.5/s |

---

## Melee (Knight)
**Color scheme:** Steel blue / Silver

**Basic Attack - Sword Combo** (3-hit chain)
- Hit 1: 25 damage, 20px range
- Hit 2: 35 damage, 22px range
- Hit 3: 50 damage, 28px range + knockback
- Combo window: 0.6 seconds between hits
- Final hit plays a heavier sound and spawns VFX

**Air Attack - Ground Slam** (tower only)
- Attack while airborne → slams downward at 600px/s
- 45 damage in 80px radius on landing
- Explosion VFX + knockback on all nearby enemies

**Special - Shield Charge**
- Dashes forward at 250px/s (overworld) / 600px/s (tower)
- 40 damage (overworld) / 35 damage to all in path (tower)
- Brief invincibility during dash (tower)
- Knockback on hit targets
- Blue flash visual

**Identity:** Tanky frontliner. Highest HP, strong melee combos, great for crowd control.

---

## Ranged (Ranger)
**Color scheme:** Forest green / Leather brown

**Basic Attack - Crossbow Bolt**
- 15 damage projectile at 350px/s
- Long range, can hit from safety

**Special - Explosive Muffin Grenade**
- 35 damage AoE projectile at 250px/s
- Green VFX flash on launch
- No mana cost

**Identity:** Safe damage dealer. Stays back, shoots from range. Grenade for burst AoE.

---

## Mage (Wizard)
**Color scheme:** Royal purple / Deep gold

**Basic Attack - Magic Bolt**
- 20 damage projectile at 300px/s
- Costs 10 mana per shot
- Won't fire if insufficient mana

**Special - Frosting Freeze**
- Costs 40 mana
- 120px radius AoE slow effect
- Slows all enemies in range for 3 seconds
- Icy blue VFX burst
- Red flash if not enough mana

**Identity:** High damage caster with crowd control. Glass cannon - lowest HP but fastest mana regen (3.0/s). Can lock down enemies for teammates.

---

## Summoner
**Color scheme:** Warm orange / Sunny yellow

**Basic Attack - Staff Bonk**
- 8 damage melee hit (weak)
- Short range (16px)

**Special - Summon Donut Buddy**
- Costs 30 mana (tower) / 25 mana (overworld)
- Spawns an Adventure Time-style animated donut companion
- Maximum 3 buddies active at once
- Orange VFX flash on summon

### Donut Buddy Stats
| Stat | Value |
|------|-------|
| Health | 30 |
| Move Speed | 80 |
| Attack Damage | 8 |
| Attack Range | 28px |
| Attack Cooldown | 1.0s |
| Detection Range | 120px |
| Follow Distance | 40px |

Buddies automatically:
- Follow the summoner when no enemies nearby
- Detect and chase nearest enemy within 120px
- Attack enemies in range every 1 second
- Die when health reaches 0 (frees up a summon slot)

**Identity:** Army builder. Weak alone but powerful with 3 donut buddies dealing 24 DPS combined. The buddies fight for you!

---

## Rogue
**Color scheme:** Dark crimson / Charcoal black

**Basic Attack - Dagger Stab**
- 22 damage (tower) / 18 damage (overworld)
- Fast attack (0.1s active window vs 0.15s for others)
- Medium range (18px)

**Special - Shadow Dash**
- Teleports 120px in facing direction
- 0.3 seconds of invincibility (semi-transparent visual)
- Raycasts to walls - won't teleport through them
- Ghost trail VFX at start and end positions
- No mana cost

**Identity:** Fastest class (150 speed). Hit-and-run assassin. Shadow dash through danger, stab, dash out. Great for dodging boss attacks.
