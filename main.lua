mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
mods["hinyb-Dropability"].auto()
mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
mods["hinyb-Dropability"].auto()

require("Utils.lua")
require("SkillModifier")
require("SkillModifierData")
require("SkillModifierManager")
require("skillPickupCompat")

mods["MGReturns-ENVY"].auto()
envy = mods["MGReturns-ENVY"]
public_things = {
    ["SkillModifierManager"] = SkillModifierManager
} -- Maybe using a wrong way
require("./envy_setup")

local names = path.get_files(_ENV["!plugins_mod_folder_path"] .. "/SkillModifiers")
for _, name in ipairs(names) do
    require(name)
end

local DRONEOFFSET = 48

local function init()
    local function get_x_range_min(inst)
        local x_range_min = math.huge
        for slot_index = 0, 3 do
            local skill = gm.array_get(inst.skills, slot_index).active_skill
            if skill.skill_id ~= 0 then
                local x_range = Utils.skill_get_range(skill.skill_id)
                if x_range_min > x_range then
                    x_range_min = x_range
                end
            end
        end
        return x_range_min
    end

    local moon = Resources.sprite_load("hinyb", "moon", _ENV["!plugins_mod_folder_path"] .. "/sprites/moon.png")
    local star = Resources.sprite_load("hinyb", "star", _ENV["!plugins_mod_folder_path"] .. "/sprites/star.png")

    local oSkillDrone = Object.new("hinyb", "oSkillDrone", Object.PARENT.drone)
    oSkillDrone:onCreate(function(self)
        self.sprite_idle = self.sprite_index
        self.sprite_idle_broken = self.sprite_index
        self.sprite_shoot1 = self.sprite_index
        self.sprite_shoot1_broken = self.sprite_index
        self:drone_stats_init(200)
        self:init_actor_late()
        CompatibilityPatch.set_compat(self.value)
        gm.actor_skill_set(self.value, 0, 2)
        gm.actor_skill_set(self.value, 1, 1)
        gm.actor_skill_set(self.value, 2, 4)
        gm.actor_skill_set(self.value, 3, 4)
        self.x_range = 1200
        self.x_range_min = get_x_range_min(self.value)
        self.y_offset = 0
        self.image_alpha = 0.5

        -- I just find all skills which use hold_facing_direction_xscale have this bug.
        -- Need time to find a better solution.
        Instance_ext.add_callback(self.value, "pre_skill_activate", "hold_facing_direction_xscale_fix",
            function(inst, slot_index)
                inst.hold_facing_direction_xscale = inst.image_xscale
            end)
    end)
    oSkillDrone:onStep(function(self)
        local master = self.master
        if not Instance.exists(master) then
            return
        end
        if master.dead then
            self.hp = -10
            self:acotr_death(true)
            return
        end

        self:skill_system_update()

        --[[
        if self.is_local then
            if not gm.instance_exists(self.target) then
                local x = (self.x + self.master.x) / 2
                local y = (self.y + self.master.y) / 2
                local new_target = gm.find_target_nearest(x, y, 2)
                if new_target == -4 or self:distance_to_object(new_target) > self.x_range then
                    self.state = 0
                    return
                else
                    self.state = 1
                    self.target = new_target
                end
            else
                local target_parent = self.target.parent
                local target_x = Utils.clamp(self.x, target_parent.bbox_left, target_parent.bbox_right)
                local target_y = Utils.clamp(self.y, target_parent.bbox_top, target_parent.bbox_bottom)
                if gm.point_distance(master.x, master.y, target_x, target_y) > 0 then
                    if math.abs(master.x - target_x) < self.x_range and math.abs(master.y - target_y) < self.y_range then
                        Utils.set_and_sync_inst_from_table(self.value, {
                            target = -4,
                            state = 0
                        })
                    end
                end
            end
        end]]
        local image_index = self.image_index
        local image_number = self.image_number
        if math.abs(image_index - image_number + 1) <= 0.0001 or image_index >= image_number - 1 then
            self.sprite_index = oSkillDrone.obj_sprite
        end
        self.z_skill = 0
        self.x_skill = 0
        self.c_skill = 0
        self.v_skill = 0
        if self.state == 0 then
            local lerp_factor = (1 - self.chase_motion_lerp) * 0.1111111111111111
            self.x = Utils.lerp(self.x, master.ghost_x + self.xx, lerp_factor)
            self.y = Utils.lerp(self.y, master.ghost_y + self.yy - 100 - DRONEOFFSET, lerp_factor) + self.yo
            self.chase_motion_lerp = math.max(self.chase_motion_lerp - 0.4, 0)
            self.image_xscale = master.image_xscale
            --[[
            if not gm.instance_exists(self.target) then
                local x = (self.x + self.master.x) / 2
                local y = (self.y + self.master.y) / 2
                local new_target = gm.find_target_nearest(x, y, 2)
                if new_target ~= -4 and self:distance_to_object(new_target) <= self.x_range then
                    self.target = new_target
                end
            end]]
        elseif self.state == 1 then
            local target = self.target
            if Instance.exists(target) then
                local target_parent = target.parent
                self.x = Utils.lerp(self.x,
                    Utils.lerp(Utils.clamp(self.master.x + self.xx, target_parent.bbox_left - self.x_range_min,
                        target_parent.bbox_right + self.x_range_min), self.master.x + self.xx, 0.1),
                    self.chase_motion_lerp * 0.075)
                self.y = Utils.lerp(self.y,
                    Utils.lerp(
                        Utils.clamp(self.master.y + self.y_offset, target_parent.bbox_top, target_parent.bbox_bottom),
                        self.master.y + self.yy, 0.1) + self.yo, self.chase_motion_lerp * 0.075)
                self.chase_motion_lerp = math.min(1.0, self.chase_motion_lerp + 0.4)
                if self.x > target_parent.x then
                    self.image_xscale = -1
                else
                    self.image_xscale = 1
                end
                local table = {0, 1, 2, 3}
                Utils.simple_shuffle_table(table)
                for i = 1, #table do
                    local slot_index = table[i]
                    if self:skill_can_activate(slot_index) then
                        self[Utils.get_name_with_slot_index(slot_index) .. "_skill"] = 1
                        break
                    end
                end
            end
        end
    end)
    oSkillDrone:onDraw(function(self)
        gm.draw_sprite_ext(moon, 0, self.x, self.y + DRONEOFFSET, 0.6, 0.6, 0.0, Color.WHITE, 1)
    end)
    local my_surface = gm.surface_create(32, 32)
    gm.surface_set_target(my_surface)
    oSkillDrone.obj_sprite = gm.sprite_create_from_surface(my_surface, 0, 0, 32, 32, false, false, 64, 64)
    gm.surface_reset_target()
    gm.surface_free(my_surface)
    local skill_scale = 0.5
    gm.post_script_hook(gm.constants.actor_skill_set, function(self, other, result, args)
        local inst_wrapped = Instance.wrap(args[1].value)
        local object_index = inst_wrapped:get_object_index_self()
        if object_index ~= oSkillDrone.value then
            return
        end
        local slot_index = args[2].value
        local skill = inst_wrapped:get_active_skill(slot_index)
        local angular_speed = 1 / math.log(skill.cooldown) * 0.05
        local angle = slot_index * math.pi / 2
        local radius = 24
        local name = "star_draw" .. Utils.to_string_with_floor(slot_index)
        local default_skill = Class.SKILL:get(skill.skill_id)
        local sprite_index = default_skill:get(4)
        local image_index = default_skill:get(5)
        local required_stock = default_skill:get(11)
        inst_wrapped:remove_callback(name)
        inst_wrapped:add_callback("onPostDraw", name, function(actor)
            angle = angle + angular_speed
            local x = actor.x + radius * math.cos(angle)
            local y = actor.y + radius * math.sin(angle) + DRONEOFFSET
            if skill.stock < required_stock then
                gm.draw_sprite_ext(sprite_index, image_index, x + 5, y + 5, skill_scale, skill_scale, 0.0, Color.GRAY, 1)
            else
                gm.draw_sprite_ext(sprite_index, image_index, x + 5, y + 5, skill_scale, skill_scale, 0.0, Color.WHITE, 1)
            end
        end)
    end)
end
Initialize(init)
