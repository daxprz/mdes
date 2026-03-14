# Weapon Crafting System - Design Document

## Overview
Each class can craft unique weapons from components found throughout the game.
Weapons are assembled from **3 class-specific components** that combine to determine
stats, visual appearance, and a procedurally generated name.

## Component Structure

### Melee (Swords/Axes/Hammers)
| Slot | Examples | Affects |
|------|----------|---------|
| **Blade** | Cookie Cutter, Candy Cane, Wafer, Pretzel | Base damage, range |
| **Hilt** | Licorice Wrap, Frosting Grip, Waffle Handle | Attack speed, crit chance |
| **Enchantment** | Sprinkle Burst, Icing Coat, Caramel Drip | Special effect on hit |

### Ranged (Crossbows/Bows)
| Slot | Examples | Affects |
|------|----------|---------|
| **Limb** | Breadstick Bow, Churro Arms, Cracker Frame | Damage, projectile speed |
| **String** | Licorice String, Taffy Pull, Caramel Thread | Fire rate, accuracy |
| **Bolt Type** | Toothpick, Candy Spike, Chocolate Arrow | Damage type, pierce |

### Mage (Staves/Wands)
| Slot | Examples | Affects |
|------|----------|---------|
| **Orb** | Gumball, Jawbreaker, Sugar Crystal | Spell damage, mana cost |
| **Staff** | Pocky Stick, Breadstick, Candy Cane | Cast speed, range |
| **Rune** | Frosting Sigil, Sprinkle Circle, Caramel Glyph | Element/effect type |

### Summoner (Totems/Charms)
| Slot | Examples | Affects |
|------|----------|---------|
| **Core** | Donut Hole, Muffin Crumb, Cookie Dough | Summon HP, summon count |
| **Shell** | Frosted Shell, Wafer Case, Candy Coat | Summon defense, duration |
| **Spirit** | Gummy Bear Soul, Marshmallow Ghost, Jelly Spirit | Summon damage, behavior |

### Rogue (Daggers/Shivs)
| Slot | Examples | Affects |
|------|----------|---------|
| **Blade** | Sugar Shard, Candy Sliver, Brittle Edge | Base damage, crit damage |
| **Grip** | Licorice Wrap, Gummy Handle, Toffee Grip | Attack speed, stealth bonus |
| **Poison** | Sour Coating, Bitter Glaze, Spicy Dust | DoT damage, slow effect |

## Rarity Tiers
1. **Common** (white) - Basic components, weak stats
2. **Uncommon** (green) - Better stats, minor bonus
3. **Rare** (blue) - Strong stats, notable bonus
4. **Epic** (purple) - Excellent stats, unique effect
5. **Legendary** (gold) - Boss drops only, game-changing effects

## Name Generation

**Template:** `[Prefix] [Material] [WeaponType] of [Suffix]`

### Prefix Pool (based on rarity + stats)
- Common: Stale, Crumbly, Half-Baked, Soggy, Bland
- Uncommon: Crispy, Toasty, Fresh, Glazed, Buttery
- Rare: Golden, Enchanted, Frosted, Double-Stuffed, Supreme
- Epic: Legendary, Ancient, Mythic, Celestial, Divine
- Legendary: The Almighty, The One True, Dax's Mighty

### Material Pool (from component type)
Gingerbread, Muffin, Cookie, Wafer, Pretzel, Candy, Chocolate, Caramel

### Weapon Type (per class)
- Melee: Sword, Cleaver, Smasher, Blade, Chopper
- Ranged: Crossbow, Launcher, Shooter, Blaster
- Mage: Staff, Wand, Scepter, Rod
- Summoner: Totem, Charm, Bell, Whistle
- Rogue: Dagger, Shiv, Fang, Spike

### Suffix Pool (from enchantment/effect)
Sprinkles, Crumbs, Icing, Frosting, Drizzle, Toppings, Glaze, Crunch

### Example Names
- "Crispy Gingerbread Sword of Sprinkles"
- "Soggy Muffin Dagger of Crumbs"
- "Golden Candy Crossbow of Drizzle"
- "The Almighty Cookie Smasher of Frosting"
- "Half-Baked Wafer Wand of Toppings"

## Crafting Flow
1. Player collects materials from enemies/bosses/muffin shops
2. Player visits crafting station (overworld hub)
3. Player selects 3 components (one per slot)
4. Preview shows resulting weapon name + stats
5. Player confirms → weapon is created
6. Player equips weapon from inventory

## Material Sources
- **Common enemies**: Flour, Sugar, Butter (common components)
- **Tower chests**: Random uncommon-rare components
- **Mini-muffin currency**: Buy components from shop
- **Bosses**: Guaranteed rare+ drops, unique legendary components
- **Secret areas**: Hidden epic components
