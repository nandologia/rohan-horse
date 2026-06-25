--[[
	Edoras Horse -- a standalone Mineclonia horse mob, a larger breed built on
	the canonical horse mesh with a deeper behaviour/physics model.

	Uses the canonical horse mesh (mobs_mc_horse.b3d, copied here as
	edoras_horse.b3d, then re-animated by tools/make_anim.py) because the
	supplied coat textures share the exact Minecraft/Mineclonia horse UV layout
	(128x128). The mesh exposes three texture layers, applied in order: chest
	overlay, fur (base coat + optional markings), saddle overlay; and a
	three-segment leg rig (hip/shoulder -> knee/hock -> fetlock).

	This is a separate mob owned by this mod, so a Mineclonia update cannot
	remove it. Done: tack/armour, riding, breeding, saddlebag, natural
	spawning, and a synthesised four-tier gait set (walk/trot/canter/gallop).
	Phase roadmap (deeper behaviour): biological needs (hunger/thirst),
	ambient idles + sleep + manure, herd/aggression dynamics, foal imprinting.

	Coat textures: PKZ Horse coats from Edoras1 (CC BY 4.0).
]]

local S = core.get_translator("edoras_horse")
local mob_class = mcl_mobs.mob_class

local BLANK = "edoras_horse_blank.png"

-- Base coats and overlay markings, mirroring the canonical horse atlas.
local horse_base = {
	"edoras_horse_brown.png",
	"edoras_horse_darkbrown.png",
	"edoras_horse_white.png",
	"edoras_horse_gray.png",
	"edoras_horse_black.png",
	"edoras_horse_chestnut.png",
	"edoras_horse_creamy.png",
}

local horse_markings = {
	"", -- none
	"edoras_horse_transparent.png",         -- none (transparent overlay) -- weights
	                                        -- the roll further toward unmarked coats
	"edoras_horse_markings_whitedots.png",  -- snowflake appaloosa
	"edoras_horse_markings_blackdots.png",  -- sooty
	"edoras_horse_markings_whitefield.png", -- paint
	"edoras_horse_markings_white.png",      -- stockings and blaze
}

-- Every coat x marking combination, as a 3-layer texture set the mesh expects.
-- The engine assigns one of these at random per spawned horse.
local horse_textures = {}
for b = 1, #horse_base do
	for m = 1, #horse_markings do
		local fur = horse_base[b]
		if horse_markings[m] ~= "" then
			fur = fur .. "^" .. horse_markings[m]
		end
		table.insert(horse_textures, {
			BLANK, -- chest overlay
			fur,   -- base coat + markings
			BLANK, -- saddle overlay
		})
	end
end

