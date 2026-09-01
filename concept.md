# Untitled Fight Game — Concept Draft v1

> Status: 🧠 Concept — NOT a work item
> Owners: Brother (brain/concept) · You (tech / AI prompting)
> Engine: Godot · Platform: PC (Windows/Mac) · Ship: itch.io

---

## The One-Line Pitch

> "Every button you press matters. It could mean life, death, or a handicap that
> changes how you play for the rest of the match — and the same is true for your
> opponent. Even as a crippled stump, you still have a chance to retaliate.
> It's the most tactile fighting game we've ever felt."

---

## The Two Design Pillars

1. **Tactile.** Every hit has weight, feedback, and consequence. No filler moves.
2. **Handicap-but-retaliate.** Losing a limb never removes your will to fight —
   it *changes* your game. A one-armed fighter is not dead; they're a different fighter.

---

## The Hook: Limb-by-Limb Health

This is THE mechanic. Imagine Mortal Kombat's fatality energy, UFC's stamina
wears, and Soul Calibur's weapon lethality — fused into **per-body-part HP**.

- Every fighter is broken into hit regions: **head, torso, left arm, right arm,
  left leg, right leg** (nameable later).
- Each region effectively has its own health. Damage concentrates where you land hits.
- When a limb's HP hits zero, it **instantly removes** (snaps off / pops).
- Losing a limb **removes the moves that limb performed**:
  - Lost left arm → you can't use left-arm attacks, can't do two-handed moves.
  - Lost leg → you move slower and lose that leg's kicks.
- **Crucial rule:** the removed limb is permanent *for that match*, EXCEPT for
  characters with their own survival rules (see Zombie → he regenerates).

### How limbs get removed — per-archetype flavor (this is the creative gold)

Not everyone severs the same way. The *method* defines the character:

| Sever style | Example characters | How it plays |
|---|---|---|
| **Precision cut (instant)** | Swordman | High-risk, high-reward moves that *immediately* sever a limb. Hard to land, devastating when they do. |
| **Bash to zero (gradual)** | Cyber-Kingpin tank, Girl | Can't sever outright — they batter a limb until its HP hits 0 and it pops off. Requires sustained pressure. |
| **Dissolve / dissipate** | (future laser-type) | Erases body parts at range. Not in the core 4 — parked for a candidate. |

Design rule: **the harder a limb is to sever, the more your character is built
around a different limb strategy.** A grappler wants to hold you still and grind
one arm; a sword wants one clean, risky chop.

### How you WIN a round

Either of these ends it:

- **Deplete the core** — destroy the opponent's torso/head core.
- **Total dismemberment** — remove all of a fighter's limbs (the "dismantle" finish,
  your flavor of fatality).

**Match format:** **single round**, sudden death. No carry-over, no best-of-3 —
one round, maximum stakes. (This is a bold choice and it fits the pitch; we can
reconsider if it feels too short on test.)

---

## The Roster — Core 4

Planned 4 fighters, ~color-scheme identity (MK-style distinct silhouettes), each
with a **focused limb strategy**. Names are placeholders — bring backstories later
if we want (see Open Questions).

### 1. The Swordman — `precision sever`
- **Identity:** cool steel/charcoal. Elusive, reads like a duelist.
- **Method:** insta-sever on risky high-payoff moves. The only true "can cut on demand" fighter.
- **Hook:** low HP, high skill. A clean cut wins a limb instantly.

### 2. The Zombie — `grappler + regen`
- **Identity:** sickly green, shambling weight.
- **Method:** bash to zero, but with grapple-specialty. Can hold you down and grind a limb.
- **Survival rule:** the ONE character who regenerates lost limbs (slowly). Losing a limb is
  a temporary setback — a comeback engine built into his kit.

### 3. The Girl — `scrappy improvised weapons`
- **Identity:** bright pink/yellow, *"cutsey but deadly"* — Lollipop Chainsaw energy.
- **Method:** she *acts* like she shouldn't be in the ring, then fights with household
  junk: yarn, a bat, knitting needles, whatever's in reach.
- **Hook:** fast, swingy, low damage-per-hit but brutal at pressuring a single limb.
  The "plucky underdog" archetype.

### 4. The Cyber-Kingpin — `heavy tank brawler`
- **Identity:** big red/black silhouette, rings on his fingers, cybernetic.
- **Concept: a realistic Kingpin.** No blade — he's a mountain of muscle.
- **Method:** cannot sever instantly at all. He *beats* limbs to pieces. Every hit is a
  truck. You don't cut on him; you grind.
- **Hook:** slow, huge damage, a walking pressure wall. Forces a different rhythm.

---

## World & Tone

- **Setting:** **modern underground fight circuit** — secret clubs, fixed in
  basement arenas, money and survival on the line.
- **Tone:** **campy 80s action** — over-the-top oneliners, B-movie energy, self-aware,
  as if an action hero said it and a synthwave camera snapped to it.
