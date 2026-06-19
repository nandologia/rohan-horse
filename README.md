# Edoras Horse

A standalone larger-breed horse mob for **Mineclonia**, with deep locomotion and
behaviour: a four-tier gait system, per-horse speed genetics, hunger/thirst needs
with head-down grazing and drinking, and a canter flee when struck. It uses the
**PKZ Horse Rig** coat textures on an upscaled copy of the canonical Mineclonia
horse mesh.

## Features

* **Four-tier manual gaits** — Walk → Trot → Canter → Gallop, each with its own
  animation and speed. While riding, hold **W** to move; tap **E** to shift up a
  gait and **S** to shift down. Releasing W (or hitting an obstacle) drops back to
  a walk. **Sneak** to dismount.
* **Per-horse speed genetics** — every horse rolls a fixed quality level at spawn
  (shown as a 5-star rating in its gear panel) that sets its top speed in each gait.
* **Hunger & thirst** — hunger is a slow biological need; thirst doubles as a
  *sprint resource* drained by galloping. A hungry or parched horse gets balky and
  will refuse the faster gaits, or buck its rider when critical.
* **Grazing & drinking** — an unmounted horse forages: it lowers its head to the
  ground and crops grass spot by spot across a field, and drinks (head down,
  gradually) at water.
* **Flee** — when hit by a player it canters away from the attacker.
* **Tack & storage** — saddle, horse armor, and a craftable **saddlebag** that
  unlocks an on-horse storage compartment. Sneak + right-click opens the gear
  panel (with a live condition readout).
* **Natural spawning** — populates Plains and Savanna (requires `mobs_mc`).

## Saddlebag recipe

```
[chest] [     ] [chest]
[leather][leather][leather]
[carpet][carpet][carpet]
```

## Installation

1. Copy the `edoras_horse` folder into your Mineclonia `mods/` directory.
2. Enable **Edoras Horse** in your world's mod configuration.

Get a horse via the creative spawn egg, or wait for one to spawn in grassland.

## Dependencies

* **Required:** `mcl_mobs` (core Mineclonia mob framework).
* **Optional:** `mobs_mc` (natural spawners), `mcl_formspec` (gear-panel slot
  backgrounds). The mod loads and runs without these.

No changes to Mineclonia's own files are required.

## License & credits

This mod combines works under two licenses (full texts bundled as `LICENSE.txt`
and `LICENSE-CC-BY-4.0.txt`; per-file details in `LICENSE-media.md`):

* **Code and model** — GPLv3.
  * The horse mesh is a modified copy of Mineclonia's `mobs_mc_horse.b3d`, which is
    by **22i** (https://github.com/22i) under GPLv3.
* **Coat & marking textures** — CC BY 4.0.
  * *PKZ Horse Rig by **Endertainer007**, licensed under CC BY 4.0*
    (https://creativecommons.org/licenses/by/4.0/). Used verbatim.

Mod by **nando**. When redistributing, keep the GPLv3 model/code terms and credit
22i (mesh) and Endertainer007 (coat textures).
