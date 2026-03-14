# New Classes Design Document

## Demolitionist

**Identity:** Explosive area damage specialist. Controls space with bombs.

**Stats:**
| Stat | Value |
|------|-------|
| Health | 100 |
| Mana | 100 |
| Speed | 105 |
| Mana Regen | 1.5/s |

**Color scheme:** Orange / Dark gray / Yellow accents

**Basic Attack - Throw Bomb:**
- Arcs with gravity (lobbed trajectory)
- Bounces once off surfaces
- Explodes after 1.5s OR on direct enemy contact
- 25 damage, 60px blast radius
- Knockback on all targets in radius
- VFX: orange explosion circle + particles

**Special - Big Bomb (40 mana):**
- Larger bomb, bigger arc
- 50 damage, 90px blast radius
- Screen shake on detonation
- Leaves brief smoke cloud

**Charge Attack - Mega Bomb:**
- Charge 0.5-3s → radius and fragment count scale
- Min: 60px radius, 0 fragments
- Max: 140px radius, 5 fragment mini-bombs

**Bomb Upgrades (future crafting integration):**

| Upgrade | Effect |
|---------|--------|
| Explosive Power | +25/50/75% damage |
| Blast Size | +20/40/60% radius |
| Fragment | Splits into 3/4/5 mini-bombs after bounce |
| Napalm | Leaves burning ground (10 dmg/s for 3s) |

**Bomb Aspects (mutually exclusive):**

| Aspect | Effect |
|--------|--------|
| Electric | Chains to 2 nearby enemies, 0.5s stun |
| Fire | Ignites target, 5 dmg/s for 3s |
| Impact | 2x knockback, -30% damage |
| Ice | 3s slow in blast radius |

---

## Healer

**Identity:** Support class. Keeps the team alive, buffs allies, disrupts enemies.

**Stats:**
| Stat | Value |
|------|-------|
| Health | 90 |
| Mana | 130 |
| Speed | 95 |
| Mana Regen | 2.5/s |

**Color scheme:** White / Soft green / Gold accents

**Basic Attack - Healing Staff:**
- Staff swing: 10 damage to enemies
- Simultaneously heals closest injured ally for 8 HP
- Visual: green healing arc connects to nearest ally
- If no allies nearby or all full HP, just does damage

**Special - Healing Burst (50 mana):**
- AoE heal: 30 HP to all allies within 80px
- Green pulse VFX expanding outward
- Minor enemy pushback in radius

**Charge Attack - Healing Blast Wave:**
- Hold attack to charge (0.5-3s)
- Release: circular healing wave pulses outward from healer
- Wave radius: 60px (min charge) → 200px (max charge)
- Heal amount: 15 HP (min) → 50 HP (max)
- Allies hit get temporary buff: +10% speed, +10% damage for 5s
- Enemies hit get stunned for 1.5s
- Visual: bright green/gold ring expanding outward

**Dash - Perpendicular Healing Wave:**
- When healer dashes, a line of energy expands perpendicular to dash direction
- Heals allies it passes through for 10 HP
- Pushes enemies aside
- Visual: bright green line expanding sideways from dash path

---

## Combat System Changes (All Classes)

### Charge Attack
- Hold attack for 0.5-3s to charge
- Character glows, particles emit, sound builds
- Release to fire enhanced version of attack
- Getting hit while charging → STAGGERED

### Stagger State
- Duration: 1.0s
- Cannot move, attack, or use abilities
- Take 25% more damage
- Visual: rapid left-right shake (±3px at 20Hz) + cartoon stars above head
- Triggered by: getting hit while charging

### Block/Parry
- Hold block button: 50% damage reduction, 50% move speed
- Perfect Parry: block within 0.2s of incoming hit
  - Attacker stunned for 1.5s
  - Bright flash + metallic clang
  - No damage taken

### Dash Wave
- All dashes create a perpendicular wave
- Wave pushes enemies, deals 5 damage (Rogue: 10)
- Adds utility to every class's movement
