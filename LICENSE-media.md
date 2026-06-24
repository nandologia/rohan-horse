# Licensing of media and code in `edoras_horse`

This mod is a combination of works under different licenses. Each component
below is governed by the license noted against it. The two full license texts
are bundled in this folder:

* `LICENSE.txt` — GNU General Public License v3 (GPLv3)
* `LICENSE-CC-BY-4.0.txt` — Creative Commons Attribution 4.0 International (CC BY 4.0)

## Model

* `models/edoras_horse.b3d` — **GPLv3**
  * Derived from Mineclonia's `mobs_mc_horse.b3d` (the horse mesh and rig), which
    is by **22i** (https://github.com/22i) and licensed GPLv3. This mod's model is
    a modified copy of that mesh (reshaped hoof geometry and resynthesised
    walk/trot/canter/gallop/idle/graze animations); it remains under GPLv3.
  * Source/generation: see `tools/` (the scripts that build the `.b3d` from the
    upstream mesh). Upstream Blender sources: https://github.com/22i/minecraft-voxel-blender-models

## Textures

* `textures/edoras_horse_black.png`, `..._brown.png`, `..._chestnut.png`,
  `..._creamy.png`, `..._darkbrown.png`, `..._gray.png`, `..._white.png`,
  `..._markings_white.png`, `..._markings_whitefield.png`,
  `..._markings_blackdots.png`, `..._markings_whitedots.png` — **CC BY 4.0**
  * Coat and marking skins from the **PKZ Horse Rig** by **Endertainer007**,
    used verbatim (the files are unchanged; only renamed `horse_*` →
    `edoras_horse_*`). The saddlebags rendered on the horse are part of these coat
    skins.
  * Attribution: *"PKZ Horse Rig by Endertainer007 is licensed under CC BY 4.0."*
    https://creativecommons.org/licenses/by/4.0/

* `textures/edoras_horse_saddlebag.png` — **CC BY 4.0**, by **nando**
  * Original 16×16 inventory icon for the craftable saddlebag item. Not derived
    from any third-party art.

* `textures/edoras_horse_blank.png` — **CC0 / public domain**
  * A blank (uniform/transparent) 128×128 base layer for the texture-overlay
    stack; not a creative work.

## Sounds

The horse sounds are looping per-gait, per-surface hoof clips
(`sounds/edoras_horse_gait_<gait>_<surface>.ogg`), a looping chewing clip
(`edoras_horse_eat_grass.ogg`), and two whinnies (`edoras_horse_neigh.{1,2}.ogg`).
Each was converted to mono, normalised, and (for the loops) crossfade-looped.

All horse sounds come from **BigSoundBank.com** by **Joseph SARDIN**, triple-licensed
**CC0 1.0 / WTFPL / Public Domain** (https://bigsoundbank.com/licenses.html — no
attribution required; credited here as a courtesy). Used for:

* `edoras_horse_gait_walk_dirt`, `…_walk_gravel`, `…_walk_hard`
* `edoras_horse_gait_trot_dirt`, `…_trot_gravel`
* `edoras_horse_gait_canter_dirt`, `…_canter_gravel`
* `edoras_horse_gait_gallop_dirt`, `…_gallop_gravel` — the canter loops sped up to 1.2x
* `edoras_horse_eat_grass`, `edoras_horse_neigh.1`, `edoras_horse_neigh.2`

Surfaces without a dedicated clip fall back in code to that gait's `dirt` loop
(walk has no `sand`; trot, canter, and gallop have no `hard`/`sand`).

Being CC0 / public domain, none of these require attribution and all are freely
redistributable, compatible with the mod's GPLv3 umbrella.

## Code

* `init.lua`, `tools/*.py` — **GPLv3**, by **nando**
  * Original code written against the Mineclonia `mcl_mobs` API. Bundled with the
    GPLv3 model under a single GPLv3 umbrella for the code and model.

## Summary

The mod as a whole is distributed under **GPLv3** (driven by the model and code),
with the coat/marking textures under **CC BY 4.0**. Credit **22i** (model) and
**Endertainer007** (coat textures) when redistributing.
