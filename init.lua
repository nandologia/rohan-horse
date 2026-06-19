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
-- Layer 2 is the coat plus any armor overlay; layer 3 exposes the saddle
-- mesh by giving it the coat texture (which holds the saddle pixels), or
-- BLANK to hide it. _naked_fur preserves the bare coat across equips.
function horse:refresh_textures ()
	local fur = self._naked_fur or (self.base_texture and self.base_texture[2])
	if not fur then return end
	self._naked_fur = fur
	local body = fur
	if self._armor and self._armor ~= "" then
		local def = core.registered_items[ItemStack(self._armor):get_name ()]
		if def and def._horse_overlay_image then
			body = fur .. "^" .. def._horse_overlay_image
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

-- Equip / remove. These do not move items; callers handle item transfer.
function horse:apply_saddle ()
	self.saddle = "yes"
	self.tamed = true
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

function horse:apply_bag ()
	self._bag = SADDLEBAG_ITEM
	self.tamed = true
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

-- Seat position on the canonical horse mesh (matches mobs_mc:horse).
function horse:init_attachment_position ()
	local vsize = self.object:get_properties().visual_size
	self.driver_attach_at = {x = 0, y = 4.17, z = -1.75}
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
	core.sound_play ("mobs_mc_animal_eat_generic", {
		gain = 0.6, max_hear_distance = 12, pos = self.object:get_pos (),
	}, true)
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

function horse:on_rightclick (clicker)
	if not clicker or not clicker:is_player() then return end
	local stack = clicker:get_wielded_item ()
	local item_name = stack:get_name ()
	local creative = core.is_creative_enabled (clicker:get_player_name ())

	-- Put a saddle on (also tames).
	if item_name == "mcl_mobitems:saddle" and self.saddle ~= "yes"
		and not self.child then
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

	-- Sneak + right-click opens the saddle/armor inventory (remove items here).
	if clicker:get_player_control ().sneak and self.tamed and not self.driver then
		self:open_inventory (clicker)
		return
	end

	-- Feed to heal / breed / tame.
	-- Pass notake=false and tamechance=1.0 explicitly: older Mineclonia
	-- (gondor, release 33876) doesn't default tamechance, so omitting it
	-- makes feeding an untamed horse error on `math.random() <= nil` before
	-- the heal ever runs. Newer Mineclonia (local) defaults it to 1.0, so
	-- passing it changes nothing there.
	if self:follow_holding(clicker) then
		if self:feed_tame(clicker, 4, true, true, false, 1.0) then
			-- Hand-feeding also fills the hunger meter (Phase 2).
			self:init_needs ()
			self._hunger = math.min (NEED_MAX, self._hunger + FEED_GAIN)
			return
		end
	end

	if self.child then return end

	-- Mount / dismount a saddled horse.
	if self.saddle == "yes" then
		if self.driver and clicker == self.driver then
			self:detach(clicker, {x = 1, y = 0, z = 0})
		elseif not self.driver then
			self:init_attachment_position()
			self:attach(clicker)
		end
	end
end

-- Per-tick custom logic: drain biological needs (which may buck the rider),
-- make an unridden horse flee at a canter, and let the rider dismount by sneaking.
function horse:do_custom (dtime)
	self:update_needs (dtime)
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
	if self.driver then
		local controls = self.driver:get_player_control()
		if controls.sneak then
			self:detach(self.driver, {x = 1, y = 0, z = 1})
		end
	end
end

function horse:on_die ()
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
	horse.check_flee,           -- our canter-away flee (replaces check_frightened)
	mob_class.check_breeding,
	mob_class.check_following,
	horse.check_forage,
	mob_class.check_pace,
}

mcl_mobs.register_mob("edoras_horse:horse", horse)

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
-- Natural spawning. Mirrors the vanilla mcl horse spawner (grass surface,
-- light >= 8, "creature" category) so Edoras horses populate the same
-- Plains/Savanna niche after the mcl horse spawner is disabled. Built on
-- mobs_mc.animal_spawner (always present under Mineclonia). register_spawner
-- must run at load time -- it errors if called after mod init.
------------------------------------------------------------------------

if mobs_mc and mobs_mc.animal_spawner then
	-- Generous weights so herds are easy to find: vanilla horse was 5, and
	-- sheep/pig/chicken sit at 10-12, so 30 makes Edoras horses the dominant
	-- Plains animal (filling the gap left by Animalia + the disabled mcl horse).
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
