# Character Classes

## Class Comparison

| Stat | Melee | Ranged | Mage | Summoner | Rogue | Demolitionist | Healer | Tank | Ninja | Balloonist | Guitarist | Werewolf |
|------|-------|--------|------|----------|-------|---------------|--------|------|-------|------------|-----------|----------|
| **Health** | 175 | 100 | 80 | 90 | 90 | 100 | 90 | 250 | 85 | 80 | 110 | 200 |
| **Mana** | 50 | 80 | 150 | 120 | 60 | 100 | 130 | 30 | 70 | 90 | 100 | 40 |
| **Speed** | 110 | 120 | 90 | 95 | 150 | 105 | 95 | 70 | 140 | 100 | 95 | 120 |
| **Mana Regen** | 1.0/s | 1.5/s | 3.0/s | 2.0/s | 1.5/s | 1.5/s | 2.5/s | 0.5/s | 1.5/s | 1.0/s | 2.0/s | 0.5/s |

---

## Melee (Knight)
**Color scheme:** Steel blue / Silver

**Basic Attack - Sword Combo** (3-hit chain)
- Hit 1: 25 damage, 20px range
- Hit 2: 35 damage, 22px range
- Hit 3: 50 damage, 28px range + knockback
- Combo window: 0.6 seconds between hits
- Final hit plays a heavier sound and spawns VFX
- Arc color matches combo stage (white > yellow > orange)

**Air Attack - Ground Slam** (tower only)
- Attack while airborne: slams downward at 600px/s
- 45 damage in 80px radius on landing
- Explosion VFX + knockback on all nearby enemies

**Special - Shield Charge**
- Dashes forward at 600px/s with invincibility
- 35 damage to all in path
- Knockback on hit targets, blue flash visual

**Charge Attack - Ground Pound**
- Hover in place while charging (wiggle animation + smoke particles)
- On release: slam with blast radius 40px (min) to 120px (max)
- Damage scales 30 to 80 based on charge time
- Screen shake on impact scales with charge

**Circle Ability - Enrage** (10s duration, 45s cooldown)
- 1.5x speed multiplier
- 1.8x damage multiplier
- Red tint VFX, "ENRAGE!" floating text
- Sound: enrage_roar.wav

**Identity:** Tanky frontliner. Highest HP among original classes, strong melee combos, great for crowd control. Enrage turns him into a damage machine.

---

## Ranged (Ranger)
**Color scheme:** Forest green / Leather brown

**Basic Attack (Square) - Crossbow Bolt**
- 60 damage projectile at 400px/s
- Ammo system: 10 arrows max, must reload
- Fires in aimed direction (right stick / movement)

**Aimed Shot (L2 + R2) - Physics Arrow**
- Hold L2: reticle appears, aim with right stick anywhere on screen
- Pull strength builds over time (300–1800 px/s). Partial trigger = partial max.
- RB: reverse power direction. Release RB: lock power level.
- Arc solver finds launch angle for parabolic trajectory to reticle
- Reticle sparkles when solution found, 50% transparent when not
- R2: fires arrow along solved arc (or best-attempt). Does not consume ammo.
- Auto re-strings in 0.5s. Locked power persists across shots.
- Charge bar + lock indicator shown below player

**Grappling Hook (L1/LB)**
- Hold L1: hook spins (14–35 rad/s). Aim with either stick (right priority).
- Release L1: thrown at 4000–10000 px/s with gravity arc. Max range 900px.
- Connects to walls/enemies (10 damage). Player launched toward anchor.
- Pendulum swing with rope slack physics. Rope bounces when taut.
- L1 again (wall): phase 1 = pull toward anchor, phase 2 = disconnect
- L1 again (enemy): Newtonian tug (F=ma, mass-based)
- Jump: disconnect + 25% jump velocity in thumbstick direction (additive)
- Controller rumble at all key moments. Full movement during windup.

**Charge Attack - Piercing Shot**
- Charged bolt that pierces enemies, bigger projectile
- Damage and size scale with charge time

**Circle Ability - Reload**
- Hold Circle to reload arrows (1.5s reload time)
- reload_click.wav on completion

