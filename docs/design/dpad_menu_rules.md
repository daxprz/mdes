# D-Pad & Menu Input Rules

## Title Screen (Start Screen)

| Input | Action | Limitations |
|-------|--------|-------------|
| D-Pad UP/DOWN | Cycle profiles | None — freely available |
| D-Pad LEFT/RIGHT | Cycle character class | **NO LIMIT** — class switching is unlimited on the title screen |

- Rift tentacle opens once per player if rift is currently inactive
- Rift deactivates normally on its own timer
- **Rift being open does NOT prevent further class selection** on the title screen
- Class selection is never limited on the title screen

## During Gameplay (Playing / Unpaused)

| Input | Action | Limitations |
|-------|--------|-------------|
| D-Pad UP/DOWN | **Nothing** (unmapped) | Must not switch profiles during gameplay |
| D-Pad LEFT/RIGHT | Cycle character class | Limited by rift — one class change per rift cycle |

- Rift status resets at the start of each new level (scene transition)
- Rift status resets when quitting to main menu

## During Gameplay (Paused — Main Menu Showing)

| Input | Action | Limitations |
|-------|--------|-------------|
| D-Pad UP/DOWN | Navigate menu items | Any player can control |
| D-Pad LEFT/RIGHT | **Nothing** | Must not change class while pause menu is open |
| Attack/Jump/Click | Confirm selection | Any player |

### Pause Menu Options
1. RESUME — close menu, continue gameplay
2. SELECT PROFILE — enter profile/class selection mode (see below)
3. QUIT TO MAIN MENU — return to title screen, reset rift status
4. QUIT GAME — exit application

## During Gameplay (Paused — Profile Selection Mode)

Entered by selecting "SELECT PROFILE" from the pause menu.

| Input | Action |
|-------|--------|
| D-Pad UP/DOWN | Cycle profile (same as title screen) |
| D-Pad LEFT/RIGHT | **Nothing** — class selection disabled in profile select mode |
| START (any player) | Exit profile selection, return to pause menu |

- All player HUDs open (popup panels appear with starburst aura)
- Pause menu disappears
- Text at top: "D-Pad: select profile/class. Press START to continue."
- Rift status is **ignored** during profile selection mode
- Class selection is **disabled** — only profile cycling with UP/DOWN
- When exiting: HUDs close, pause menu reappears

## Rift Status Reset Triggers

Rift status (class_change_locked, tentacle_lost, active_tentacle_count) resets on:
1. Scene/level transition (GameManager.state_changed signal)
2. Quit to main menu
3. Profile selection mode (temporarily ignored, not reset)