-- Distinct marking overlays to cycle through when re-skinning a horse with
-- redstone (see horse:cycle_markings). The transparent overlay is dropped: it is
-- only a spawn-weighting duplicate of "none", so it'd show as a wasted "no
-- change" step. cycle_index maps an overlay filename ("" for none) -> its slot.
local marking_cycle = {}
local cycle_index = {}
for _, m in ipairs (horse_markings) do
	if m ~= "edoras_horse_transparent.png" and not cycle_index[m] then
		marking_cycle[#marking_cycle + 1] = m
		cycle_index[m] = #marking_cycle
	end
end

-- Base coats to cycle through when recolouring with glowstone dust (see
-- horse:cycle_coat). coat_index maps a base filename -> its slot.
local coat_cycle = {}
local coat_index = {}
for _, b in ipairs (horse_base) do
	if not coat_index[b] then
		coat_cycle[#coat_cycle + 1] = b
		coat_index[b] = #coat_cycle
	end
end

-- Minimum seconds between re-skin steps: on_rightclick repeats while the button
-- is held, so without this a single press would cycle (and spend) all the dust.
local RESKIN_CD = 0.5

local horse = {
	description = S("Edoras Horse"),
	type = "animal",
	_spawn_category = "creature",
	runaway = true,
	-- Flee speed when hit (movement_speed * this). Default 1.25 was a skating
	-- "fast walk"; 0.85 (~5.7 bps) matches the canter the horse flees with.
	run_bonus = 0.85,
	hp_min = 15,
	hp_max = 30,
	xp_min = 1,
	xp_max = 3,
	-- Edoras horses are a larger, more imposing breed: the canonical mesh +
	-- collision box (visual_size 3.0, half-width 0.69825, height 1.6) scaled
	-- up by ~1.2. The seat (driver_attach_at) is in model-local units so it
	-- rides up with the mesh automatically; only the camera eye_offset and
	-- step/eye heights are retuned below.
	collisionbox = {-0.8379, 0, -0.8379, 0.8379, 1.92, 0.8379},
	visual = "mesh",
	mesh = "edoras_horse.b3d",
	visual_size = {x = 3.6, y = 3.6},
	textures = horse_textures,
	makes_footstep_sound = true,
	movement_speed = 6.75,
	floats = 1,
	-- Calm, confined idle behaviour: approach food at a walk (not a sprint),
	-- and wander only a few blocks at a slow pace rather than freezing.
	follow_bonus = 0.4,   -- food-follow speed = movement_speed * this (was 1.2)
	pace_bonus = 0.35,    -- slow wandering
	pace_width = 3,       -- stay within ~3 blocks horizontally
	pace_height = 2,
	pace_chance = 60,     -- wander a bit more often than the default 120
	pace_interval = 8,
	-- Riding / saddle. With steer_class = "controls", mcl_mobs drives the
	-- mob with the rider's WASD + look direction for free once attached;
	-- drive speed = movement_speed * drive_bonus (default 1.0).
	jump = true,
	-- Base launch velocity (used wild / un-driven). While ridden, horse:drive
	-- overrides this per gait so a gallop leaps higher/farther than a trot.
	-- NB mob gravity is ~32 m/s^2 (fall_speed -1.6 / MC tick), so apex height in
	-- nodes ~= jump_height^2 / 64: jh 6 only cleared ~0.56 node (couldn't make a
	-- 1-block hop); the GAITS values below are sized to clear 1.3-2.4 nodes.
	jump_height = 10,
	stepheight = 1.1,    -- taller breed clears a little more
	-- Fall protection. Forking from a plain mob table left these at the generic
	-- mob_class defaults (safe 3.0 / mult 1.0); a clean gallop jump apexes at
	-- ~13^2/64 = 2.6 nodes (just under 3.0, so no harm), but with the jump key
	-- HELD the horse can re-contact terrain mid-ascent and fire a second jump
	-- (physics.lua jump_timer is only 0.2s vs ~0.8s airtime), stacking to ~4
	-- nodes and taking fall damage on landing. Match the canonical mobs_mc horse
	-- so a tall/double hop is survivable.
	_safe_fall_distance = 6.0,
	fall_damage_multiplier = 0.5,
	head_eye_height = 1.82,
	can_ride_boat = false,
	steer_class = "controls",
	-- Force server-side driving so self.driver is always set (client-side
	-- CSM mounting returns before setting it, which would break our
	-- right-click / sneak dismount). Can revisit for smoother prediction.
	_csm_driving_enabled = false,
	saddle = "no",
	drops = {
		{
			name = "mcl_mobitems:leather",
			chance = 1,
			min = 0,
			max = 2,
			looting = "common",
		},
	},
	sounds = {
		-- provided by mobs_mc (always loaded under Mineclonia)
		random = "mobs_mc_horse_random",
		damage = "mobs_mc_horse_hurt",
		death = "mobs_mc_horse_death",
		eat = "mobs_mc_animal_eat_generic",
		distance = 16,
	},
	-- Frame ranges authored by tools/make_anim.py into edoras_horse.b3d.
	-- All synthesised: walk 0-40 (true 4-beat) + trot 179-207 + canter 49-73 +
	-- gallop 79-99 + idle 109-169. Four-tier driven gait: see horse:drive.
	-- walk_speed lowered 25->18 so the slow walk doesn't out-cycle the trot.
	animation = {
		stand_start  = 109, stand_end  = 169, stand_speed  = 12,
		walk_start   = 0,   walk_end   = 40,  walk_speed   = 18,
		trot_start   = 179, trot_end   = 207, trot_speed   = 30,
		canter_start = 49,  canter_end = 73,  canter_speed = 38,
		run_start    = 79,  run_end    = 99,  run_speed    = 34,
		graze_start  = 209, graze_end  = 249, graze_speed  = 15,
		buck_start   = 259, buck_end   = 289, buck_speed   = 45,
	},
	follow = {
		"mcl_farming:wheat_item",
		"mcl_core:sugar",
		"mcl_core:apple",
		"mcl_farming:hay_block",
		"mcl_core:apple_gold",
		"mcl_core:apple_gold_enchanted",
		"mcl_farming:carrot_item_gold",
		"mcl_farming:carrot_item",
	},
}

function horse:on_breed (parent2)
	local pos = self.object:get_pos()
	local child = mcl_mobs.spawn_child(pos, self.name)
	if child then
		child:get_luaentity().persistent = true
	end
	-- Return false so the engine's own beget_child stops here and does
	-- NOT spawn a second foal. Older Mineclonia (gondor, release 33876)
	-- spawns its own child after on_breed and copies a parent's
	-- base_texture onto it -- and a saddled parent's base_texture carries
	-- the saddle overlay layer, so that extra foal renders saddled.
	-- Newer Mineclonia (local) ignores the return value, so this is safe.
	return false
end

------------------------------------------------------------------------
-- Saddle, armor + riding.
------------------------------------------------------------------------

local SADDLE_SLOT = 1
local ARMOR_SLOT = 2
local BAG_SLOT = 3
local STORAGE_SIZE = 15            -- 5 x 3, like a horse's chest in Minecraft
local SADDLEBAG_ITEM = "edoras_horse:saddlebag"

-- Edoras-only armor reskins: when one of these vanilla armor items is worn, the
-- horse's armor overlay uses OUR texture instead of the item's stock
-- _horse_overlay_image. Render-time only -- it touches no item definitions, so
-- vanilla horses (and players' existing armor stacks) are unaffected; players just
-- equip the armor they already have. Any name not listed (or whose file is missing)
-- falls back to the vanilla overlay in refresh_textures. Ship the PNGs in
-- textures/ under these mod-prefixed names.
local ARMOR_OVERLAY = {
	["mcl_mobitems:leather_horse_armor"] = "edoras_horse_armor_leather.png",
	["mcl_mobitems:copper_horse_armor"]  = "edoras_horse_armor_copper.png",
	["mcl_mobitems:iron_horse_armor"]    = "edoras_horse_armor_iron.png",
	["mcl_mobitems:gold_horse_armor"]    = "edoras_horse_armor_gold.png",
	["mcl_mobitems:diamond_horse_armor"] = "edoras_horse_armor_diamond.png",
	-- Our own loot-only armor (registered below); not a reskin of a vanilla item.
	["edoras_horse:knight_horse_armor"]  = "edoras_horse_armor_knight.png",
}

local function is_saddle_item (stack)
	return stack:get_name () == "mcl_mobitems:saddle"
end

local function is_bag_item (stack)
	return stack:get_name () == SADDLEBAG_ITEM
end

-- Horse-armor items carry a "horse_armor" group whose value is the fleshy
-- armor level to apply (lower = more protection); 0 means "not armor".
local function horse_armor_level (stack)
	return core.get_item_group (stack:get_name (), "horse_armor")
end

-- Rebuild the 3-layer texture set (chest, fur+armor, saddle).
-- Layer 2 is the coat with any armor overlay on top; layer 3 exposes the saddle
-- mesh by giving it the coat texture (which holds the saddle pixels), or BLANK to
-- hide it. _naked_fur preserves the bare coat across equips.
function horse:refresh_textures ()
	local fur = self._naked_fur or (self.base_texture and self.base_texture[2])
	if not fur then return end
	self._naked_fur = fur
	local body = fur
	if self._armor and self._armor ~= "" then
		local name = ItemStack(self._armor):get_name ()
		-- Prefer our Edoras reskin; fall back to the item's stock overlay.
		local overlay = ARMOR_OVERLAY[name]
		if not overlay then
			local def = core.registered_items[name]
			overlay = def and def._horse_overlay_image
		end
		if overlay then
			body = body .. "^" .. overlay
		end
	end
	local saddled = self.saddle == "yes"
	-- Layer 1 is the donkey-style chest overlay: the mesh has chest boxes whose
	-- UV samples the coat texture, so giving it the coat reveals the saddlebag
	-- (mobs_mc does the same for a donkey's chest). Layer 3 likewise shows the
	-- saddle. _naked_fur preserves the bare coat across equips.
	local tex = {
		self:has_bag () and fur or BLANK,  -- chest / saddlebag overlay
		body,                              -- coat (+ armor overlay)
		saddled and fur or BLANK,          -- saddle overlay
	}
	self.base_texture = tex
	self:set_textures (tex)
end

-- Re-skin: swap the marking overlay for the next one in marking_cycle, keeping
-- the base coat colour. The new coat is written through _naked_fur, so it flows
-- through refresh_textures (preserving any saddle/armor/bag overlays) and the
-- updated base_texture persists in staticdata across reloads. Returns the new
-- overlay filename ("" for none) for caller feedback.
function horse:cycle_markings ()
	local fur = self._naked_fur or (self.base_texture and self.base_texture[2])
	-- base coat = everything before the first overlay; current overlay = the last.
	local base = fur and fur:match ("^[^%^]+") or horse_base[1]
	local overlay = fur and fur:match ("%^([^%^]+)$") or ""
	local pos = (cycle_index[overlay] or 1) % #marking_cycle + 1
	local marking = marking_cycle[pos]
	self._naked_fur = (marking ~= "") and (base .. "^" .. marking) or base
	self:refresh_textures ()
	core.sound_play ("mcl_armor_equip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
	return marking
end

-- Recolour: swap the base coat for the next one in coat_cycle, keeping the
-- current marking overlay. Mirrors cycle_markings (writes through _naked_fur so
-- saddle/armor/bag overlays survive and the new base_texture persists). Returns
-- the new base coat filename.
function horse:cycle_coat ()
	local fur = self._naked_fur or (self.base_texture and self.base_texture[2])
	-- base coat = everything before the first overlay; current overlay = the last.
	local base = fur and fur:match ("^[^%^]+") or horse_base[1]
	local overlay = fur and fur:match ("%^([^%^]+)$") or ""
	local pos = (coat_index[base] or 1) % #coat_cycle + 1
	local coat = coat_cycle[pos]
	self._naked_fur = (overlay ~= "") and (coat .. "^" .. overlay) or coat
	self:refresh_textures ()
	core.sound_play ("mcl_armor_equip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
	return coat
end

-- Equip / remove. These do not move items; callers handle item transfer.
-- Only ever called on an already-tamed horse (callers gate on self.tamed); a wild
-- horse must be broken in first (see the taming section).
function horse:apply_saddle ()
	self.saddle = "yes"
	self:refresh_textures ()
	core.sound_play ("mcl_armor_equip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
end

function horse:clear_saddle ()
	self.saddle = "no"
	self:refresh_textures ()
	core.sound_play ("mcl_armor_unequip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
end

function horse:apply_armor (stack)
	local level = horse_armor_level (stack)
	if level <= 0 then return false end
	self._armor = stack:to_string ()
	local agroups = self.object:get_armor_groups ()
	agroups.fleshy = level
	self.object:set_armor_groups (agroups)
	self:refresh_textures ()
	local def = stack:get_definition ()
	local snd = def and def.sounds and def.sounds._mcl_armor_equip
	core.sound_play (snd or "mcl_armor_equip_leather", {
		gain = 0.5, max_hear_distance = 12, pos = self.object:get_pos (),
	}, true)
	return true
end

function horse:clear_armor ()
	local def = ItemStack (self._armor):get_definition ()
	self._armor = ""
	local agroups = self.object:get_armor_groups ()
	agroups.fleshy = 100
	self.object:set_armor_groups (agroups)
	self:refresh_textures ()
	local snd = def and def.sounds and def.sounds._mcl_armor_unequip
	core.sound_play (snd or "mcl_armor_unequip_leather", {
		gain = 0.5, max_hear_distance = 12, pos = self.object:get_pos (),
	}, true)
end

-- Saddlebag: an equippable bag that unlocks a storage compartment carried by
-- the horse. The contents live in self._saddlebag (a list of itemstrings),
-- which persists with the mob's staticdata across unload/reload.
function horse:has_bag ()
	return (self._bag or "") ~= ""
end

-- Only ever called on an already-tamed horse (callers gate on self.tamed).
function horse:apply_bag ()
	self._bag = SADDLEBAG_ITEM
	self:refresh_textures ()
	core.sound_play ("mcl_armor_equip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
end

function horse:clear_bag ()
	self._bag = ""
	self:refresh_textures ()
	core.sound_play ("mcl_armor_unequip_leather", {
		gain = 0.5, max_hear_distance = 8, pos = self.object:get_pos (),
	}, true)
end

function horse:storage_is_empty ()
	if not self._saddlebag then return true end
	for _, s in ipairs (self._saddlebag) do
		if s ~= "" then return false end
	end
	return true
end

-- Serialize the detached storage list back onto the mob so it persists.
function horse:save_storage (inv)
	local t = {}
	for i = 1, STORAGE_SIZE do
		t[i] = inv:get_stack ("storage", i):to_string ()
	end
	self._saddlebag = t
end

------------------------------------------------------------------------
-- Inventory GUI (saddle, armor, bag slots + saddlebag storage + a condition
-- panel). Open with sneak + right-click; take items out to remove them, drop
-- them in to equip. The condition panel (health/hunger/thirst + speed) is a
-- snapshot built from the mob's own state -- no dependency on game HUD mods.
------------------------------------------------------------------------

-- Slot-background images (the base-game inventory "boxes") behind a w*h grid at
-- (x,y), matching list[] coords exactly. Degrades to nothing on an older
-- Mineclonia that lacks the v4 helper (so the lists still work, just unframed).
local function slot_bg (x, y, w, h)
	if mcl_formspec and mcl_formspec.get_itemslot_bg_v4 then
		return mcl_formspec.get_itemslot_bg_v4 (x, y, w, h)
	end
	return ""
end

-- Append a labeled progress bar ("Label: v / max" over a filled box) to fs.
local function fs_stat_bar (fs, x, y, w, label, value, maxv, color)
	local frac = (maxv > 0) and math.max (0, math.min (1, value / maxv)) or 0
	fs[#fs + 1] = string.format ("label[%g,%g;%s]", x, y,
		core.formspec_escape (string.format ("%s: %d / %d", label, value, maxv)))
	fs[#fs + 1] = string.format ("box[%g,%g;%g,0.3;#00000088]", x, y + 0.28, w)
	if frac > 0 then
		fs[#fs + 1] = string.format ("box[%g,%g;%g,0.3;%s]", x, y + 0.28, w * frac, color)
	end
end

function horse:inv_formspec (inv_name, has_bag)
	local list = core.formspec_escape ("detached:" .. inv_name)
	local fs = {
		"formspec_version[4]",
		"size[12.2,11.3]",
		"label[0.6,0.5;" .. core.formspec_escape (S("Edoras Horse")) .. "]",
		"label[0.6,1.1;" .. core.formspec_escape (S("Saddle")) .. "]",
		slot_bg (0.6, 1.4, 1, 1),
		"list[" .. list .. ";main;0.6,1.4;1,1;0]",
		"label[0.6,2.6;" .. core.formspec_escape (S("Armor")) .. "]",
		slot_bg (0.6, 2.9, 1, 1),
		"list[" .. list .. ";main;0.6,2.9;1,1;1]",
		"label[0.6,4.1;" .. core.formspec_escape (S("Bag")) .. "]",
		slot_bg (0.6, 4.4, 1, 1),
		"list[" .. list .. ";main;0.6,4.4;1,1;2]",
	}
	if has_bag then
		fs[#fs + 1] = "label[2.5,1.1;" .. core.formspec_escape (S("Saddlebag")) .. "]"
		fs[#fs + 1] = slot_bg (2.5, 1.4, 5, 3)
		fs[#fs + 1] = "list[" .. list .. ";storage;2.5,1.4;5,3;]"
	end

	-- Condition panel (right column): health / hunger / thirst + speed quality
	-- and this horse's per-gait top speeds. A snapshot as of opening.
	local props = self.object:get_properties ()
	local maxhp = math.floor ((props and props.hp_max) or self.hp_max or 30)
	local hp = math.floor ((self.health or maxhp) + 0.5)
	local hunger = math.floor ((self._hunger or 0) + 0.5)
	local thirst = math.floor ((self._thirst or 0) + 0.5)
	local sp = self:gait_speeds ()   -- {walk, trot, canter, gallop} blocks/sec
	-- Right of the saddlebag (which ends ~x=8.5): narrow bars, pushed right.
	local px, pw = 8.8, 2.6
	fs[#fs + 1] = "label[" .. px .. ",0.9;" .. core.formspec_escape (S("Condition")) .. "]"
	fs_stat_bar (fs, px, 1.4, pw, S("Health"), hp,     maxhp, "#d83a3a")
	fs_stat_bar (fs, px, 2.3, pw, S("Hunger"), hunger, 100, "#e0902a")  -- NEED_MAX
	fs_stat_bar (fs, px, 3.2, pw, S("Thirst"), thirst, 100, "#2f8fe0")  -- NEED_MAX
	-- Speed grade is a FIXED genetic roll (spawn-only; no training mechanic), so
	-- show it as a 5-star rating, not a fillable bar. ceil splits [0,1] into five
	-- even 0.2 buckets -> 1-5 stars. Glyphs are raw UTF-8 (LuaJIT has no \u escape).
	local stars = math.max (1, math.min (5, math.ceil ((self._speed_level or 0.5) * 5)))
	local star_full  = string.char (0xE2, 0x98, 0x85)   -- "★"
	local star_empty = string.char (0xE2, 0x98, 0x86)   -- "☆"
	fs[#fs + 1] = string.format ("label[%g,4.1;%s]", px, core.formspec_escape (
		S("Speed") .. ": " .. string.rep (star_full, stars)
		.. string.rep (star_empty, 5 - stars)))
	fs[#fs + 1] = string.format ("label[%g,4.5;%s]", px, core.formspec_escape (
		S("Top speed (m/s)")))
	fs[#fs + 1] = string.format ("label[%g,4.9;%s]", px, core.formspec_escape (
		string.format ("%s %.1f  %s %.1f", S("Walk"), sp[1], S("Trot"), sp[2])))
	fs[#fs + 1] = string.format ("label[%g,5.3;%s]", px, core.formspec_escape (
		string.format ("%s %.1f  %s %.1f", S("Canter"), sp[3], S("Gallop"), sp[4])))

	-- Player main inventory: slots 9-35 in the upper 3x9 block, hotbar (0-8) below.
	-- 3x9 bottom row ends ~y=9.3 (5.8 + 2*1.25 + 1.0), clearing the hotbar at 9.55.
	fs[#fs + 1] = slot_bg (0.6, 5.8, 9, 3)
	fs[#fs + 1] = "list[current_player;main;0.6,5.8;9,3;9]"
	fs[#fs + 1] = slot_bg (0.6, 9.55, 9, 1)
	fs[#fs + 1] = "list[current_player;main;0.6,9.55;9,1;0]"
	fs[#fs + 1] = "listring[" .. list .. ";storage]"
	fs[#fs + 1] = "listring[current_player;main]"
	return table.concat (fs)
end

function horse:open_inventory (clicker)
	local name = clicker:get_player_name ()
	local inv_name = "edoras_horse_inv_" .. name
	local this = self
	self:init_needs ()      -- so the condition panel shows real values
	self:init_genetics ()
	local function refresh ()
		core.show_formspec (name, "edoras_horse:inv",
			this:inv_formspec (inv_name, this:has_bag ()))
	end
	local inv = core.create_detached_inventory (inv_name, {
		-- Allow rearranging within the storage compartment only.
		allow_move = function (inv, from_list, from_index, to_list, to_index, count)
			return (from_list == "storage" and to_list == "storage") and count or 0
		end,
		allow_put = function (inv, listname, index, stack)
			if listname == "storage" then
				return this:has_bag () and stack:get_count () or 0
			end
			if not inv:get_stack (listname, index):is_empty () then
				return 0
			end
			if index == SADDLE_SLOT then
				return is_saddle_item (stack) and 1 or 0
			elseif index == ARMOR_SLOT then
				return horse_armor_level (stack) > 0 and 1 or 0
			elseif index == BAG_SLOT then
				return is_bag_item (stack) and 1 or 0
			end
			return 0
		end,
		allow_take = function (inv, listname, index, stack)
			-- The bag can only be removed once its storage is empty, so its
			-- contents are never silently lost.
			if listname == "main" and index == BAG_SLOT
				and not this:storage_is_empty () then
				return 0
			end
			return stack:get_count ()
		end,
		on_put = function (inv, listname, index, stack)
			if listname == "storage" then
				this:save_storage (inv)
			elseif index == SADDLE_SLOT then
				this:apply_saddle ()
			elseif index == ARMOR_SLOT then
				this:apply_armor (stack)
			elseif index == BAG_SLOT then
				this:apply_bag ()
				refresh ()
			end
		end,
		on_take = function (inv, listname, index)
			if listname == "storage" then
				this:save_storage (inv)
			elseif index == SADDLE_SLOT then
				this:clear_saddle ()
			elseif index == ARMOR_SLOT then
				this:clear_armor ()
			elseif index == BAG_SLOT then
				this:clear_bag ()
				refresh ()
			end
		end,
	}, name)
	inv:set_size ("main", 3)
	inv:set_size ("storage", STORAGE_SIZE)
	inv:set_stack ("main", SADDLE_SLOT,
		self.saddle == "yes" and ItemStack ("mcl_mobitems:saddle") or ItemStack (""))
	inv:set_stack ("main", ARMOR_SLOT, ItemStack (self._armor))
	inv:set_stack ("main", BAG_SLOT, ItemStack (self._bag))
	if self._saddlebag then
		for i = 1, STORAGE_SIZE do
			inv:set_stack ("storage", i, ItemStack (self._saddlebag[i] or ""))
		end
	end
	refresh ()
end

core.register_on_player_receive_fields (function (player, formname, fields)
	if formname ~= "edoras_horse:inv" or not fields.quit then return end
	core.remove_detached_inventory ("edoras_horse_inv_" .. player:get_player_name ())
end)

core.register_on_leaveplayer (function (player)
	core.remove_detached_inventory ("edoras_horse_inv_" .. player:get_player_name ())
end)

------------------------------------------------------------------------
-- Riding.
------------------------------------------------------------------------

-- Forward seat offset on the saddle (model-local Z; +Z = head). Stock seat was
-- -1.75 (behind centre); tune this to sit the rider on the saddle/withers.
local SEAT_FORWARD = -0.75

-- Seat position on the canonical horse mesh (matches mobs_mc:horse).
function horse:init_attachment_position ()
	local vsize = self.object:get_properties().visual_size
	-- z is forward (+Z = head end). Stock mobs_mc seat was z=-1.75 (behind centre);
	-- moved forward onto the saddle/withers. SEAT_FORWARD is the tuning lever.
	self.driver_attach_at = {x = 0, y = 4.17, z = SEAT_FORWARD}
	self.driver_scale = {x = 1 / vsize.x, y = 1 / vsize.y}
	-- Raise the first-person camera so the horse's neck/head doesn't block
	-- the view (stock mcl_mobs eye offset is y=3; edoras used y=8). Bumped to
	-- 12 for this taller breed -- the head was still blocking the view at 9.5.
	self.driver_eye_offset = {x = 0, y = 12, z = 0}
	-- Every mount starts in Walk; clear the shift-key edge state so a key still
	-- held from the previous rider doesn't auto-trigger a tap.
	self._gait_tier = 1
	self._shift_up_held = false
	self._shift_down_held = false
end

-- Rider pose. The stock player "sit_mount" clip throws the legs forward (Lego
-- style); we override the rider's leg bones so they sit astride. NB the Leg_Right/
-- Leg_Left bones carry a 180-degree-flipped rest frame, so axis senses are NOT
-- obvious -- RIDE_LEG_SCALE mirrors mcl_player's bone_workaround_scales for the legs
-- and the angles below need in-game tuning (flip a sign if a leg goes the wrong way).
local RIDE_LEG_SCALE = vector.new (1, -1, -1)
local RIDE_LEG_PITCH = 10     -- thigh tilt front-to-back (deg) -- this angle is good
local RIDE_LEG_SPLAY = 45     -- outward (centre->out) abduction (deg), mirrored L/R

-- Forward torso lean while galloping (deg), like the player's sneak lean. Applied
-- to the "Body" bone, which mcl_serverplayer leaves alone while mounted (it only
-- forces Body_Control) -- so this survives, same as the leg overrides. Body is the
-- parent of the legs, so the whole rider tilts forward over the neck (jockey crouch).
-- Negative pitches forward (jockey crouch); positive leans back. 0 = no lean.
local RIDE_LEAN = -25

-- Rodeo rider reaction while the horse bucks: lean back and rock with the buck,
-- one arm thrown up. The arm uses the Arm_*_Pitch_Control bone (mcl_serverplayer
-- only forces those on CSM-driven riders; ours is server-side, so the override
-- holds, like Body/legs). All degrees; SIGNS likely need in-game tuning.
-- Rock the rider FORWARD and back to the original upright pose (not back past it):
-- base lean is forward (-16) and the rock (+16) returns it to 0, so the torso pitch
-- swings within [-32 (forward), 0 (original)]. Flip RIDE_BUCK_ROCK's sign to change
-- which point in the buck cycle is the forward extreme.
local RIDE_BUCK_LEAN = -16      -- base forward lean while bucking (-=forward)
local RIDE_BUCK_ROCK = 16       -- rocks back toward the original upright pose
local RIDE_BUCK_FREQ = 9.4      -- rock angular speed (rad/s); ~ 2*pi / hop interval
local RIDE_BUCK_ARM_PITCH = -120  -- right arm swung up overhead (deg)
local RIDE_BUCK_ARM_OUT   = -25   -- ...and out to the side (z)
local RIDE_BUCK_ARM_WAVE  = 18    -- arm waves this much with the rhythm
local RIDE_ARM_SCALE = vector.new (1, -1, -1)  -- Arm_*_Pitch_Control workaround scale

-- Put the rider's legs into the straddle pose and lean the torso forward when the
-- horse is galloping (anim "run"). Uses Mineclonia's helper (rot in degrees, applies
-- the leg scale workaround); runs every tick while ridden, idempotent so it eases
-- between lean/upright via the helper's 0.1s interpolation. Guarded if mcl_util absent.
function horse:set_ride_pose (player)
	if not (player and mcl_util and mcl_util.set_bone_position) then return end
	mcl_util.set_bone_position (player, "Leg_Right",
		nil, vector.new (RIDE_LEG_PITCH, 0, -RIDE_LEG_SPLAY), RIDE_LEG_SCALE)
	mcl_util.set_bone_position (player, "Leg_Left",
		nil, vector.new (RIDE_LEG_PITCH, 0,  RIDE_LEG_SPLAY), RIDE_LEG_SCALE)
	if self._bucking then
		-- Rodeo: rock the torso with the buck and throw one arm up. _buck_phase is
		-- advanced in do_custom (it has dtime); osc rocks lean and arm together.
		local osc = math.sin ((self._buck_phase or 0) * RIDE_BUCK_FREQ)
		mcl_util.set_bone_position (player, "Body",
			nil, vector.new (RIDE_BUCK_LEAN + RIDE_BUCK_ROCK * osc, 0, 0), nil)
		mcl_util.set_bone_position (player, "Arm_Right_Pitch_Control", nil,
			vector.new (RIDE_BUCK_ARM_PITCH, 0, RIDE_BUCK_ARM_OUT + RIDE_BUCK_ARM_WAVE * osc),
			RIDE_ARM_SCALE)
		self._buck_arm = true
	else
		local lean = (self._current_animation == "run") and RIDE_LEAN or 0
		mcl_util.set_bone_position (player, "Body", nil, vector.new (lean, 0, 0), nil)
		-- Drop the raised arm once when the buck ends (leave it alone otherwise so
		-- the stock mounted arm pose shows through).
		if self._buck_arm then
			self._buck_arm = false
			player:set_bone_override ("Arm_Right_Pitch_Control", {})
		end
	end
end

function horse:clear_ride_pose (player)
	if not (player and player.set_bone_override) then return end
	player:set_bone_override ("Leg_Right", {})
	player:set_bone_override ("Leg_Left", {})
	player:set_bone_override ("Body", {})
	player:set_bone_override ("Arm_Right_Pitch_Control", {})
	self._buck_arm = false
end

-- Wrap mob_class attach/detach so the straddle pose is applied on mount and
-- cleared on every dismount path (sneak, buck, death, water).
function horse:attach (player, force_server_side)
	mob_class.attach (self, player, force_server_side)
	self:set_ride_pose (player)
end

function horse:detach (player, offset)
	self:clear_ride_pose (player)
	mob_class.detach (self, player, offset)
end

-- Only a saddled horse can be driven.
function horse:should_drive ()
	return self.saddle == "yes" and mob_class.should_drive(self)
end

-- Carry the rider through water instead of dumping them: stock mcl_mobs expels
-- any driver whose mount's head is submerged. The horse floats (floats=1) so it
-- swims at the surface, and drive() caps it to a walk in water.
function horse:expel_underwater_drivers ()
	return
end

-- SWEM-style four-tier manual gait box (Walk -> Trot -> Canter -> Gallop).
-- mcl_mobs otherwise hardcodes the ridden anim to "walk"; here the rider SHIFTS
-- gaits with discrete key taps and the horse holds the selected gait only while
-- moving forward:
--   shift up    : tap E (aux1)   -- one tier up per tap
--   shift down  : tap S (down)   -- one tier down per tap
--   maintain    : hold W (up)
--   reset->Walk : release W, or run into an obstacle/refusal
-- NB: Luanti servers can't read arbitrary keys (no H/G as in SWEM); E/S are the
-- engine-readable stand-ins (sneak stays reserved for dismount). A client-side
-- mod could remap these to literal H/G.
--
-- Speeds are authored as a per-gait [min,max] range in BLOCKS PER SECOND
-- (1 block = 1 m). Every horse has a fixed quality level self._speed_level in
-- [0,1] (rolled at spawn) that places it within EVERY gait's range:
--   bps = min + (max - min) * level
-- so a low-level horse is slow in all gaits and a top horse is fast in all.
-- Then drive_bonus = bps / movement_speed (driven speed = movement_speed *
-- drive_bonus). Each tier also sets the play anim and jump_height.
local GAITS = {
	-- jump = launch velocity; apex nodes ~= jump^2/64 (see jump_height note).
	{ name = "walk",    anim = "walk",   min = 1.4, max = 1.8, jump = 10 },  -- ~1.3 nodes
	{ name = "trot",    anim = "trot",   min = 2.4, max = 4.0, jump = 11 },  -- ~1.6 nodes
	{ name = "canter",  anim = "canter", min = 4.0, max = 6.0, jump = 12 },  -- ~1.9 nodes
	{ name = "gallop",  anim = "run",    min = 7.0, max = 10.0, jump = 13 }, -- ~2.4 nodes
}
local MAX_TIER = #GAITS

-- Roll this horse's fixed quality level in [0,1] once (placement within every
-- gait's speed range, see GAITS). Persists via mcl_mobs staticdata. Called from
-- after_activate so each spawn -- and any pre-genetics horse -- gets one.
function horse:init_genetics ()
	if not self._speed_level then
		self._speed_level = math.random ()
	end
end

-- Sprint (gallop) economy: thirst is the sprint resource (drained ONLY while
-- galloping, below). A full meter buys ~80s of gallop ("8 gallops" of 10s). A
-- single burst runs at most GALLOP_MAX_TIME before a forced step-down to canter,
-- and can't be re-initiated until the horse has cantered steadily for
-- GALLOP_COOLDOWN; emptying thirst hard-locks it to a walk (see update_needs).
-- NB these MUST be declared before horse:drive -- a local defined later in the
-- file is not in scope as an upvalue here and would read as a nil global.
local GALLOP_THIRST_DRAIN = 100 / 80   -- 1.25/s: full (100) -> 0 over 80s of gallop
local GALLOP_MAX_TIME     = 10.0       -- max continuous gallop (s) -> canter
local GALLOP_COOLDOWN     = 4.0        -- steady cantering (s) needed to re-gallop
local DEHYDRATE_RECOVER   = 20         -- thirst must exceed this to clear walk-lock
local THIRST_BUCKET_GAIN  = 50         -- thirst restored by a water bucket

function horse:drive (moving_anim, stand_anim, can_fly, dtime, moveresult)
	local ctrl = self.driver and self.driver:get_player_control ()
	local tier = self._gait_tier or 1

	-- Edge-detected taps: act only on the press, not while the key is held.
	local up_now   = (ctrl and ctrl.aux1) or false   -- E: shift up
	local down_now = (ctrl and ctrl.down) or false   -- S: shift down
	if up_now and not self._shift_up_held and tier < MAX_TIER then
		tier = tier + 1
	end
	if down_now and not self._shift_down_held and tier > 1 then
		tier = tier - 1
	end
	self._shift_up_held = up_now
	self._shift_down_held = down_now

	-- Rider defiance (Phase 2): _gait_ceiling caps the gait a HUNGRY horse will
	-- give -- 2 = no canter/gallop (trot max), 1 = walk only. A tap past the cap
	-- just clamps; it doesn't dump the rider back to a walk.
	tier = math.min (tier, self._gait_ceiling or MAX_TIER)
	-- Swimming: a horse only walks in water (it can't gallop while afloat).
	if core.get_item_group (self.standing_in or "", "water") > 0 then
		tier = math.min (tier, 1)
	end
	-- Forward context: the horse holds its selected gait only while W is down;
	-- releasing W, or running into an obstacle, snaps it back to a walk.
	local forward = ctrl and ctrl.up
	local v = self.object:get_velocity ()
	local speed = math.sqrt (v.x * v.x + v.z * v.z)
	local blocked = forward and moveresult and moveresult.collides and speed < 0.5
	if not forward or blocked then
		tier = 1
	end

	-- Dehydration: an empty sprint meter rejects any shift up above a walk and
	-- hard-locks the horse to a walk until it drinks (latch in update_needs).
	if self._dehydrated then
		tier = math.min (tier, 1)
	end

	-- Sprint limiter: a gallop drains thirst fast, runs at most GALLOP_MAX_TIME
	-- before a forced step-down to canter, and can't be re-initiated until the
	-- horse has cantered steadily for GALLOP_COOLDOWN.
	local GALLOP, CANTER = MAX_TIER, MAX_TIER - 1
	self._gallop_timer = self._gallop_timer or 0
	self._canter_timer = self._canter_timer or 0
	if tier >= GALLOP then
		if self._gallop_locked then
			tier = CANTER                 -- cooldown interlock: not recovered yet
		else
			self._gallop_timer = self._gallop_timer + dtime
			self._thirst = math.max (0, (self._thirst or 0)
				- GALLOP_THIRST_DRAIN * dtime)
			if self._gallop_timer >= GALLOP_MAX_TIME then
				tier = CANTER             -- 4s cap reached: forced step-down
				self._gallop_locked = true
				self._gallop_timer = 0
				self._canter_timer = 0
			end
		end
	else
		self._gallop_timer = 0
	end
	-- The lock clears only after a steady stretch of cantering (drop out of
	-- canter and the cooldown restarts).
	if self._gallop_locked then
		if tier == CANTER then
			self._canter_timer = self._canter_timer + dtime
			if self._canter_timer >= GALLOP_COOLDOWN then
				self._gallop_locked = false
				self._canter_timer = 0
			end
		else
			self._canter_timer = 0
		end
	end

	tier = math.max (1, tier)
	self._gait_tier = tier

	local g = GAITS[tier]
	local level = self._speed_level or 0.5
	local bps = g.min + (g.max - g.min) * level
	self.drive_bonus = bps / self.movement_speed
	self.jump_height = g.jump
	if speed > 0.5 then
		moving_anim = g.anim
	end
	return mob_class.drive (self, moving_anim, stand_anim, can_fly, dtime, moveresult)
end

------------------------------------------------------------------------
-- Phase 2: biological needs (hunger + thirst), foraging, rider defiance.
--
-- _hunger / _thirst are 0..100 "fullness" meters (100 = sated, 0 = empty) that
-- persist via mcl_mobs staticdata. HUNGER is the slow biological need: it drains
-- over time and, as it runs low, caps the gait the horse will give its rider
-- (_gait_ceiling, read by horse:drive) -- bucking the rider off when critical.
-- THIRST is the sprint resource: it drains ONLY while galloping (the gallop
-- limiter in horse:drive) and empties hard-locks the horse to a trot until it
-- drinks. Left unridden, a hungry/thirsty horse forages: it pathfinds to the
-- nearest grass/hay (food) or water (drink) and tops the meter back up; standing
-- in water or right-clicking with a water bucket also restores thirst.
------------------------------------------------------------------------
local NEED_MAX      = 100
local START_NEED    = 70                    -- freshly spawned: mostly fed
local HUNGER_DRAIN  = NEED_MAX / (25 * 60)  -- empties in ~25 min at rest
local EXERTION      = 2.5                    -- hunger drain multiplier while worked hard
-- Forage thresholds (separate, because thirst is now the sprint meter: it rests
-- high and only drops when galloping, so it must NOT share hunger's trigger or an
-- idle horse would obsessively hunt water). HUNGER is the everyday grazing driver;
-- raise HUNGER_SEEK_BELOW to make horses graze sooner/more often.
local HUNGER_SEEK_BELOW = 70                 -- graze when hunger dips below this
local THIRST_SEEK_BELOW = 55                 -- seek water only after a gallop drains it
local CEIL_LOW      = 35                     -- below this: cap at TROT (tier 2)
local CEIL_CRITICAL = 12                     -- below this: walk only + buck rider
local BUCK_INTERVAL = 4.0                    -- seconds between bucks when critical
local FORAGE_RADIUS = 10
local FORAGE_BONUS  = 0.6                    -- forage speed = movement_speed * this
-- Grazing is a slow, drawn-out activity: each bite restores only a few points, so a
-- hungry horse drifts across the field cropping many spots before it's full. Once it
-- STARTS feeding (a meter < its SEEK threshold) it keeps grazing until that meter
-- reaches FORAGE_FULL -- without this hysteresis it would stop the instant it crept
-- back over the trigger and only ever take one bite. Lower FORAGE_GAIN (or raise
-- FORAGE_FULL) to make a feeding session longer.
local FORAGE_GAIN   = 6                      -- hunger restored per graze (a few points)
local FORAGE_FULL   = 98                     -- stop a feeding session once topped up here
local DRINK_RATE    = 8                      -- thirst refilled per second while drinking
                                             -- (faster than grazing, but not instant)
local FEED_GAIN     = 40                     -- hunger restored when hand-fed (deliberate)

-- Taming (vanilla-style temper minigame). A wild horse must be broken in before it
-- accepts a saddle: right-click EMPTY-HANDED to mount it bareback; after a short
-- ride it either accepts the rider (tamed, heart particles) or bucks them off,
-- raising its _temper so the next attempt is likelier to succeed. Feeding an untamed
-- horse also raises temper (and heals). Mirrors mobs_mc/horse.lua's _temper /
-- _max_temper roll. These MUST be declared before on_rightclick / do_custom use them.
local TAME_MAX_TEMPER  = 120     -- success when random(1, this) <= _temper + 1
local TAME_TEMPER_BUCK = 5       -- temper gained per failed (bucked) attempt
local TAME_FOOD_TEMPER = 3       -- temper gained per food item fed to a wild horse
local TAME_RIDE_MIN    = 1.5     -- bareback seconds before the verdict (min)
local TAME_RIDE_MAX    = 3.5     -- bareback seconds before the verdict (max)
-- Rodeo struggle: while a wild horse is ridden bareback it plays the buck clip
-- and hops in place trying to throw the rider.
local BUCK_HOP_INTERVAL = 0.67   -- seconds between in-place hops (~one per buck clip cycle)
local BUCK_HOP_SPEED    = 4.5    -- upward velocity of each hop (apex ~0.3 nodes)
-- On arrival the horse stays head-down grazing for a random spell in this range
-- before it eats and wanders off (keeps it rooted to one spot, not a quick peck).
local GRAZE_HOLD_MIN = 7.0
local GRAZE_HOLD_MAX = 10.0
-- After a bite, drift this long (random) toward the next patch before grazing again.
local GRAZE_WANDER_MIN = 4.0
local GRAZE_WANDER_MAX = 7.0
-- Flee (when hit by a player): canter away from the attacker (biased into a cone
-- pointing away, re-rolled each leg, so the path bends rather than running dead
-- straight), instead of the stock fully-random nearby pacing_target.
local FLEE_RANGE     = 14            -- how far each flee leg reaches (nodes)
local FLEE_RISE      = 7             -- vertical search span for the flee target
local FLEE_DEVIATION = math.pi / 6   -- cone half-angle around the away direction (~30deg)
local FLEE_RETARGET  = 1.0           -- re-aim this often (s) to keep fleeing a chaser
-- Pathfinding targets when hungry. The tall plants (tallgrass / double grass /
-- ferns) are eaten destructively in graze(); grass blocks + hay are a fallback
-- the horse only grazes lightly.
local FOOD_NODES  = {"mcl_flowers:tallgrass", "mcl_flowers:double_grass",
                     "mcl_flowers:fern", "mcl_flowers:double_fern",
                     "mcl_farming:hay_block", "mcl_core:dirt_with_grass"}
-- Plants the horse actually eats (removes the node, leaving the grass block).
local EAT_NODES   = {"mcl_flowers:tallgrass", "mcl_flowers:double_grass",
                     "mcl_flowers:fern", "mcl_flowers:double_fern"}
local WATER_NODES = {"group:water"}
-- Swimming to shore. A riderless horse that finds itself in deep water (feet AND
-- the node below both water -- i.e. no footing) heads for the nearest dry land
-- instead of milling about on the surface. find_nodes_in_area_under_air only
-- returns ground with AIR above it, so every candidate sits at/above the
-- waterline (never the submerged lake bed). We steer there with go_to_stupidly
-- (continuous straight-line steering, re-aimed each rescan) rather than gopath:
-- A* paths across open water are flaky/short-ranged, whereas stupid steering
-- crosses any distance and the stepheight walks the horse up onto the beach.
local WATER_ESCAPE_RADIUS = 16      -- horizontal reach of the shore scan (nodes)
local WATER_ESCAPE_DOWN   = 2       -- how far below the horse to look (shore can sit low)
local WATER_ESCAPE_RISE   = 4       -- how far above the horse to look
local WATER_ESCAPE_BONUS  = 0.7     -- swim-to-shore speed = movement_speed * this
local WATER_ESCAPE_CD     = 1.5     -- re-aim interval while swimming for shore (s)
local LAND_NODES = {"group:solid"}
-- Half-submerged idle pose. Stock floats=1 buoyancy jumps the horse up until only
-- ~0.4 node is underwater, so a riderless horse appears to walk ON the water. We
-- instead hold a deep-water horse with the waterline across the middle of its
-- body. do_custom runs AFTER the physics motion step, so overriding velocity.y
-- there wins for the tick; a proportional pull settles it at the target depth.
local SWIM_HEIGHT     = 1.92        -- collisionbox height (see collisionbox above)
local SWIM_SUBMERGE   = 0.55        -- fraction of the body below the waterline
local SWIM_SINK_GAIN  = 4.0         -- proportional pull toward the target depth
local SWIM_SINK_MAX   = 3.0         -- clamp on the corrective vertical speed (m/s)
local SWIM_BREACH_VY  = 2.0         -- above this upward speed, physics is launching the
                                    -- horse out of the water -- don't cancel the leap

-- True if the move this tick ran into something on a horizontal axis. While
-- floating, mcl_mobs zeroes stepheight, so the only way onto a shore is the
-- engine's "breach" leap (v.y = 6.0), which it fires exactly on such a collision.
-- We use this to STOP forcing the horse down at the water's edge, letting it rise
-- to the surface and leap out instead of being pinned half-submerged at the wall.
local function horiz_collision (moveresult)
	if not (moveresult and moveresult.collisions) then return false end
	for _, c in ipairs (moveresult.collisions) do
		if c.axis == "x" or c.axis == "z" then return true end
	end
	return false
end

-- World Y of the air/water boundary in the column above pos, or nil if the horse
-- is not actually standing in a water column. Scans up from the feet node.
local function water_surface_y (pos)
	local x, z = math.floor (pos.x + 0.5), math.floor (pos.z + 0.5)
	local base = math.floor (pos.y + 0.5)
	for i = 0, 4 do
		local y = base + i
		local name = core.get_node ({x = x, y = y, z = z}).name
		if core.get_item_group (name, "water") == 0 then
			-- First non-water node up the column; the water top is its bottom face.
			-- If the feet node itself is dry, the horse isn't in water at all.
			return (i == 0) and nil or (y - 0.5)
		end
	end
	return base + 4.5
end

-- Lead following (integrates with the "leads" mod by SilverSandstone, if present).
-- A leashed horse TRAILS its leader (the player holding the rope) under its own
-- power, instead of standing still until the rope goes taut and is physically
-- dragged. The leads mod only applies a pull force once the gap exceeds its
-- lead_length (default 8 nodes); keeping the horse within LEAD_STOP means the rope
-- stays slack and the horse simply walks alongside.
local LEAD_STOP  = 4.0    -- stop trailing once this close to the leader (nodes)
local LEAD_BONUS = 0.6    -- follow speed = movement_speed * this (a relaxed pace)
local LEAD_SCAN  = 0.5    -- re-scan the leads API this often (s) when none cached

-- Lazily initialise the meters (new spawns and pre-Phase-2 horses).
function horse:init_needs ()
	if not self._hunger then self._hunger = START_NEED end
	if not self._thirst then self._thirst = START_NEED end
end

-- Which meter, if any, the horse should leave to forage for. A feeding session
-- latches (self._feeding) so the horse keeps grazing many spots until the meter is
-- FORAGE_FULL, not just until it nudges back over the SEEK trigger.
function horse:forage_need ()
	local h, t = self._hunger or NEED_MAX, self._thirst or NEED_MAX
	-- End the session once the meter it set out to fill is topped up.
	if self._feeding == "hunger" and h >= FORAGE_FULL then self._feeding = nil end
	if self._feeding == "thirst" and t >= FORAGE_FULL then self._feeding = nil end
	if self._feeding then return self._feeding end
	-- Otherwise start a new session (post-gallop thirst takes priority if lower).
	if t < THIRST_SEEK_BELOW and t <= h then self._feeding = "thirst"; return "thirst" end
	if h < HUNGER_SEEK_BELOW then self._feeding = "hunger"; return "hunger" end
	return nil
end

-- Throw the current rider off (rear + toss).
function horse:buck_rider ()
	local rider = self.driver
	if not rider then return end
	self:detach (rider, {x = 1.6, y = 0.35, z = 1.6})
	core.sound_play ("mobs_mc_horse_hurt", {
		gain = 0.7, max_hear_distance = 16, pos = self.object:get_pos (),
	}, true)
end

------------------------------------------------------------------------
-- Taming. A wild horse is broken in by riding it bareback (empty hand): each ride
-- ends in either acceptance (tamed) or a buck-off that raises its temper, so
-- attempts get likelier to stick. Only a tamed horse accepts a saddle/armor/bag.
------------------------------------------------------------------------

-- Lazily initialise the temper meter (new spawns and pre-taming-feature horses).
function horse:init_taming ()
	if not self._temper then self._temper = 0 end
end

-- Heart-particle burst (taming feedback), matching mcl_mobs.just_tame.
local function tame_hearts (pos)
	mcl_mobs.effect ({x = pos.x, y = pos.y + 0.7, z = pos.z},
		5, "heart.png", 2, 4, 2.0, 0.1)
end

-- Failed-attempt smoke puff (matching feed_tame's reject effect).
local function tame_reject (pos)
	mcl_mobs.effect ({x = pos.x, y = pos.y + 0.7, z = pos.z}, math.random (7),
		"mcl_particles_mob_death.png^[colorize:#000000:255", 2, 4, 2.0, 0.1)
end

-- Successfully tame the horse to a player (heart particles + a whinny).
function horse:tame_horse (player)
	self.tamed = true
	self.owner = player and player:is_player () and player:get_player_name () or ""
	self.persistent = true
	local pos = self.object:get_pos ()
	if pos then tame_hearts (pos) end
	self:neigh ()
end

-- Empty-handed mount of an untamed horse: ride it bareback to break it in. Sets a
-- short countdown after which update_taming delivers the verdict.
function horse:try_bareback_mount (clicker)
	if self.tamed or self.child or self.driver then return end
	self:init_taming ()
	self:init_attachment_position ()
	self:attach (clicker)
	self._tame_eval = TAME_RIDE_MIN + math.random () * (TAME_RIDE_MAX - TAME_RIDE_MIN)
	core.sound_play ("mobs_mc_horse_hurt", {
		gain = 0.4, max_hear_distance = 16, pos = self.object:get_pos (),
	}, true)
end

-- Per-tick taming verdict while a rider clings to an untamed horse. After the ride
-- countdown, roll against temper: succeed -> tamed; fail -> buck the rider and bump
-- temper so the next ride is likelier. Called from do_custom.
function horse:update_taming (dtime)
	if self.tamed or not self.driver then
		self._tame_eval = nil
		return
	end
	self:init_taming ()
	if not self._tame_eval then
		self._tame_eval = TAME_RIDE_MIN + math.random () * (TAME_RIDE_MAX - TAME_RIDE_MIN)
	end
	self._tame_eval = self._tame_eval - dtime
	if self._tame_eval > 0 then return end
	self._tame_eval = nil
	if math.random (1, TAME_MAX_TEMPER) <= self._temper + 1 then
		self:tame_horse (self.driver)
	else
		self._temper = math.min (TAME_MAX_TEMPER, self._temper + TAME_TEMPER_BUCK)
		local pos = self.object:get_pos ()
		self:buck_rider ()
		if pos then tame_reject (pos) end
	end
end

-- AI function (FIRST in the list): while a wild horse is ridden bareback it is
-- being broken in -- it shouldn't pace/forage/flee. Halting and returning an active
-- activity is REQUIRED for the buck clip to play: run_ai forces set_animation("stand")
-- every tick when NO activity is active, which would restart (and freeze) the buck
-- clip that do_custom sets. Returning "bucking" suppresses that stand-force; the
-- buck pose is set in do_custom, the in-place hops too. keep_animation stops
-- halt_in_tracks from setting "stand" itself.
function horse:check_buck (pos, dtime)
	if self.driver and not self.tamed then
		self:halt_in_tracks (false, true)
		return "bucking"
	end
	return false
end

-- Per-tick meter drain + defiance state. Called from do_custom.
function horse:update_needs (dtime)
	self:init_needs ()
	-- Hunger is the slow biological need; thirst is the sprint resource and is
	-- drained only while galloping (horse:drive). Drinking refills it GRADUALLY at
	-- DRINK_RATE (faster than grazing but not instant) whenever the horse is standing
	-- in water (ridden or guided in) or head-down drinking at a water source it
	-- foraged to (_grazing with _forage_for == "thirst").
	local worked = self.driver and (self._gait_tier or 1) >= 3
	local exert = worked and EXERTION or 1.0
	self._hunger = math.max (0, self._hunger - HUNGER_DRAIN * dtime * exert)
	local drinking = core.get_item_group (self.standing_in or "", "water") > 0
		or (self._grazing and self._forage_for == "thirst")
	if drinking then
		self._thirst = math.min (NEED_MAX, (self._thirst or 0) + DRINK_RATE * dtime)
	end

	-- Dehydration latch (hysteresis): an empty sprint meter hard-locks the horse
	-- to a walk (enforced in horse:drive) until it drinks back above the recovery
	-- threshold. Updated here so it stays correct even while drinking unridden.
	if (self._thirst or 0) <= 0 then
		self._dehydrated = true
	elseif (self._thirst or 0) > DEHYDRATE_RECOVER then
		self._dehydrated = false
	end

	-- Defiance now keys off HUNGER alone (thirst gates gaits via the sprint
	-- limiter / dehydration lock instead).
	local low = self._hunger
	if low <= CEIL_CRITICAL then
		self._gait_ceiling = 1            -- walk only
	elseif low <= CEIL_LOW then
		self._gait_ceiling = 2            -- slow to a trot: no canter/gallop
	else
		self._gait_ceiling = nil          -- no cap
	end

	-- A starving/parched horse won't tolerate a rider: periodic buck-off.
	if self.driver and low <= CEIL_CRITICAL then
		self._buck_timer = (self._buck_timer or 0) + dtime
		if self._buck_timer >= BUCK_INTERVAL then
			self._buck_timer = 0
			self:buck_rider ()
		end
	else
		self._buck_timer = 0
	end
end

-- Top up the meter the horse set out to satisfy (called on arrival).
function horse:graze ()
	if self._forage_for == "thirst" then
		-- Thirst is topped up gradually while head-down at the water (update_needs's
		-- DRINK_RATE over the hold), so there is nothing to add at the end here.
	else
		local gain = FORAGE_GAIN
		-- Eat a tall plant if one is underfoot: remove it (and the top half of a
		-- double plant), but never the grass block beneath. No nearby plant ->
		-- the horse only grazed the surface, so a lighter top-up.
		local pos = self.object:get_pos ()
		local p = pos and core.find_node_near (pos, 2, EAT_NODES)
		if p then
			local nn = core.get_node (p).name
			core.remove_node (p)
			if nn == "mcl_flowers:double_grass" or nn == "mcl_flowers:double_fern" then
				local top = {x = p.x, y = p.y + 1, z = p.z}
				if core.get_item_group (core.get_node (top).name, "double_plant") == 2 then
					core.remove_node (top)
				end
			end
		else
			gain = FORAGE_GAIN * 0.5
		end
		self._hunger = math.min (NEED_MAX, (self._hunger or 0) + gain)
	end
	self._forage_for = nil
end

-- Per-horse top speed (blocks/sec) for each gait at this horse's quality level,
-- shown in the gear inventory. Mirrors the bps math in horse:drive.
function horse:gait_speeds ()
	local level = self._speed_level or 0.5
	local t = {}
	for i = 1, #GAITS do
		local g = GAITS[i]
		t[i] = g.min + (g.max - g.min) * level
	end
	return t
end

-- AI function: when unridden and a meter is low, pathfind to the nearest
-- food/water node and graze on arrival. Mirrors check_pace's gopath pattern;
-- "foraging" is an interruptible named activity (self.foraging is its flag).
function horse:check_forage (pos, dtime)
	-- Don't graze/drink while swimming in deep water: check_water_escape owns that
	-- state, and a head-down forage here just plays the eating clip over the sea
	-- floor (it reads as the horse "eating seaweed"). It's auto-drinking anyway --
	-- update_needs tops up thirst while standing in water.
	if core.get_item_group (self.standing_in or "", "water") > 0
		and core.get_item_group (self.standing_on or "", "water") > 0 then
		self.foraging = false
		self._grazing = false
		return false
	end
	if self.driver or self.child then
		self.foraging = false
		self._grazing = false
		return false
	end
	-- Grazing hold: once arrived, stay head-down and chew for GRAZE_HOLD_* seconds
	-- before actually eating + moving on. Returning "foraging" the whole time keeps
	-- check_pace (wandering) from running, so the horse stays put. The do_custom
	-- overlay drives the head-down animation and pins it in place.
	if self._grazing then
		self._graze_timer = (self._graze_timer or 0) - dtime
		if self._graze_timer <= 0 then
			self:graze ()
			self._grazing = false
			self.foraging = false
			-- Still feeding? Hunger drifts to the next patch (force a short pace) so it
			-- grazes across the field; thirst stays put at the water and keeps drinking.
			local still = self:forage_need ()
			if still == "hunger" then
				self._pace_asap = true
				self._forage_cd = GRAZE_WANDER_MIN
					+ math.random () * (GRAZE_WANDER_MAX - GRAZE_WANDER_MIN)
			elseif still == "thirst" then
				self._forage_cd = 1.0       -- brief pause, then drink again in place
			end
			return false
		end
		return "foraging"
	end
	if self.foraging then
		if self:navigation_finished () then
			self._grazing = true
			self._graze_timer = GRAZE_HOLD_MIN
				+ math.random () * (GRAZE_HOLD_MAX - GRAZE_HOLD_MIN)
			return "foraging"
		end
		return "foraging"
	end
	-- Don't re-scan the world every tick.
	self._forage_cd = (self._forage_cd or 0) - dtime
	if self._forage_cd > 0 then return false end
	self._forage_cd = 1.5

	local need = self:forage_need ()
	if not need then return false end
	local target = core.find_node_near (pos, FORAGE_RADIUS,
		need == "thirst" and WATER_NODES or FOOD_NODES)
	if target and self:gopath (target, FORAGE_BONUS) then
		self._forage_for = need
		self.foraging = true
		return "foraging"
	end
	return false
end

-- AI function (replaces stock check_frightened): when hit, an unridden horse canters
-- away from its attacker, instead of the stock fully-random nearby pacing_target.
-- Driven by runaway_timer (set to 5 by the stock on_punch -> do_runaway path) and
-- _recent_attacker (the source object, set on damage, valid ~5s). We pick a REACHABLE
-- (WALKABLE) node in a cone pointing away from the attacker via the engine's
-- target_in_direction helper -- the same primitive the stock mob "avoid" flee uses, so
-- gopath reliably finds a path (gopath to an arbitrary far point silently fails, which
-- left the horse standing). The cone is re-rolled each leg so the flight reads as
-- "away" but bends rather than running dead straight (good enough; not refined further).
-- gopath sets gowp_animation = "canter" so the path follower replays the canter clip.
function horse:check_flee (pos, dtime)
	if self.driver then
		self._fleeing = false
		return false
	end
	if self:is_frightened () then
		self._flee_retarget = (self._flee_retarget or 0) - dtime
		if not self._fleeing or self._flee_retarget <= 0
			or self:navigation_finished () then
			local target
			local atk = self._recent_attacker
			if atk and atk:is_valid () then
				local a = atk:get_pos ()
				local away = vector.new (pos.x - a.x, pos.y - a.y, pos.z - a.z)
				target = self:target_in_direction (pos, FLEE_RANGE, FLEE_RISE,
					away, FLEE_DEVIATION)
			end
			-- No known attacker, or that direction is blocked: flee any open way.
			if not target then
				target = self:pacing_target (pos, FLEE_RANGE, FLEE_RISE,
					mcl_mobs.SOLID_PACING_GROUPS)
			end
			if target and self:gopath (target, self.run_bonus) then
				self.gowp_animation = "canter"
				self:set_animation ("canter")
			end
			self._fleeing = true
			self._flee_retarget = FLEE_RETARGET
		end
		self._grazing = false        -- abandon any graze in progress
		return "fleeing"
	end
	-- Calmed down: stop and hand control back to grazing/pacing.
	if self._fleeing then
		self._fleeing = false
		self:cancel_navigation ()
		self:set_animation ("stand")
	end
	return false
end

-- AI function: when this horse is the FOLLOWER of a lead (the "leads" mod), trail
-- the leader (the player holding the rope) on its own, so being led looks like the
-- horse walking along rather than the rope physically dragging a stationary mob.
-- Sits below flee/breeding (a spooked horse still bolts -- the rope may snap, which
-- is fine) but above food-following/foraging/pacing, so a led horse heeds the
-- player over grazing. The lead is cached via the _leads_lead_add/remove hooks for
-- instant response and re-discovered periodically through the leads API (the mod
-- relinks connectors on reload WITHOUT re-calling the hook, so the scan is what
-- keeps a tied horse following after a server restart).
function horse:check_lead (pos, dtime)
	if not leads or self.driver or self.child then
		self._leading = false
		return false
	end
	self._lead_scan = (self._lead_scan or 0) - dtime
	local lead = self._lead_obj
	if not (lead and lead:get_pos ()) and self._lead_scan <= 0 then
		self._lead_scan = LEAD_SCAN
		lead = leads.find_connected_leads (self.object, false, true) ()
		self._lead_obj = lead
	end
	if not (lead and lead:get_pos ()) then
		self._leading = false
		return false
	end
	local le = lead:get_luaentity ()
	local leader = le and le.leader
	local lpos = leader and leader:get_pos ()
	-- No leader, or tied to a post (the leader is an immobile knot): don't actively
	-- trail -- the rope still tethers the horse physically; let it idle/graze nearby.
	if not lpos or leads.is_immobile (leader) then
		self._leading = false
		return false
	end
	if vector.distance (pos, lpos) <= LEAD_STOP then
		if self._leading then
			self._leading = false
			self:halt_in_tracks ()
			self:cancel_navigation ()
			self:set_animation ("stand")
		end
		return false
	end
	-- go_to_stupidly continuously re-steers toward the (moving) leader -- the same
	-- primitive normal food-following uses -- so it tracks smoothly without re-pathing.
	self:go_to_stupidly (lpos, LEAD_BONUS)
	self._leading = true
	self._grazing = false        -- abandon any graze in progress to heed the lead
	return "leading"
end

-- Nearest dry-land surface within the scan box, or nil. find_nodes_in_area_under_air
-- only returns ground with AIR above it, so candidates are at/above the waterline
-- (never the submerged sea floor); the water-group guard catches waterlogged edges.
function horse:nearest_shore (pos)
	local r = WATER_ESCAPE_RADIUS
	local minp = vector.new (pos.x - r, pos.y - WATER_ESCAPE_DOWN, pos.z - r)
	local maxp = vector.new (pos.x + r, pos.y + WATER_ESCAPE_RISE, pos.z + r)
	local cands = core.find_nodes_in_area_under_air (minp, maxp, LAND_NODES)
	local best, bestd
	for _, c in ipairs (cands) do
		if core.get_item_group (core.get_node (c).name, "water") == 0 then
			local d = vector.distance (pos, c)
			if d > 0.5 and (not bestd or d < bestd) then
				best, bestd = c, d
			end
		end
	end
	return best
end

-- AI function: a riderless horse swimming in deep water (feet node AND the node
-- below both water -- so there's no footing) steers for the nearest dry shore
-- rather than drifting on the surface. Re-aims at the closest shore on a timer so
-- it keeps tracking land as new terrain loads on a long swim. Sits below the
-- lead/follow checks so a player can still pull the horse where they want, but
-- above foraging/pacing so it prioritises getting out over idling. The
-- half-submerged pose itself is applied in do_custom (SWIM_* above).
function horse:check_water_escape (pos, dtime)
	if self.driver or self.child then
		self._escaping = false
		return false
	end
	local in_deep = core.get_item_group (self.standing_in or "", "water") > 0
		and core.get_item_group (self.standing_on or "", "water") > 0
	if not in_deep then
		-- Reached the shallows / climbed out: hand control back to grazing/pacing.
		if self._escaping then
			self._escaping = false
			self:cancel_navigation ()
			self:set_animation ("stand")
		end
		return false
	end
	-- Re-aim at the nearest shore on first entry and then on a timer (the target
	-- moves as the horse swims and new chunks load).
	self._escape_cd = (self._escape_cd or 0) - dtime
	if not self._escaping or self._escape_cd <= 0 then
		self._escape_cd = WATER_ESCAPE_CD
		local target = self:nearest_shore (pos)
		if target then
			-- go_to_stupidly steers straight at the point each tick (the primitive
			-- following/leading use): reliable across open water, where A* fails.
			self:go_to_stupidly (target, WATER_ESCAPE_BONUS)
			self.gowp_animation = "walk"
			self:set_animation ("walk")
			self._escaping = true
		elseif not self._escaping then
			-- No shore in range and not already swimming: don't pin the horse here,
			-- let check_pace wander (it may drift into scan range of land).
			return false
		end
	end
	return self._escaping and "escaping" or false
end

-- The leads mod calls these on the connector entity when a lead is attached or
-- removed; the args are the lead's luaentity and whether THIS horse is the leader.
-- We only care when the horse is the FOLLOWER (is_leader == false): cache/clear the
-- lead object so check_lead reacts immediately (the periodic scan is the fallback).
function horse:_leads_lead_add (lead, is_leader)
	if not is_leader then
		self._lead_obj = lead and lead.object
	end
end

function horse:_leads_lead_remove (lead, is_leader)
	if not is_leader then
		self._lead_obj = nil
		self._leading = false
	end
end

function horse:on_rightclick (clicker)
	if not clicker or not clicker:is_player() then return end
	local stack = clicker:get_wielded_item ()
	local item_name = stack:get_name ()
	local creative = core.is_creative_enabled (clicker:get_player_name ())

	-- Put a saddle on a TAMED horse (a wild one must be broken in first).
	if item_name == "mcl_mobitems:saddle" and self.saddle ~= "yes"
		and self.tamed and not self.child then
		self:apply_saddle ()
		if not creative then
			stack:take_item ()
			clicker:set_wielded_item (stack)
		end
		return
	end

	-- Put horse armor on a tamed horse.
	if horse_armor_level (stack) > 0 and (not self._armor or self._armor == "")
		and self.tamed and not self.child then
		if self:apply_armor (stack) and not creative then
			stack:take_item ()
			clicker:set_wielded_item (stack)
		end
		return
	end

	-- Equip a saddlebag on a tamed horse.
	if is_bag_item (stack) and not self:has_bag () and self.tamed
		and not self.child then
		self:apply_bag ()
		if not creative then
			stack:take_item ()
			clicker:set_wielded_item (stack)
		end
		return
	end

	-- Water the horse from a bucket: refills the sprint (thirst) meter and hands
	-- back an empty bucket. Takes one bucket from the stack so a stacked bucket
	-- isn't wiped.
	if item_name == "mcl_buckets:bucket_water" then
		self:init_needs ()
		if self._thirst < NEED_MAX then
			self._thirst = math.min (NEED_MAX, self._thirst + THIRST_BUCKET_GAIN)
			if not creative then
				stack:take_item ()
				clicker:set_wielded_item (stack)
				local empty = ItemStack ("mcl_buckets:bucket_empty")
				local inv = clicker:get_inventory ()
				if inv and inv:room_for_item ("main", empty) then
					inv:add_item ("main", empty)
				else
					core.add_item (clicker:get_pos (), empty)
				end
			end
		end
		return
	end

	-- Right-click with redstone dust recolours a tamed horse: cycle to the next
	-- base coat (brown, dark brown, white, gray, black...), keeping the current
	-- markings, one dust each use. No sneak needed -- holding redstone is itself
	-- the "recolour" mode, so it intercepts the click before mounting (you can't
	-- mount with redstone in hand). on_rightclick fires repeatedly while the
	-- button is held, so debounce: one step (and one dust) per press, giving the
	-- player time to see each coat before spending the next dust.
	if item_name == "mcl_redstone:redstone"
		and self.tamed and not self.driver and not self.child then
		local now = core.get_us_time () / 1e6
		if self._last_reskin and now - self._last_reskin < RESKIN_CD then return end
		self._last_reskin = now
		self:cycle_coat ()
		if not creative then
			stack:take_item ()
			clicker:set_wielded_item (stack)
		end
		return
	end

	-- Right-click with lapis lazuli swaps the marking overlay on a tamed horse:
	-- cycle to the next marking (snowflake, sooty, paint, stockings, none...),
	-- keeping the current coat, one lapis per press (same no-sneak intercept and
	-- debounce as the redstone recolour -- you can't mount with lapis in hand).
	if item_name == "mcl_core:lapis"
		and self.tamed and not self.driver and not self.child then
		local now = core.get_us_time () / 1e6
		if self._last_reskin and now - self._last_reskin < RESKIN_CD then return end
		self._last_reskin = now
		self:cycle_markings ()
		if not creative then
			stack:take_item ()
			clicker:set_wielded_item (stack)
		end
		return
	end

	-- Sneak + right-click opens the saddle/armor inventory (remove items here).
	if clicker:get_player_control ().sneak and self.tamed and not self.driver then
		self:open_inventory (clicker)
		return
	end

	-- Feeding.
	if self:follow_holding(clicker) then
		if not self.tamed then
			-- A wild horse can't be tamed by food alone, but feeding gentles it:
			-- raise its temper (improving the odds the next bareback ride sticks)
			-- and heal/feed it. It must still be ridden in to actually tame.
			self:init_taming ()
			if self._temper < TAME_MAX_TEMPER then
				self._temper = math.min (TAME_MAX_TEMPER, self._temper + TAME_FOOD_TEMPER)
			end
			local maxhp = self.object:get_properties ().hp_max
			if self.health and self.health < maxhp then self:heal_mob (1, maxhp) end
			self:init_needs ()
			self._hunger = math.min (NEED_MAX, self._hunger + FEED_GAIN)
			core.sound_play ("mobs_mc_animal_eat_generic", {
				gain = 0.7, max_hear_distance = 8, pos = self.object:get_pos (),
			}, true)
			if not creative then
				stack:take_item ()
				clicker:set_wielded_item (stack)
			end
			return
		end
		-- Tamed: heal / breed (taming is already done). feed_tame handles the
		-- wield-item removal itself.
		if self:feed_tame(clicker, 4, true, false, false, 1.0) then
			-- Hand-feeding also fills the hunger meter (Phase 2).
			self:init_needs ()
			self._hunger = math.min (NEED_MAX, self._hunger + FEED_GAIN)
			return
		end
	end

	if self.child then return end

	-- Wild horse: an EMPTY hand mounts it bareback to break it in (it'll buck or
	-- be tamed -- see update_taming); right-clicking again gets off. Any other
	-- item just gives a hint, since a wild horse can't be saddled or geared yet.
	if not self.tamed then
		if item_name == "" then
			if self.driver and clicker == self.driver then
				self:detach (clicker, {x = 1, y = 0, z = 0})
			else
				self:try_bareback_mount (clicker)
			end
		else
			core.chat_send_player (clicker:get_player_name (),
				S("This horse is wild. Ride it bareback (empty hand) to tame it."))
		end
		return
	end

	-- Mount / dismount a (tamed) saddled horse.
	if self.saddle == "yes" then
		if self.driver and clicker == self.driver then
			self:detach(clicker, {x = 1, y = 0, z = 0})
		elseif not self.driver then
			self:init_attachment_position()
			self:attach(clicker)
		end
	end
end

-- Hoof gait sounds (ridden only). Luanti plays a node's sounds.footstep CLIENT-SIDE
-- for the local player's own movement only -- there is no per-step event for mobs,
-- and synthesising the rhythm by triggering single clops per footfall never sounded
-- right (esp. the gallop, whose paired beats land finer than the ~0.1s server tick).
-- So instead we LOOP a real per-gait, per-surface recording for as long as the horse
-- holds that gait on that ground -- the recording carries the true rhythm and timbre.
-- 16 loops = {walk,trot,canter,gallop} x {hard,dirt,gravel,sand}; CC0/CC BY sources
-- are credited in LICENSE-media.md.
local HOOF_HEAR      = 16     -- max_hear_distance
local HOOF_MIN_SPEED = 0.5    -- below this the horse counts as stopped (loop off)
local HOOF_FADE_STEP = 6.0    -- gain/s when fading a loop out on a gait/surface change

local EAT_GAIN = 0.7          -- chewing loop volume while head-down grazing (hunger)
local EAT_HEAR = 12

-- Ambient neigh: an occasional whinny while unridden + calm, plus one on taming.
local NEIGH_GAIN = 0.8
local NEIGH_HEAR = 24
local NEIGH_MIN  = 18.0       -- random seconds between ambient neighs
local NEIGH_MAX  = 50.0

-- anim name (set by horse:drive) -> gait key. "run" is the gallop clip.
local GAIT_OF = {walk = "walk", trot = "trot", canter = "canter", run = "gallop"}

-- Per-surface loudness: damped ground (sand/dirt) is quieter than a ringing hard
-- surface. The loops are all normalised to the same peak; this is the level knob.
local SURFACE_GAIN = {hard = 0.9, gravel = 0.7, dirt = 0.5, sand = 0.4}

-- A node's own footstep sound NAME -> our surface category (reuses Mineclonia's
-- material tagging). Unmatched ground falls back to "dirt".
local SURFACE_TAG = {
	sand = "sand", gravel = "gravel",
	dirt = "dirt", grass = "dirt", snow = "dirt", mud = "dirt",
	hard = "hard", stone = "hard", wood = "hard", metal = "hard",
	glass = "hard", ice = "hard",
}

-- Which (gait, surface) cells ship a dedicated loop. The BigSoundBank set (CC0,
-- June 2026) covers walk on hard/dirt/gravel and trot/canter on dirt/gravel; gallop
-- reuses the canter dirt/gravel loops sped up to 1.2x. Any surface a gait lacks
-- falls back to that gait's "dirt" loop.
local GAIT_SURFACES = {
	walk   = {hard = true, dirt = true, gravel = true},          -- sand -> dirt
	trot   = {dirt = true, gravel = true},                       -- hard, sand -> dirt
	canter = {dirt = true, gravel = true},                       -- hard, sand -> dirt
	gallop = {dirt = true, gravel = true},                       -- hard, sand -> dirt
}

-- GAIT_LOOP[gait][surface] = looping sound name (files in sounds/).
local GAIT_LOOP = {}
for _, g in ipairs ({"walk", "trot", "canter", "gallop"}) do
	GAIT_LOOP[g] = {}
	for _, s in ipairs ({"hard", "dirt", "gravel", "sand"}) do
		local use = GAIT_SURFACES[g][s] and s or "dirt"
		GAIT_LOOP[g][s] = "edoras_horse_gait_" .. g .. "_" .. use
	end
end

-- Classify the ground under the horse into a surface category, or nil if it isn't
-- over a node with a footstep sound.
local function surface_for (self)
	local node = self.standing_on
	if not node or node == "air" or node == "ignore" then return nil end
	local def = core.registered_nodes[node]
	local fs = def and def.sounds and def.sounds.footstep
	if not fs or not fs.name then return nil end
	for tag in fs.name:gmatch ("[a-z]+") do
		if SURFACE_TAG[tag] then return SURFACE_TAG[tag] end
	end
	return "dirt"
end

-- Stop the current gait loop, fading it out so it doesn't click off.
local function stop_gait_loop (self)
	if self._loop_handle then
		core.sound_fade (self._loop_handle, HOOF_FADE_STEP, 0.0)
		self._loop_handle = nil
	end
	self._loop_key = nil
end

-- Start/stop/switch the per-gait, per-surface loop to match the horse's state each
-- tick. Ridden only; loops while moving forward on solid ground, silent otherwise.
function horse:update_hoofsteps (dtime)
	local key, sound, gain
	if self.driver then
		local gait = GAIT_OF[self._current_animation or ""]
		local in_water = core.get_item_group (self.standing_in or "", "water") > 0
		local vel = self.object:get_velocity ()
		local speed = math.sqrt (vel.x * vel.x + vel.z * vel.z)
		if gait and not in_water and speed >= HOOF_MIN_SPEED then
			local surf = surface_for (self)
			if surf then
				key   = gait .. "|" .. surf
				sound = GAIT_LOOP[gait][surf]
				gain  = SURFACE_GAIN[surf]
			end
		end
	end
	if key == self._loop_key then return end     -- gait + surface unchanged
	stop_gait_loop (self)
	if sound then
		self._loop_handle = core.sound_play (sound, {
			object = self.object,                -- follows the horse as it moves
			gain = gain,
			max_hear_distance = HOOF_HEAR,
			loop = true,
		})
		self._loop_key = key
	end
end

-- Loop the chewing sound while the horse is head-down eating (hunger graze only,
-- not drinking). Attached to the horse so it follows it and stops on unload.
function horse:update_eating ()
	local eating = self._grazing and self._forage_for == "hunger"
		and not self.driver and not self._fleeing
	if eating then
		if not self._eat_handle then
			self._eat_handle = core.sound_play ("edoras_horse_eat_grass", {
				object = self.object,
				gain = EAT_GAIN,
				max_hear_distance = EAT_HEAR,
				loop = true,
			})
		end
	elseif self._eat_handle then
		core.sound_fade (self._eat_handle, HOOF_FADE_STEP, 0.0)
		self._eat_handle = nil
	end
end

-- Play a random whinny at the horse (ambient timer + on taming).
function horse:neigh (gain)
	core.sound_play ("edoras_horse_neigh", {
		object = self.object,
		gain = gain or NEIGH_GAIN,
		max_hear_distance = NEIGH_HEAR,
		pitch = 0.94 + math.random () * 0.12,   -- slight per-call variation
	})
end

-- Tick the ambient-neigh countdown; whinny now and then when unridden and calm.
function horse:update_ambient (dtime)
	if self.driver or self._fleeing then return end
	self._neigh_timer = (self._neigh_timer
		or NEIGH_MIN + math.random () * (NEIGH_MAX - NEIGH_MIN)) - dtime
	if self._neigh_timer <= 0 then
		self._neigh_timer = NEIGH_MIN + math.random () * (NEIGH_MAX - NEIGH_MIN)
		self:neigh ()
	end
end

-- Trampling charge: a GALLOPING or CANTERING edoras horse runs hostile mobs down.
-- Damage scales with the horse's armor (heavier metal = a harder hit); at a gallop
-- diamond one-shots a spider (16 hp) or a zombie (20 hp). An unarmored horse still
-- tramples on its own mass, just lightly. A canter hits softer than a gallop (see
-- the CUT constants below). TRAMPLE_DMG holds the full (gallop) values, keyed off
-- the armor itemstring.
local TRAMPLE_DMG = {
	[""]                                 = 4,   -- bareback / no armor
	["mcl_mobitems:leather_horse_armor"] = 7,
	["mcl_mobitems:copper_horse_armor"]  = 10,
	["mcl_mobitems:iron_horse_armor"]    = 14,
	["mcl_mobitems:gold_horse_armor"]    = 17,
	["mcl_mobitems:diamond_horse_armor"] = 22,  -- one-hit kills a spider / zombie
	["edoras_horse:knight_horse_armor"]  = 18,  -- between gold and diamond
}
-- A canter hits for less than a gallop: -2 with any armor, -1 bareback.
local TRAMPLE_CANTER_CUT          = 2
local TRAMPLE_CANTER_CUT_BAREBACK = 1
-- Hostile mobs a charge will trample: skeletons, spiders, illagers, witches,
-- zombies, piglins, evoker -- plus the obvious variant of each family.
local TRAMPLE_TARGETS = {
	["mobs_mc:skeleton"] = true,   ["mobs_mc:stray"] = true,
	["mobs_mc:spider"] = true,     ["mobs_mc:cave_spider"] = true,
	["mobs_mc:pillager"] = true,   ["mobs_mc:vindicator"] = true,
	["mobs_mc:evoker"] = true,     ["mobs_mc:witch"] = true,
	["mobs_mc:zombie"] = true,     ["mobs_mc:husk"] = true,
	["mobs_mc:drowned"] = true,
	["mobs_mc:piglin"] = true,     ["mobs_mc:piglin_brute"] = true,
	["mobs_mc:zombified_piglin"] = true,
}
local TRAMPLE_REACH   = 2.2    -- how close a target must be to get run over (nodes)
local TRAMPLE_MIN_SPD = 3.5    -- min horizontal speed to count as a charge (m/s);
                               -- below both gaits' min so a slow canter still counts
local TRAMPLE_KB      = 6.0    -- knockback dealt to a trampled mob
local TRAMPLE_CD      = 0.6    -- per-target re-hit cooldown (s)
local TRAMPLE_SCAN    = 0.15   -- how often a galloping horse scans for targets (s)

-- Run down hostile mobs while galloping. Punches each target (so it routes through
-- mcl_mobs' normal damage/knockback/death, crediting the horse) with armor-scaled
-- fleshy damage. Per-target cooldown stamped on the victim so one charge doesn't
-- multi-hit the same mob every tick.
function horse:trample (dtime)
	-- Gallop or canter only (clips named "run"/"canter" in GAITS), at a real charge speed.
	local gait = self._current_animation or ""
	if gait ~= "run" and gait ~= "canter" then return end
	self._trample_cd = (self._trample_cd or 0) - dtime
	if self._trample_cd > 0 then return end
	self._trample_cd = TRAMPLE_SCAN
	local v = self.object:get_velocity ()
	if not v or (v.x * v.x + v.z * v.z) < TRAMPLE_MIN_SPD * TRAMPLE_MIN_SPD then
		return
	end
	local pos = self.object:get_pos ()
	if not pos then return end
	local armor = (self._armor and self._armor ~= "")
		and ItemStack (self._armor):get_name () or ""
	local dmg = TRAMPLE_DMG[armor] or TRAMPLE_DMG[""]
	-- A canter lands softer than a gallop.
	if gait == "canter" then
		dmg = dmg - ((armor == "") and TRAMPLE_CANTER_CUT_BAREBACK or TRAMPLE_CANTER_CUT)
	end
	local dir = vector.normalize (vector.new (v.x, 0, v.z))
	local now = core.get_us_time () / 1e6
	for _, obj in ipairs (core.get_objects_inside_radius (pos, TRAMPLE_REACH)) do
		if obj ~= self.object then
			local le = obj:get_luaentity ()
			if le and TRAMPLE_TARGETS[le.name]
				and (le._edoras_trample_t or 0) <= now - TRAMPLE_CD then
				le._edoras_trample_t = now
				obj:punch (self.object, 1.0, {
					full_punch_interval = 1.0,
					damage_groups = {fleshy = dmg, knockback = TRAMPLE_KB},
				}, dir)
			end
		end
	end
end

-- Per-tick custom logic: drain biological needs (which may buck the rider),
-- make an unridden horse flee at a canter, and let the rider dismount by sneaking.
function horse:do_custom (dtime, moveresult)
	self:update_needs (dtime)
	self:update_taming (dtime)
	self:update_hoofsteps (dtime)
	self:update_eating ()
	self:update_ambient (dtime)
	self:trample (dtime)
	-- Flee animation overlay: check_flee sets gowp_animation = "canter" so the path
	-- follower replays the canter clip; reinforce it here (do_custom runs after the
	-- movement step, so it wins if anything reset the clip to walk/stand).
	if self._fleeing and not self.driver then
		self.gowp_animation = "canter"
		self:set_animation ("canter")
		self._grazing = false          -- bolt: abandon any graze in progress
	end
	-- Self-feeding overlay: while in the grazing hold, force the head-down clip and
	-- pin the horse so the stock movement code can't drag it off the food or swap
	-- the animation back to stand (mirrors the flee overlay above).
	if self._grazing and not self.driver and not self._fleeing then
		self:set_animation ("graze")
		local v = self.object:get_velocity ()
		self.object:set_velocity ({x = 0, y = v.y, z = 0})
	end
	-- Half-submerge a riderless horse in deep water (feet AND the node below both
	-- water -- so it's swimming, not wading at the shore). Stock floats=1 buoyancy
	-- (in the physics step that ran before this) jumps it up to ride on the
	-- surface; we override velocity.y here -- this runs after that step, so it wins
	-- -- to hold the waterline across the middle of the body. Horizontal velocity
	-- is left untouched so a swim-to-shore path (check_water_escape) still steers.
	-- Don't pin the horse down while it's pressed against a shore (horiz collision)
	-- or already leaping clear (v.y high): that's it climbing out, and overriding
	-- velocity.y here would cancel the engine's breach leap. Let it float up and go.
	if not self.driver
		and core.get_item_group (self.standing_in or "", "water") > 0
		and core.get_item_group (self.standing_on or "", "water") > 0
		and not horiz_collision (moveresult) then
		local pos = self.object:get_pos ()
		local surface = pos and water_surface_y (pos)
		if surface then
			local v = self.object:get_velocity ()
			if v.y < SWIM_BREACH_VY then
				local target_y = surface - SWIM_HEIGHT * SWIM_SUBMERGE
				v.y = math.max (-SWIM_SINK_MAX, math.min (SWIM_SINK_MAX,
					(target_y - pos.y) * SWIM_SINK_GAIN))
				self.object:set_velocity (v)
			end
		end
	end
	-- Rodeo buck overlay: ONLY while a WILD horse is ridden bareback. Set the flag +
	-- advance the buck phase before set_ride_pose (below) so the rider reacts in sync.
	local bucking = self.driver and not self.tamed
	if bucking then
		self._bucking = true
		self._buck_phase = (self._buck_phase or 0) + dtime
		self:set_animation ("buck")   -- buck clip now animates the head-toss itself
		self._buck_hop = (self._buck_hop or 0) + dtime
		if self._buck_hop >= BUCK_HOP_INTERVAL then
			self._buck_hop = 0
			local v = self.object:get_velocity ()
			self.object:set_velocity ({x = v.x, y = BUCK_HOP_SPEED, z = v.z})
		end
	elseif self._bucking then
		-- Just stopped bucking (tamed, or the rider was thrown). Clear the state and
		-- return to a normal stance, otherwise the buck clip keeps looping forever on
		-- a now-riderless/tamed horse (nothing else resets a do_custom-set animation).
		self._bucking = false
		self._buck_hop = 0
		if not self._fleeing and not self._grazing then
			self:set_animation ("stand")
		end
	end
	if self.driver then
		self:set_ride_pose (self.driver)   -- straddle pose (+ buck reaction if bucking)
		local controls = self.driver:get_player_control()
		if controls.sneak then
			self:detach(self.driver, {x = 1, y = 0, z = 1})
		end
	end
end

function horse:on_die ()
	stop_gait_loop (self)
	if self._eat_handle then
		core.sound_fade (self._eat_handle, HOOF_FADE_STEP, 0.0)
		self._eat_handle = nil
	end
	local pos = self.object:get_pos ()
	if self.driver then
		self:detach(self.driver, {x = 1, y = 0, z = 1})
	end
	if not pos then return end
	if self.saddle == "yes" then
		core.add_item (pos, "mcl_mobitems:saddle")
	end
	if self._armor and self._armor ~= "" then
		core.add_item (pos, self._armor)
	end
	if self:has_bag () then
		core.add_item (pos, self._bag)
	end
	if self._saddlebag then
		for _, s in ipairs (self._saddlebag) do
			if s ~= "" then
				core.add_item (pos, s)
			end
		end
	end
end

-- Restore textures + armor protection after the horse is reloaded.
function horse:after_activate ()
	self:init_needs ()
	self:init_genetics ()
	self:init_taming ()
	if self.saddle == "yes" or (self._armor and self._armor ~= "") or self:has_bag () then
		self:refresh_textures ()
	end
	if self._armor and self._armor ~= "" then
		local level = horse_armor_level (ItemStack (self._armor))
		if level > 0 then
			local agroups = self.object:get_armor_groups ()
			agroups.fleshy = level
			self.object:set_armor_groups (agroups)
		end
	end
end

-- AI priority: react to threats and breeding/holding first, then -- if a
-- biological meter is low -- forage for food/water, otherwise wander slowly in
-- place (the pace_* tunables above). follow_herd stays off so a content horse
-- doesn't drift toward others.
horse.ai_functions = {
	horse.check_buck,           -- being broken in bareback: halt + hold the buck clip
	horse.check_flee,           -- our canter-away flee (replaces check_frightened)
	mob_class.check_breeding,
	horse.check_lead,           -- trail the player when leashed ("leads" mod)
	mob_class.check_following,
	horse.check_water_escape,   -- riderless + in deep water: swim to the nearest shore
	horse.check_forage,
	mob_class.check_pace,
}

mcl_mobs.register_mob("edoras_horse:horse", horse)

------------------------------------------------------------------------
-- Legacy orphan migration. This mod was once named "rohan_horse"; worlds played
-- back then still hold saved rohan_horse:horse entities, which now spam
-- 'LuaEntity name "rohan_horse:horse" not defined' every time their mapblock
-- loads, because that name no longer exists. An unknown entity can only be
-- cleared once its name is DEFINED again, so we register it as a tiny stub that,
-- on activation, RE-CREATES the horse as a proper edoras_horse:horse carrying the
-- same saved data, then removes itself. The rename was a pure "rohan_horse" ->
-- "edoras_horse" string swap (entity/item/texture names), so rewriting that prefix
-- across every saved string fully restores the horse -- tame state, owner, saddle,
-- bag, armor, coat textures and speed genetics all transfer. core.register_entity
-- needs the ":" prefix to register a name outside this mod's namespace. Safe to
-- delete this block once existing worlds have been roamed clean of old orphans.
------------------------------------------------------------------------
do
	-- Recursively rewrite "rohan_horse" -> "edoras_horse" in every string within
	-- the saved staticdata table (values; field-name keys never contain it).
	local function remap (v)
		local t = type (v)
		if t == "string" then
			return (v:gsub ("rohan_horse", "edoras_horse"))
		elseif t == "table" then
			local r = {}
			for k, vv in pairs (v) do r[k] = remap (vv) end
			return r
		end
		return v
	end

	core.register_entity (":rohan_horse:horse", {
		get_staticdata = function () return "" end,
		on_activate = function (self, staticdata)
			local obj = self.object
			local pos = obj and obj:get_pos ()
			if pos then
				local sd = ""
				local tmp = staticdata and staticdata ~= ""
					and core.deserialize (staticdata)
				if type (tmp) == "table" then
					sd = core.serialize (remap (tmp))
				end
				core.add_entity (pos, "edoras_horse:horse", sd)
			end
			if obj then obj:remove () end
		end,
	})
end

-- Spawn egg (creative / give). No natural spawner yet.
mcl_mobs.register_egg("edoras_horse:horse", S("Edoras Horse"), "#c09e7d", "#523a28", 0)

------------------------------------------------------------------------
-- Saddlebag item + recipe (SWEN-style: 2 chests, 3 leather, 3 carpet).
-- Equip on a tamed horse (right-click, or via the gear inventory) to unlock
-- a 15-slot storage compartment that travels with the horse.
------------------------------------------------------------------------

core.register_craftitem("edoras_horse:saddlebag", {
	description = S("Saddlebag"),
	_doc_items_longdesc = S("A pair of leather saddlebags. Equip them on a "
		.. "tamed horse to carry extra items."),
	inventory_image = "edoras_horse_saddlebag.png",
	stack_max = 1,
})

core.register_craft({
	output = "edoras_horse:saddlebag",
	recipe = {
		{"mcl_chests:chest",     "",                      "mcl_chests:chest"},
		{"mcl_mobitems:leather", "mcl_mobitems:leather",  "mcl_mobitems:leather"},
		{"group:carpet",         "group:carpet",          "group:carpet"},
	},
})

------------------------------------------------------------------------
-- Knight Horse Armor: a loot-only horse armor (no recipe) found in dungeon
-- chests. It is a brand-new item -- not a reskin of a vanilla one -- so it
-- carries the "horse_armor" group (protection) itself, renders via ARMOR_OVERLAY
-- (edoras_horse_armor_knight.png), and tramples at 18 (TRAMPLE_DMG above). The
-- horse_armor value is the fleshy damage % the horse takes: vanilla runs leather
-- 88 -> diamond 56 (lower = tougher), so 58 puts knight just shy of diamond.
------------------------------------------------------------------------

core.register_craftitem ("edoras_horse:knight_horse_armor", {
	description = S("Knight Horse Armor"),
	_doc_items_longdesc = S("Ornate barding worn by a horse for great protection. "
		.. "Found only in the chests of the realm's old and dangerous places."),
	inventory_image = "edoras_horse_armor_knight_inv.png",
	_horse_overlay_image = "edoras_horse_armor_knight.png",
	sounds = { _mcl_armor_equip = "mcl_armor_equip_iron" },
	stack_max = 1,
	groups = { horse_armor = 58 },
})

-- Drop the knight armor into existing Mineclonia loot pools without editing any
-- game file: mcl_structures keeps each structure's loot in the live table
-- mcl_structures.registered_structures[name].loot, which is read at mapgen time,
-- so appending an entry now takes effect for every later-generated chest. We walk
-- each target structure's loot, find every pool that has an `items` list, and add
-- one weighted knight entry. Dungeon/mineshaft loot lives in module-private locals
-- (mcl_dungeons / tsm_railcorridors) we cannot reach this way -- see note to user.
core.register_on_mods_loaded (function ()
	if not (mcl_structures and mcl_structures.registered_structures) then
		core.log ("warning", "[edoras_horse] mcl_structures absent -- knight armor "
			.. "registered but NOT added to any loot")
		return
	end
	local KNIGHT_LOOT = { itemstring = "edoras_horse:knight_horse_armor", weight = 1 }
	-- desert/jungle temples + the underwater ocean ruin treasure ("ocean_temple").
	local targets = { "desert_temple", "jungle_temple", "ocean_temple" }
	local added = 0
	for _, name in ipairs (targets) do
		local def = mcl_structures.registered_structures[name]
		if def and def.loot then
			-- loot = { [chest_node] = { pool, pool, ... } }; each pool has .items.
			for _, pools in pairs (def.loot) do
				for _, pool in pairs (pools) do
					if type (pool) == "table" and type (pool.items) == "table" then
						pool.items[#pool.items + 1] = table.copy (KNIGHT_LOOT)
						added = added + 1
					end
				end
			end
		else
			core.log ("warning", "[edoras_horse] loot target '" .. name
				.. "' not found -- skipped")
		end
	end
	core.log ("action", "[edoras_horse] knight armor added to " .. added
		.. " loot pool(s)")
end)

------------------------------------------------------------------------
-- Natural spawning. Mirrors the vanilla mcl horse spawner (grass surface,
-- light >= 8, "creature" category) so Edoras horses populate the same
-- Plains/Savanna niche after the mcl horse spawner is disabled. Built on
-- mobs_mc.animal_spawner (always present under Mineclonia). register_spawner
-- must run at load time -- it errors if called after mod init.
------------------------------------------------------------------------

if mobs_mc and mobs_mc.animal_spawner then
	-- Generous weights so herds are easy to find: vanilla horse was 5, and
	-- sheep/pig/chicken sit at 10-12, so 30 makes Edoras horses a common
	-- Plains animal.
	mcl_mobs.register_spawner(table.merge(mobs_mc.animal_spawner, {
		name = "edoras_horse:horse",
		weight = 30,
		pack_min = 2,
		pack_max = 6,
		biomes = {"Plains", "SunflowerPlains"},
	}))
	mcl_mobs.register_spawner(table.merge(mobs_mc.animal_spawner, {
		name = "edoras_horse:horse",
		weight = 12,
		pack_min = 2,
		pack_max = 6,
		biomes = {"#is_savannah"},
	}))
	core.log("action", "[edoras_horse] registered wild spawners (Plains w=30, Savanna w=12)")
else
	core.log("warning",
		"[edoras_horse] mobs_mc.animal_spawner unavailable -- NO wild spawner registered")
end