**Identity:** High single-target damage dealer. Ammo management adds tactical depth. Physics grappling hook provides momentum-based traversal, enemy manipulation via mass-based tug mechanics, and dynamic engage/escape options.

---

## Mage (Wizard)
**Color scheme:** Royal purple / Deep gold

**Basic Attack - Fireball**
- Fire-type projectile at 450px/s
- Costs mana per shot
- Fast fire rate, aimed direction
- Fire type: explodes balloons on contact (triggers H2 gas release + chain reactions)

**Special - Mana Potion**
- Restores 60% of max mana
- Drink animation with purple glow
- Blue/purple mana particles spiral upward
- Sound: mana_drink.wav

**Charge Attack - Beam of Light**
- Raycast beam in aimed direction
- Range: 200px (min charge) to 500px (max charge)
- Width: 8px to 24px scaled by charge
- Damage: 40-120 total, applied as multi-hit burns (3-8 hits)
- Three-layer glow visual (outer, middle, white-hot core) + sparkle particles
- Knocks enemies back along beam direction
- Sound: beam_fire.wav

**Circle Ability - Air-Walk** (5s duration, 10s cooldown)
- No gravity while active - walk on air
- Drains mana while active
- Sound: airwalk_activate.wav

**Identity:** High sustained damage caster. Glass cannon - lowest HP but fastest mana regen (3.0/s). Mana potion ensures uptime. Beam of Light is devastating fully charged. Air-walk grants unique positioning. Fireballs are fire-type and interact with the balloon/H2 gas system for chain explosions.

---

## Summoner
**Color scheme:** Warm orange / Sunny yellow

**Basic Attack - Homing Mark**
- Fires a slow homing orb that seeks nearest enemy (250px detection)
- On hit: marks target for 6 seconds (orange glow)
- Marked enemies take bonus damage from donut buddies
- Sound: mark_target.wav on hit

**Special - Summon Donut Buddy**
- Costs 30 mana (tower) / 25 mana (overworld)
- Spawns an animated donut companion (max 3 active)
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

Buddies automatically follow summoner, chase enemies within 120px, and attack every 1s.

**Charge Attack - Empowered Donut Buddy**
- Summon a bigger, stronger buddy that scales with charge time
- Costs 40 mana

**Circle Ability - Delegate Mode** (10s duration, 30s cooldown)
- Summoner freezes in trance (purple tint, 0.5 alpha)
- Spawns a ghost delegate that the player controls instead
- Ghost: 1.5x speed, 1.5x jump height, can dash with special button
- All donut buddies follow the ghost instead of the summoner
- Countdown timer displayed above summoner
- Summoner takes 1.5x damage while delegating; hit >= 15 cancels it
- On exit: aether rift teleport VFX, summoner teleports to ghost position

**Identity:** Army builder. Weak alone but powerful with 3 donut buddies + homing marks amplifying damage. Delegate mode enables aggressive buddy positioning.

---

## Rogue
**Color scheme:** Dark crimson / Charcoal black

**Basic Attack - Knife Fan** (3 knives)
- 3 knives thrown in a fan pattern
- 22 damage (tower) / 18 damage (overworld)
- Fast attack (0.1s active window)
- Medium range (18px)

**Special - Shadow Dash**
- Teleports 120px in facing direction
- 0.3 seconds of invincibility (semi-transparent visual)
- Raycasts to walls - won't teleport through them
- Ghost trail VFX at start and end positions
- No mana cost

**Charge Attack - Charged Backstab**
- Teleport behind nearest enemy, massive damage
- Damage scales with charge time

**Circle Ability - Stealth** (5s duration, 20s cooldown)
- Semi-transparent, enemies ignore the rogue
- Take 50% less damage while stealthed
- Attacks from stealth deal 3.75x damage (backstab)
- Sound: stealth_activate.wav

**Identity:** Fastest class (150 speed). Hit-and-run assassin. Stealth + backstab delivers massive burst damage. Shadow dash through danger for repositioning.

---

## Demolitionist
**Color scheme:** Orange-red / Gunmetal grey

