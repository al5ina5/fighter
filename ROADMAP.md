# ROADMAP — Untitled Fight Game (v1)

> Companion to `concept.md`. This is the *how*, step by step.
> Rule: **complete each step fully, verify it runs, commit, THEN move on.** No skipping ahead.

> Architecture update: the battle now uses a deterministic 2D combat simulation
> beneath a side-locked 3D presentation. Early `CharacterBody2D` and `Area2D`
> steps below remain accurate for gameplay; visual references to colored boxes or
> `Camera2D` describe the prototype history. New models follow `MODEL_INTEGRATION.md`.

---

## How to work this roadmap (read this first)

We build one step at a time so nothing ever breaks beyond repair.

**The loop per step (ask the AI to help at each stage):**
1. **Read** the step. Understand the goal and the *Definition of Done*.
2. **Prompt** the AI: "Let's do Roadmap Step N — [step name]. Here's the plan..." and let it
   propose the code/scene.
3. **Review** the AI's output. Don't paste blind — understand every line (you're gonna debug it *later*).
4. **Apply** it in Godot, then **run** the game and test it.
5. **Confirm** it meets the DoD. If yes → **commit** (git) and start the next step.
   If no → fix it *before* moving on. A half-broken step will poison every step after it.

**Golden rules:**
- One step = one session (or a few). Stop at the DoD, don't gold-plate.
- Always `git commit` at the end of a working step. If you break something, you can roll back.
- Test by **hand in the editor**, not just "it compiles." Feel the controls.
- Every step should be runnable — you should always be able to open the project and play *something*.

---

## Suggested project structure

```
fighter/
  project.godot          <- Godot entry
  scenes/
    Menu.tscn
    CharacterSelect.tscn
    Battle.tscn          <- the fight stage
    fighters/
      Swordman/
      Zombie/
      Girl/
      Tank/
  scripts/               <- GDScript files
  assets/
    sprites/
    audio/
    fonts/
  tests/                 <- (optional) GDScript unit tests
```

Add this early (Step 0) and keep it clean — a tidy structure is half of finishing a game.

---

# PHASE 0 — FOUNDATION
*(get the project booting and moving; ~Steps 0–3)*

### Step 0 — Install Godot & create the project
- **Goal:** Godot 4 opens, and you have an empty game window with version control.
- **Tasks:**
  - Download & install **Godot 4** (standard, not mono, unless you'll use C#).
  - `git init` the `fighter/` folder. Add a `.gitignore` for Godot (ignore `.godot/`).
  - Create `project.godot`, set window size to `1280x720`, make the game run at a fixed 60fps.
- **Definition of Done:** You open Godot, the project loads, you press Play and a blank window appears.
- **Verify:** Run → blank window. `git status` shows clean.
- **AI prompt idea:** *"Set up a fresh Godot 4.3 project with a 1280x720 window, 60fps, and a .gitignore. Give me the folder structure and what to click."*

### Step 1 — A moving red rectangle (input & movement)
- **Goal:** One red rectangle (placeholder player) moves with the keyboard.
- **Tasks:**
  - Create `Battle.tscn` with a `CharacterBody2D` player and a `Camera2D`.
  - Add a sprite (just a red `ColorRect` or `Sprite2D` with a placeholder).
  - Add `Player.gd` — reads input (left/right, and a jump) and moves the body.
  - (For a fighter: no side-scroll world — the camera is static, players move freely left/right.)
- **Definition of Done:** A red box you can move left/right and jump with WASD/arrows.
- **Verify:** Play, move the box, it responds smoothly. Jump works.
- **AI prompt idea:** *"Give me a minimal Godot 4 CharacterBody2D that moves left/right and jumps. Include the InputMap keys and the tscn steps."*

### Step 2 — A second rectangle & facing (the 2P foundation)
- **Goal:** Two rectangles can be controlled simultaneously — the couch co-op core.
- **Tasks:**
  - Duplicate the player, give player 2 a different key set (arrows vs WASD).
  - Set up facing: each character faces the other (flip sprite based on relative position).
  - Keep them from overlapping (simple collision or a same-direction push).
- **Definition of Done:** Two boxes, two simultaneous controls, they face each other and can't walk through each other.
- **Verify:** Two players (same keyboard) move independently.

### Step 3 — The fight stage boundaries & arena
- **Goal:** A visually clear arena: floor line, walls, and a camera framing the action.
- **Tasks:**
  - Add a floor (collision) and walls so you can't leave the court.
  - Add a background (a dark undefined shape = placeholder "underground circuit").
  - Center the camera on the midpoint between the two players (or tile horizontally).
- **Definition of Done:** Both players start on the arena floor, can't fall off or leave, camera looks good.
- **Verify:** Play — boxes stay in the arena, background renders.

---

# PHASE 1 — COMBAT SKELETON
*(make the boxes fight ~Steps 4–9)*

### Step 4 — Light & heavy attacks (hitboxes + hurtboxes)
- **Goal:** You can punch and kick, and it connects on the opponent.
- **Tasks:**
  - Give the player state: `idle`, `attack`, `block`, `hurt`.
  - Make a `hitbox` (an `Area2D` in front of the attacker) activate during a swing.
  - Make the opponent a `hurtbox` (`Area2D`). On `area_entered`, register a hit.
  - Two buttons: light (fast, low damage) and heavy (slow, high damage).
- **Definition of Done:** Press attack → an animation/hitbox appears → when close enough it registers a "hit" (print a line and flash the target).
- **Verify:** Play as both (or 1P vs dummy) — swings connect when you're close.

### Step 5 — Health, damage, knockback, hitstop (THE JUICE step)
- **Goal:** Hitting actually hurts and FEELS good. This is where "tactile" starts.
- **Tasks:**
  - Add a total health value and a simple health bar.
  - Apply damage on hit; flash the victim white for a frame.
  - Add **knockback** (push the victim away) and **hitstop** (freeze both for ~50–100ms on connect).
  - Add **screen shake** on hits (scaled by damage weight).
- **Definition of Done:** Hits push, flash, shake the camera, and whittle a health bar down. It *feels* rewarding.
- **Verify:** 1P vs dummy — land hits, see the effects. This is the step that decides if the game is fun.
- **AI prompt idea:** *"Add hitstop, knockback, white-flash, and screen shake to a Godot 2D fighter on hit. Show me how each effect is implemented."*

### Step 6 — Blocking
- **Goal:** Holding back (or a block button) reduces/negates damage.
- **Tasks:**
  - Blocking state: reduces damage, knocks the blocker back slightly (chip damage).
  - Add a block "bar" that depletes, and breaks if it hits zero (guard-break → punish window).
- **Definition of Done:** Blocking cuts damage and prevents hitstun; break creates a real opening.

### Step 7 — Round flow: FIGHT / KO / rematch
- **Goal:** The match has a beginning and an end.
- **Tasks:**
  - State machine: `intro → fight → round-over → rematch`.
  - On KO (health = 0), show "KO", stop input, then a "Rematch?" prompt.
  - Countdown "3, 2, 1, FIGHT" at the start.
- **Definition of Done:** Start, fight, KO, rematch cycle works cleanly.

### Step 8 — Hit reactions & hurt animation
- **Goal:** Getting hit looks right, not just numerically.
- **Tasks:**
  - Hurt pose (tilt back), hitstun duration, and a `recovery` window before you can act again.
  - Damage scaling if you're juggled (avoid infinite combos).
- **Definition of Done:** Getting hit reacts visually, you can't act during hitstun, combos don't loop forever.

### Step 9 — Menu & character select (basic)
- **Goal:** Title screen → pick a character → fight.
- **Tasks:**
  - Title screen with "Start".
  - Character select (even just 2 placeholders now — Swordman & Zombie colored boxes).
  - Wire the selection into the battle.
- **Definition of Done:** Menu → select → battle → win → back to menu.

---

# PHASE 2 — THE LIMB SYSTEM (the core hook)
*(this is what makes your game YOURS ~Steps 10–15)*

### Step 10 — Body-part hit regions (per-limb HP)
- **Goal:** The opponent is now 6 separate hurtboxes: head, torso, L/R arm, L/R leg — each with its own HP.
- **Tasks:**
  - Replace the single hurtbox with a set of `Area2D` parts on the body (matching the sprite's limbs).
  - Each part holds its own `hp` (e.g. arm=40, leg=40, torso=100, head=25 — tune later).
  - A hit now damages whichever specific region it touches.
- **Definition of Done:** Land a hit on the arm → the arm's HP drops (print it), while the torso keeps its own.
- **Verify:** Display part HP numbers on-screen temporarily to confirm each region depletes independently.
- **AI prompt idea:** *"How do I structure a Godot 2D fighter so each body part is a separate hit region with its own HP? Show the node tree and data."*

### Step 11 — Limb loss: disable the move(s) it performed
- **Goal:** When a limb's HP hits zero — it's gone — and the fighter loses everything that limb could do.
- **Tasks:**
  - Define a mapping: `left_arm → [punch1, punch2]`, `left_leg → [kick1]`, etc.
  - On arm/leg death: hide/remove the limb sprite, set a `disabled` flag on those moves.
  - The move list / input returns "no-op" (or a weak stagger) for dead-limb moves.
  - Add a "pop" when it flies off (stylized campy gore).
- **Definition of Done:** Lose an arm → those attacks can't be used. Lose a leg → mobility drops + those kicks go.
- **Verify:** Destroy one limb and confirm the move list genuinely changes. Re-read your design rule **"removes its moves"** — make sure it's REAL, not cosmetic.

### Step 12 — Win by total dismemberment
- **Goal:** A match can end by stripping an opponent of all four limbs (the "dismantle" finish).
- **Tasks:**
  - Track which limbs are gone; if all 4 limb-regions are destroyed → match over (a special finisher).
  - (Design check: does destroying a leg stop the fighter? Where is the "core" — torso/head — stop OR total-limb-loss ends it? Confirm with concept.md Open Q4.)
- **Definition of Done:** You can win by removing all four limbs without killing the core.

### Step 13 — Sever styles: instant-cut vs. bash-to-zero
- **GOAL:** Make the Swordman's *method* feel different from the Tank's. This is the creative gold.
- **Tasks:**
  - **Swordman:** one high-risk, high-payoff move (long windup, easy to whiff) that **instantly severs** a targeted limb on hit.
  - **Tank / Girl:** no instant cut — they only grind a limb's HP to 0 with sustained hits.
  - Make the two feel NOTICEABLY different: risk vs. pressure.
- **Definition of Done:** As each fighter, severing a limb requires a genuinely different approach.

### Step 14 — Zombie: grappler + limb regeneration
- **Goal:** The Zombie's unique survival rule (the ONLY re-generator) is in.
- **Tasks:**
  - Zombie grapple move: grab + hold + grind a specific limb.
  - Zombie regen: over time (or by a successful grab), a lost limb slowly regrows and its moves come back.
  - Rebalance: a regenerating fighter must be punishable so it's not OP.
- **Definition of Done:** Zombie can lose a limb, then get it back; other fighters can't.

### Step 15 — The 4th fighter & distinct limb strategies
- **Goal:** All four fighters are in with distinct color identity + limb strengths (Swordman, Zombie, Girl, Cyber-Kingpin).
- **Tasks:**
  - Implement each character's special move set + limb map.
  - Girl = improvised household weapons (bat, needles — fast, swingy).  Scorpion-level pressure, low per-hit.
  - Tank = no cut, pure heavy pressure, truck damage on one limb.
- **Definition of Done:** 4 selectable fighters, each plays/rehearsals differently around limbs.

---

# PHASE 3 — MAKE IT A REAL GAME
*(~Steps 16–20)*

### Step 16 — Game-feel polish pass (the "tactile" promise)
- **Goal:** Every single hit feels amazing. This is your brother's pitch — don't skip.
- **Tasks — the checklist from concept.md:**
  - Hitstop tuned per move weight · camera shake · SFX on every hit
  - Flash on connect · displacement · lenient input buffer
  - Limb "pop" feels earned · hurt reactions
  - Damage numbers or impact rings on hit (optional but juicy)
- **Definition of Done:** The game is FUN to button-mash even before any strategy — that's game feel.
- **Verify:** Hand-test for 20 minutes; iterate until hitting feels addictive.

### Step 17 — Training mode
- **Goal:** A dummy + readable numbers so players learn the limb system.
- **Tasks:**
  - Dummy (can be set to idle/block).
  - Show hitboxes, per-limb HP readout, and a move list.
- **Definition of Done:** Open training, see exact limb HP, practice severing one arm.

### Step 18 — Audio: trap soundtrack + SFX
- **Goal:** Hip-hop/trap BGM + punchy SFX that match the 80s-campy energy.
- **Tasks:**
  - Implement an audio manager. Loop the theme during fights.
  - Hits, blocks, KO, limb-pop, and menu sounds.
- **Definition of Done:** Music plays, hits sound punchy and satisfying.

### Step 19 — Presentation: 80s campy oneliners & identity
- **Goal:** The tone lands. Color identity of each fighter. Taunts/oneliners on win/KO.
- **Tasks:**
  - Color-scheme per character (matches concept's "distinct silhouette").
  - Win/lose/taunt text — cheesy 80s action one-liners.
  - Pre-fight taglines, campy fonts/effects.
- **Definition of Done:** The game *communicates* campy 80s underground-circuit vibe, not just "boxes fighting."

### Step 20 — Balance pass
- **Goal:** Make all four fighters viable; no single strategy dominates.
- **Tasks:**
  - Numeric tuning: damage, health, speed, move recovery.
  - Playtest each match-up (1v1, all pairings). Note who feels oppressive.
  - Test the limb economy: is a limb loss too punishing (e.g. single arm loss = unwinnable)? Tune the *regener* vs. handicap balance.
- **Definition of Done:** Any fighter can win any matchup with skill.

---

# PHASE 4 — SHIP & BEYOND
*(~Steps 21–23)*

### Step 21 — Menus, settings & packaging polish
- **Goal:** Presentable menus + basic options.
- **Tasks:**
  - Title, character select, rematch screens all look clean.
  - Volume/brightness settings, pause menu, exit.
  - Accessibility: remappable keys, maybe simple difficulty toggles.
- **Definition of Done:** A stranger can boot the game, configure it, and play without confusion.

### Step 22 — Export to PC (Windows/Mac) + localization up
- **Goal:** Produce a runnable standalone build.
- **Tasks:**
  - Export Preset for Windows + Mac via Godot.
  - Test the exported binaries on real machines (not just in-editor).
  - Fix any platform-specific bugs (input, resolution).
- **Definition of Done:** A downloadable file launches and runs the full game on the target OS.

### Step 23 — Package & ship to itch.io
- **Goal:** The game is publicly playable.
- **Tasks:**
  - Create the itch.io page: name, screenshots (with the *gore + limb hook* front and center), a GIF of the fun.
  - Upload the builds. Set a fair price or "pay what you want." Toss in a free demo.
  - Write a short itch description that sells the **limb-by-limb** hook (the pitch, in the pitch).
- **Definition of Done:** Someone with no connection to you downloads, plays, and a new player has fun.

---

## AFTER SHIP (v2+ ideas — NOT v1)
- Optional free-roaming 3D arena mode; the current game deliberately remains 2.5D.
- Online multiplayer (the hardest thing — only after a follow-up game, realistically).
- Story mode / character bios / a proper underground-circuit narrative.
- 5th+ fighters: the **laser/dissolve** type, who erases parts at range.
- Interactive arenas: breakables, floor holes, free weapons.

---

## ⚠️ The 3 rules that keep a beginner game alive

1. **One step at a time.** Don't start Step 6 until Step 5's DoD is met. A step is done when it *runs and feels right*, not when the tabs are open.
2. **Scope discipline.** If something feels too big (full 3D, online, story), cut it — the limb system is your identity, protect it.
3. **Commit every win.** Tiny branches, tiny commits. If it breaks, `git` back. Confidence is a superpower.

---

## Still-open (from concept.md, resolve before/around Step 11)
- **Art era:** resolved as rigged 3D characters in a side-on 2.5D presentation.
- **Title:** `DISARMED` · `CIRCUIT` · `Limbless` · `STUMPED` · `Rack & Ruin` (campy) or something serious.
- **Win condition details:** core = torso+head, or does head-loss = instant round loss? (Step 12 depends on it.)
- **Match format:** single-round is bold. Feel it out in the Step 7 prototype; change if too short.
```
