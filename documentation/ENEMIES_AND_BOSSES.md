# Enemies & Bosses

## Regular Enemies

### Skeleton
The basic enemy found in all towers.

| Stat | Value |
|------|-------|
| Health | 25 |
| Patrol Speed | 35 px/s |
| Chase Speed | 55 px/s |
| Lunge Speed | 150 px/s |
| Contact Damage | 5 |
| Attack Damage | 8 |
| Detection Range | 140px |
| Attack Range | 35px |
| Attack Cooldown | 2.0s |

**Behaviors (State Machine):**
- **PATROL** - walks back and forth on platform. Switches to CHASE if player within 140px.
- **CHASE** - sprints toward nearest player. Jumps (-400 velocity) if player is above. Returns to PATROL if player > 210px away.
- **ATTACK** - lunges at player at 150px/s, deals 8 damage. 0.3s pause after attack, then back to CHASE.
- **HURT** - brief 0.25s stun when hit. Gets knocked back 150px in opposite direction.
- **DEAD** - shrinks and fades, drops 3 mini-muffins.

Skeletons are in the `"enemies"` group so donut buddies can target them.

---

## Bosses

All bosses share a base system:
- **Hit flash:** White flash for 0.12 seconds when damaged
- **Phase system:** Phase 2 at 50% HP, Phase 3 at 25% HP
- **Death animation:** Rapid flash + shrink over ~1 second
- **Gravity:** 980 px/s²
- **Health bar:** 48px wide red bar above boss + UI bar at top of screen

---

### Boss 1: Gingerbread Skeleton (Tower 1)
*A giant skeleton made of gingerbread cookie with icing for joints.*

| Stat | Value |
|------|-------|
| Health | 500 |
| Speed | 80 px/s |
| Attack Cooldown | 2.2s |
| Sprite Scale | 2.0x |
| Hitbox | 48x56 |

**Attacks:**

| Attack | Condition | Damage | Details |
|--------|-----------|--------|---------|
| Bone Throw | Default ranged | 15 | Single bone at 250px/s. Phase 3: 3 bones in spread. |
| Ground Slam | Player within 100px | 25 | Jumps up 30px, slams down. 80px damage radius. |
| Summon Skeletons | Phase 2+, 30% chance | - | Spawns 2 skeletons (Phase 2) or 3 (Phase 3). |

---

### Boss 2: Icing Goblin (Tower 2)
*A hulking goblin made entirely of pastel frosting and fondant.*

| Stat | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| Health | 600 (total) | - | - |
| Speed | 80 px/s | 100 px/s | 120 px/s |
| Attack Cooldown | 2.0s | 1.6s | 1.3s |
| Sprite Scale | 2.0x | - | - |
| Hitbox | 52x52 | - | - |

**Special mechanic:** Takes 50% reduced damage during Icing Shield (4s duration).

**Attacks:**

| Attack | Condition | Damage | Details |
|--------|-----------|--------|---------|
| Icing Spit | Player > 100px away | 12 | Projectile at 200px/s. Leaves slowing puddle (4s, 0.4x speed). Phase 3: double spit. |
| Belly Flop | Player within 110px | 30 | Jumps 60px up, slams down. 90px radius. |
| Icing Shield | Phase 2+, 25% chance | - | 50% damage reduction for 4 seconds. Cyan tint. |

---

### Boss 3: Sprinkle Dragon (Tower 3)
*A dragon covered in rainbow sprinkles with candy fire breath.*

| Stat | Phase 1 | Phase 2 | Phase 3 |
|------|---------|---------|---------|
| Health | 800 (total) | - | - |
| Speed | 60 px/s | 80 px/s | 100 px/s |
| Attack Cooldown | 2.5s | 2.0s | 1.5s |
| Sprite Scale | 2.5x | - | - |
| Hitbox | 64x48 | - | - |

**Attacks:**

| Attack | Condition | Damage | Details |
|--------|-----------|--------|---------|
| Sprinkle Breath | Player > 80px in front | 10 each | 3 sprinkles (5 in Phase 3) in cone, 280px/s. 5 rainbow colors. |
| Tail Swipe | Player behind within 70px | 20 | Hits players behind the dragon. |
| Fly & Rain | Phase 2+, 25% chance | 8 each | Flies up 150px for 4s. Rains 4 (or 7) sprinkles downward at 180px/s. |

---

### Boss 4: Giant Muffin (Final Boss)
*A massive angry muffin with a face, arms, and pure rage.*

| Stat | Phase 1 | Phase 2 | Phase 3 (BERSERK) |
|------|---------|---------|-------------------|
| Health | 1200 (total) | - | - |
| Speed | 50 px/s | 65 px/s | 90 px/s |
| Attack Cooldown | 2.5s | 2.0s | 1.2s |
| Sprite Scale | 3.0x | - | - |
| Hitbox | 72x72 | - | - |

**Berserk Mode (Phase 3):** Red tint, doubled crumb count, spawns previous boss minions.

**Attacks:**

| Attack | Condition | Damage | Details |
|--------|-----------|--------|---------|
| Muffin Slam | Player within 120px | 35 | Jumps 80px up, slams. 100px radius. Spawns 2 shockwave projectiles (15 dmg). |
| Crumb Burst | Player > 120px away | 12 each | 12 projectiles in 360° (24 in Berserk) at 220px/s. |
| Summon Mini-Muffins | 30% chance | - | 2 minions (4 in Berserk). |
| Summon Boss Minions | Berserk only, 20% chance | - | Spawns skeletons + muffin minions. |

---

## Boss Rewards

| Tower | Boss | Artifacts |
|-------|------|-----------|
| 1 | Gingerbread Skeleton | Skeleton Bone Charm, Gingerbread Shield |
| 2 | Icing Goblin | Icing Wand, Goblin Boots |
| 3 | Sprinkle Dragon | Sprinkle Crown, Dragon Scale |
| 4 | Giant Muffin | Muffin Heart, Golden Crumb |