**Basic Attack - Throw Bomb**
- Arcs with gravity, bounces once, explodes after 1.5s or on enemy contact
- 25 damage, 60px radius, knockback + screen shake
- Upgradeable: power tiers, blast size tiers, fragment bombs, napalm bombs

**Special - Big Bomb**
- Costs 40 mana
- 50 damage, 90px radius, bigger VFX
- Scales with upgrade tiers

**Charge Attack - Mega Bomb**
- Huge radius + fragments, scales with charge

**Bomb Aspects:**
- Electric (chains to nearby enemies, brief stun)
- Fire (ignites enemies, DoT 3s)
- Impact (massive knockback, lower damage)
- Ice (slows enemies in blast radius)

**Circle Ability - Refuel**
- Hold Circle while grounded to refill rocket fuel
- No auto-refuel on landing - manual refuel only
- Sound: refuel_gurgle.wav

**Rocket Jetpack:**
- Activated by pressing jump a second time after first jump
- 4 seconds of fuel, 800 thrust acceleration, 550 max speed
- Aim direction controls thrust vector
- Drift/spin increases over time (chaos mechanic)
- Out of fuel = crash explosion (damage to self + nearby enemies)
- Sounds: rocket_ignite.wav, rocket_thrust.wav, rocket_crash.wav

**Identity:** Explosive specialist with unique vertical mobility. Rocket jetpack is powerful but dangerous. Bomb upgrades provide build variety.

---

## Healer
**Color scheme:** Soft green / Warm white

**Basic Attack - Healing Potion Throw**
- Throws an arcing potion projectile in aimed direction
- Auto-targets nearest injured ally within 150px (if in aimed direction)
- Potion arcs with bezier curve, creates healing zone on landing
- Healing zone: 40px radius, heals players standing in it over time

**Special - Healing Burst**
- Costs 50 mana
- Heals all allies in 80px radius for 30 HP
- Green pulse VFX expanding outward

**Charge Attack - Channel Heal / Healing Wave**
- Hold attack to channel: continuous 5 HP/s healing aura to nearby allies (80px radius)
- Healer cannot move while channeling, green glow with pulsing ring VFX
- Takes 25% more damage while channeling
- Interrupted by hit: fires burst heal proportional to charge time
- On release (if charged enough): healing blast wave expanding outward
- Wave radius + healing scales with charge duration
- Allies get healed + temporary buff (10% speed + 10% damage for 5s)
- Enemies hit by wave get stunned for 1.5s

**Dash Wave:**
- Dash creates perpendicular wave pulse
- Heals allies and pushes enemies aside

**Circle Ability - Wind Gust** (8s cooldown)
- 100px radius knockback blast (400 force)
- Pushes all enemies away from healer
- Sound: wind_gust.wav

**Identity:** Support class. Healing potion throw + channel heal keep allies alive. Wind gust provides emergency crowd control. Healing burst for clutch saves.

---

## Tank
**Color scheme:** Bronze / Dark iron

**Basic Attack - Heavy Mace Slam**
- 45 damage, very slow (1.2s cooldown)
- Wide attack area in aimed direction
- Damage reduced by 50% while fortified (tradeoff)

**Special - Ground Pound AoE Stun**
- AoE stun around the tank
- Explosion + shield charge sound
- Stuns nearby enemies

**Charge Attack - Massive Shockwave**
- Ground shockwave expanding outward
- Radius: 60px (min) to 160px (max) scaled by charge
- Damage: 20 to 70 scaled by charge
- Bigger than special, longer stun

**Circle Ability - Fortify** (8s duration, 25s cooldown)
- Ignore 60% of incoming damage
- Attack damage reduced by 50% (tradeoff)
- Bronze glow VFX with pulsing, warning flash at 2s remaining
- "FORTIFIED!" floating text on activation

**Identity:** Ultimate tank. Highest HP in the game (250). Slowest movement (70) but nearly unkillable when fortified. Ground pound + shockwave provide crowd control. Best for absorbing boss damage.

---

## Ninja
**Color scheme:** Dark purple / Black

