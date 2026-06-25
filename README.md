# Edoras Horse

A standalone larger-breed horse mob for **Mineclonia**, with deep locomotion and
behaviour: a four-tier gait system, per-horse speed genetics, hunger/thirst needs
with head-down grazing and drinking, bareback taming, full tack and storage, a
trampling charge, and player-driven recolouring. It uses the **PKZ Horse Rig**
coat textures on an upscaled copy of the canonical Mineclonia horse mesh.

## Features

* **Four-tier manual gaits** — Walk → Trot → Canter → Gallop, each with its own
  animation and speed. Shift up and down through the gaits while riding (see
  *Controls*).
* **Per-horse speed genetics** — every horse rolls a fixed quality level at spawn
  (shown as a 5-star rating in its gear panel) that sets its top speed in each gait.
* **Hunger & thirst** — hunger is a slow biological need; thirst doubles as a
  *sprint resource* drained by galloping. A hungry or parched horse gets balky and
  will refuse the faster gaits, or buck its rider when critical.
* **Grazing & drinking** — an unmounted horse forages: it lowers its head to the
  ground and crops grass spot by spot across a field, and drinks (head down,
  gradually) at water.
* **Swimming** — a riderless horse in deep water swims to the nearest shore and
  idles half-submerged rather than sinking; while ridden it is capped to a walk in
  water.
* **Flee** — when hit by a player it canters away from the attacker.
* **Trampling charge** — a galloping or cantering horse runs down hostile mobs
  (skeletons, spiders, illagers, witches, etc.) in its path, dealing fleshy damage
  scaled by armor and gait. A gallop hits harder than a canter; a diamond-armored
  gallop one-shots light mobs.
* **Taming** — a wild horse must be broken in before it accepts tack. Mount it
  **bareback** (empty hand) to break it in; after a short ride it either accepts
  you (tamed, with heart particles) or bucks you off. Each attempt raises its
  temper, so it grows likelier to settle — and feeding a wild horse helps gentle
  it too.
* **Tack & storage** — a *tamed* horse accepts a saddle, horse armor, and a
  craftable **saddlebag** that unlocks an on-horse storage compartment. Sneak +
  right-click (empty/other item in hand) opens the gear panel with a live
  condition readout.
* **Recolouring** — a tamed horse can be reskinned by hand. Right-click it with
  **redstone dust** to cycle the **base coat**, or with **lapis lazuli** to cycle
  the **markings**. (See *Recolouring* below.)
* **Breeding** — feed two tamed horses to breed a persistent foal.
* **Lead-following** — with the optional `leads` mod, a leashed horse trails the
  player under its own power instead of being dragged.
* **Reduced fall damage** — the heavier breed takes half fall damage.
* **Natural spawning** — populates Plains and Savanna (requires `mobs_mc`).

## Controls

While **riding**:

| Action | Control |
| --- | --- |
| Move forward | hold **W** |
| Shift up a gait (Walk→Trot→Canter→Gallop) | tap **E** |
| Shift down a gait | tap **S** |
| Drop to a walk | release **W** (or hit an obstacle) |
| Dismount | **Sneak** |

On a horse **on the ground**:

| Action | Control |
| --- | --- |
| Tame a wild horse | right-click **empty-handed** to mount bareback |
| Mount a tamed, saddled horse | right-click (empty/normal item in hand) |
| Open the gear/inventory panel | **Sneak + right-click** |
| Recolour the base coat | right-click with **redstone dust** |
| Recolour the markings | right-click with **lapis lazuli** |
| Saddle / armor / saddlebag | right-click with that item |
| Feed / heal / breed | right-click with a follow food (wheat, sugar, apple, hay, carrot, golden apple/carrot) |
| Water (refills thirst) | right-click with a **water bucket** |

Remove the saddle, armor, or bag by taking it out of the gear panel
(**Sneak + right-click**).

> **Note:** because redstone and lapis are intercepted to recolour the horse, you
> **cannot mount it while holding redstone or lapis** — switch to an empty hand or
> another item to ride. The same applies to opening the gear panel.

## Recolouring

A **tamed**, unmounted, adult horse can be reskinned in place, one dye per click:

* **Redstone dust → base coat.** Each right-click advances to the next coat:
  brown → dark brown → white → gray → black → chestnut → creamy → (loops).
* **Lapis lazuli → markings.** Each right-click advances to the next marking:
  none → snowflake appaloosa → sooty → paint → stockings & blaze → (loops).

The coat and markings cycle independently, so you can reach any combination. Each
click consumes one dust and steps exactly once (a 0.5 s debounce stops a held
click from burning the whole stack), so you can preview each look before spending
the next dye. Saddle, armor, and saddlebag overlays are preserved, and the chosen
appearance persists across world reloads. In creative mode no dye is consumed.

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
* **Optional:**
  * `mobs_mc` — natural spawners.
  * `mcl_formspec` — gear-panel slot backgrounds.
  * `leads` — lead-following.

  Recolouring uses redstone (`mcl_redstone`) and lapis (`mcl_core`); all are
  present in any normal Mineclonia install. The mod loads and runs without any
  optional dependency — the related features just stay inactive.

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