- **Audio:** **hip-hop / trap** — bass-heavy, trunk-rattling; cuts the arena like an
  underground invitational.
- **Gore:** **stylized / campy.** Big spray particles, dismember with a satisfying
  "pop" — splashy and fun, not grim and realistic. Stays on-brand with the 80s energy.

---

## Arenas

- **Static walls (v1).** No breakables, no free weapons yet. Environment is presentation,
  not physics — we pour effort into the *limb* mechanic instead.

---

## Controls & Perspective

**Roadmap split: build it 2D first, go 3D later.**

- **v1:** **2D side-view fighter.** Left/right movement, maybe a small forward/back
  depth for sidesteps. This is how beginners actually finish a fighting game, and it's
  where the limb mechanic can be clearly read and felt.
- **Later:** explore **full 3D arena** (the Soul Calibur dream) once the 2D core is
  tight and the limb system is proven. Sister always asks: *is the fun already there in 2D?*
  Yes → THEN spend months on 3D. Don't jump to 3D before the fun exists.

> ⚠️ Trade-off to lock in: earlier you picked "stylized low-poly 3D" art, but chose **2D**
> gameplay. For a beginner Godot v1, **2D sprite/pixel art** is by far the surest path.
> Decision, when ready: build 2D art first, and let low-poly 3D be the *later* 3D era
> art style. (Open Question #2.)

---

## Game Modes — v1

- **Local 2-player versus** (the core — couch play).
- **Training mode** — CPU dummy, hitbox display, move list, limb-HP readout so the
  mechanic can be learned.

---

## Ground Game

- Mostly **stand-up.** Only the **Zombie** has a grappling mechanic (hold, grind a limb).
  Everyone else stays on their feet — keeps scope tight.

---

## Tech & Art Approach (beginner-safe)

- **Engine:** **Godot 4** + **GDScript.** Free, docs-rich, great 2D tooling, exports
  to PC easily. Zero licensing cost.
- **Art:** 2D sprites/pixel art for v1 (see trade-off above). Low-poly 3D is the future era.
- **Scope discipline:** this is the most important rule. We finish 4 characters and
  1 tight mechanic well, rather than 10 characters badly.

---

## 🔒 Scope Guardrails — what we are NOT doing in v1

- ❌ Online multiplayer (hardest thing in fighting games — defer entirely).
- ❌ 3D fighter movement (2D first).
- ❌ Story mode / cinematic campaigns (maybe v2).
- ❌ Breakable/interactive arenas (static walls).
- ❌ More than 4 fighters.
- ❌ A full healthbar + limb-gauge UI clutter (damage reads on the model itself).

---

## Game Feel Checklist (the "tactile" promise lives or dies here)

The brother's pitch is *tactile*. Don't ship until these all feel right:
- **Hitstop** — brief freeze on every connect. JUICY.
- **Camera shake** scaled to move weight.
- **SFX on every single hit** — loud, weighty, satisfying.
- **Flash/white-pulse** on the victim.
- **Varying attack weight** — a heavy feels heavy, a jab feels snappy.
- **Displacement** — characters get pushed by hits.
- **Lenient input buffer** — spongy input makes beginners feel good.
- **Limb "pop"** — when a limb flies off, it should feel *earned*.

---

## Roadmap (milestones, beginner-friendly)

1. **Prototype** — 2 colored boxes, movement (L/R), light/heavy/block, placeholder shove.
   Call it done when a hit feels even 60% fun.
2. **Limb system core** — body hit regions, per-limb HP, "disable the move linked to that limb."
3. **Two full fighters** — Swordman + one other, with distinctive limb loss.
4. **Game-feel pass** — the checklist above. This is where the magic appears.
5. **Versus + round flow** — start screen, character select, "FIGHT", win / dismember / lose.
6. **Training mode** — dumbbot + move/limb readouts.
7. **Audio + campy oneliners** — trap soundtrack, taunts, comment lines.
8. **Polish & package** — menus, balance, quit cleanly, ship **to itch.io**.

---

## Open Questions / Parking Lot (answer later, not now)

1. **Title.** Campy 80s underground + limbs. Starter ideas:
   `DISARMED` · `CIRCUIT` · `Limbless` · `STUMPED` · `Rack & Ruin` · `One-Armed`
   or lean real: `FIGHT CLUB: underground`. (Pick a lane: serious vs comedy.)
2. **Art era.** Confirm: 2D art for v1, low-poly 3D for the later 3D era. Yes/No.
3. **Limb-region naming** head/torso/L/R arm/L/R leg — or something more flavorful?
4. **Core = torso + head only**, or does losing certain limbs *also* nudge the win
   condition (e.g. head loss = instant round loss)? Ballot needed.
5. **Story/character bios** — self-contained combatants, or a connected underworld lore?
6. **Roster 2.0** — laser/dissolve character is a 5th to grow into once limbs feel great.
7. **Do we want a single-round format, or is that TOO short?** We'll feel it out in prototype.