**Basic Attack - Fast Slices** (3-hit sequential)
- 3 fast sequential slices in rapid succession
- Quick attack speed, medium damage per hit
- Flows naturally into movement

**Special - Dive Kick**
- Fast downward kick from air
- Deals damage and bounces ninja upward on hit

**Charge Attack - Meteor Strike**
- Charge while airborne, then slam down as a meteor
- Damage and blast radius scale with charge time
- Devastating from height

**Circle Ability - Air Dash / Item Pickup**
- Dash through the air in aimed direction
- Also pulls nearby items toward the ninja
- Enables rapid aerial repositioning

**Passive - Triple Jump**
- Ninja can jump 3 times before needing to touch ground
- Highest aerial mobility of any class

**Identity:** Fastest aerial class. Triple jump + air dash + dive kick make the ninja unmatched in vertical mobility. Fast slices keep up pressure while meteor strike punishes from above.

---

## Balloonist
**Color scheme:** Sky blue / Bright yellow

**Basic Attack - Balloon Darts**
- Fires darts that spawn physics-based balloons on hit
- Balloons are teardrop-shaped with physics string (12 segments)
- Balloons repulse each other, affected by wind
- 3x fire rate, max 10 balloons active
- Balloon weight system affects entity movement

**Special - Pop All** (Triangle)
- Pops all active balloons simultaneously
- Each pop releases H2 gas that lingers for 25 seconds
- H2 gas ignites on contact with fire or lava, causing chain explosions

**Charge Attack - Giant Balloon**
- Charge to create a larger balloon with more lift
- Scales with charge time

**Circle Ability - Self-Float**
- Attach a balloon to self for temporary flight
- Slowly rises while active
- Can be popped by enemies or fire

**Identity:** Chaos controller. Balloons create battlefield hazards through physics interactions. Pop-and-ignite combos with Mage fireballs enable devastating chain reactions. H2 gas + fire = hydrogen explosions.

---

## Guitarist
**Color scheme:** Electric red / Chrome silver

**Basic Attack - Musical Notes**
- Fires musical note projectiles that travel in a sine wave pattern
- Notes bounce and weave through the air
- Consistent ranged damage with unique trajectory

**Special - Blast Wave** (Triangle)
- 60-degree arc shockwave in aimed direction
- Weight-based push: lighter enemies pushed further
- Uses entity weight system (Bat 5 = far push, Golem 150 = barely moves)

**Charge Attack - Power Chord**
- Charge up a massive sound blast
- Damage and range scale with charge time
- Screen shake on release

**Circle Ability - Amp Up** (15s duration, 30s cooldown)
- Amplifies all attacks with increased damage and effect radius
- Musical VFX intensify during amp mode
- "AMP UP!" floating text on activation

**Sound Design:** Guitar sounds use Karplus-Strong string synthesis for authentic plucked-string tones (guitar_note.wav, guitar_blast.wav).

**Identity:** Rhythm-based fighter with unique sine-wave projectiles. Blast wave leverages the entity weight system for tactical crowd control. Amp Up turns the guitarist into a damage powerhouse.

---

## Werewolf
**Color scheme:** Dark grey / Blood red

**Basic Attack - Triple Claw Slash**
- 3-hit claw combo that shreds enemies
- Each slash spawns 8 blood drop particles
- Fast attack with visceral VFX

**Special - Roar Push**
- 30-degree arc directional roar
- 250px range push effect
- Pushes all enemies in the cone away from werewolf
- Weight-based: lighter enemies pushed further

**Charge Attack - Pounce**
- Charge up and leap at a target
- Distance and damage scale with charge time
- Lands with impact damage in area

**Circle Ability - Frenzy** (8s duration, 35s cooldown)
- Attack speed dramatically increased
- Movement speed boosted
- Blood-red VFX aura, "FRENZY!" floating text
- Claw attacks become even more ferocious during frenzy

**Identity:** Brutal melee brawler. Triple claw slash with blood particles creates visceral combat feel. Roar provides directional crowd control. Frenzy mode turns the werewolf into an unstoppable close-range killer. Second highest HP (200) after Tank.
