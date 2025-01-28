mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
mods["hinyb-Dropability"].auto()

local DRONEOFFSET = 48
local RANGEOFFSET = -40
local PICKUPRANGE = 40
local SKILLSCALE = 0.5
local function init()
    local get_random = Utils.random_skill_id()
    local drone_skill_blacklist = {
        [129] = true, -- drifterX -- It's difficult to form a combo. So I decided blacklist it.
        [130] = true, -- drifterC
        [131] = true, -- drifterV
        [132] = true, -- drifterVBoosted
        [133] = true, -- drifterX2
        [134] = true, -- drifterC2
        [135] = true, -- drifterV2
        [136] = true, -- drifterV2Boosted
        [141] = true, -- robomandoV
        [98] = true -- loaderX2 -- Drone can't hit the ground
    }
    local function drone_skill_check(skill_id)
        return Utils.is_damage_skill(skill_id) and not drone_skill_blacklist[skill_id]
    end
    local function get_drone_random_skill_id()
        local random_skill_id = get_random()
        while not drone_skill_check(random_skill_id) do
            random_skill_id = get_random()
        end
        return random_skill_id
    end
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
    local function is_in_range(x1, y1, x2, y2, range)
        return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
    end
    local moon = Resources.sprite_load("hinyb", "moon", _ENV["!plugins_mod_folder_path"] .. "/sprites/moon.png", 1, 16,
        16)
    local star = Resources.sprite_load("hinyb", "star", _ENV["!plugins_mod_folder_path"] .. "/sprites/star.png", 1, 16,
        16)
    -- this mod don't relay on SkillChest
    -- so I have to do this
    local oSkillDrone_skill_packet = Packet.new()
    oSkillDrone_skill_packet:onReceived(function(message, player)
        local drone = message:read_instance().value
        local slot_index = message:read_byte()
        local skill_id = message:read_ushort()
        gm.actor_skill_set(drone, slot_index, skill_id)
    end)
    local skill_drone_skill_message_create = function(drone, slot_index, skill_id)
        local sync_message = oSkillDrone_skill_packet:message_begin()
        sync_message:write_instance(drone)
        sync_message:write_byte(slot_index)
        sync_message:write_ushort(skill_id)
        return sync_message
    end
    local oSkillDrone_pick_packet = Packet.new()
    oSkillDrone_pick_packet:onReceived(function(message, player)
        local drone = message:read_instance().value
        local skill_pickup = message:read_instance().value
        drone.cache_skill_pickup = skill_pickup
    end)
    local skill_drone_pick_message_create = function(drone, skill_pickup)
        local sync_message = oSkillDrone_pick_packet:message_begin()
        sync_message:write_instance(drone)
        sync_message:write_instance(skill_pickup)
        return sync_message
    end
    local oSkillDroneItem = Object.new("hinyb", "oSkillDroneItem", Object.PARENT.interactableDrone)
    local oSkillDrone = Object.new("hinyb", "oSkillDrone", Object.PARENT.drone)
    oSkillDrone:onCreate(function(self)
        -- need to draw a sprite, but I am lazy.
        self.sprite_idle = self.sprite_index
        self.sprite_idle_broken = self.sprite_index
        self.sprite_shoot1 = self.sprite_index
        self.sprite_shoot1_broken = self.sprite_index
        self:drone_stats_init(200)
        self:init_actor_late()
        CompatibilityPatch.set_compat(self.value)
        self.x_range = 1200
        self.x_range_min = 40
        self.y_offset = 0
        self.image_alpha = 0.5
        self.cache_skill_pickup = -4
        self.interactable_child = oSkillDroneItem.value

        -- because the sprite is empty
        gm._mod_instance_set_mask(self.value, gm.constants.sPMask)

        -- I just find all skills which use hold_facing_direction_xscale have this bug.
        -- Need time to find a better solution.
        Instance_ext.add_callback(self.value, "pre_skill_activate", "hold_facing_direction_xscale_fix",
            function(inst, slot_index)
                inst.hold_facing_direction_xscale = inst.image_xscale
            end)
        Instance_ext.add_callback(self.value, "pre_actor_set_dead", "drop_skill_pickup", function(inst_)
            for slot_index = 0, 3 do
                local skill = gm.array_get(inst_.skills, slot_index).active_skill
                if skill.skill_id ~= 0 then
                    SkillPickup.drop_skill(inst_, skill)
                end
            end
        end)

        -- custom drone will create twice
        -- terrible solution, need time to improve
        local callstack = Array.wrap(gm.debug_get_callstack())
        for i = 0, callstack:size() - 1 do
            if string.find(callstack:get(i), "net_packet_create_object_read") then
                self:destroy()
            end
        end
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

        -- to fix combo attack loaderZ and pilotZ.
        -- It will reset on client. So I put it here.
        self.z_tap_buffered = 1

        self:skill_system_update()

        local image_index = self.image_index
        local image_number = self.image_number
        if self.state_strafe_half == 1.0 or math.abs(image_index - image_number + 1) <= 0.0001 or image_index >=
            image_number - 1 then
            self.sprite_index = oSkillDrone.obj_sprite
        end
        self.z_skill = 0
        self.x_skill = 0
        self.c_skill = 0
        self.v_skill = 0

        if self.state == 0 then
            self.sprite_index = oSkillDrone.obj_sprite
            if gm.bool(self.is_local) and not Instance.exists(self.cache_skill_pickup) then
                local skill_pickup = gm._mod_instance_nearest(SkillPickup.skillPickup_object_index, self.x, self.y)
                if skill_pickup ~= -4 and drone_skill_check(skill_pickup.skill_id) and
                    skill_pickup.has_been_drone_pickup ~= 1 and
                    is_in_range(self.x, self.y, skill_pickup.x, skill_pickup.y, self.y_range) then
                    self.cache_skill_pickup = skill_pickup
                    if Net.is_host() then
                        skill_drone_pick_message_create(self.value, skill_pickup):send_to_all()
                    end
                else
                    self.cache_skill_pickup = -4
                end
            end
            local skill_pickup = self.cache_skill_pickup
            if Instance.exists(skill_pickup) then
                if gm.bool(self.is_local) and gm.point_distance(self.x, self.y, skill_pickup.x, skill_pickup.y) <=
                    PICKUPRANGE then
                    gm.call("gml_Script_interactable_set_active", skill_pickup.value, self.value, skill_pickup.value,
                        self.value, 1)
                else
                    self.x = Utils.lerp(self.x, skill_pickup.x, self.chase_motion_lerp * 0.075)
                    self.y = Utils.lerp(self.y, skill_pickup.y, self.chase_motion_lerp * 0.075)
                    self.chase_motion_lerp = math.min(1.0, self.chase_motion_lerp + 0.4)
                end
            else
                local lerp_factor = (1 - self.chase_motion_lerp) * 0.1111111111111111
                self.x = Utils.lerp(self.x, master.ghost_x + self.xx, lerp_factor)
                self.y = Utils.lerp(self.y, master.ghost_y + self.yy - 40 - DRONEOFFSET, lerp_factor) + self.yo
                self.chase_motion_lerp = math.max(self.chase_motion_lerp - 0.4, 0)
                self.image_xscale = master.image_xscale
            end
        elseif self.state == 1 then
            local target = self.target
            if Instance.exists(target) then
                local target_parent = target.parent
                self.x = Utils.lerp(self.x,
                    Utils.lerp(
                        Utils.clamp(self.master.x + self.xx, target_parent.bbox_left - self.x_range_min - RANGEOFFSET,
                            target_parent.bbox_right + self.x_range_min + RANGEOFFSET), self.master.x + self.xx, 0.1),
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
    gm.post_script_hook(gm.constants.actor_skill_set, function(self, other, result, args)
        local inst_wrapped = Instance.wrap(args[1].value)
        local object_index = inst_wrapped:get_object_index_self()
        if object_index ~= oSkillDrone.value then
            return
        end
        local slot_index = args[2].value
        local skill_id = args[3].value
        inst_wrapped.x_range_min = get_x_range_min(inst_wrapped.value)
        local name = "star_draw" .. Utils.to_string_with_floor(slot_index)
        if skill_id == 0 then
            inst_wrapped:remove_callback(name)
            return
        end

        local angle = slot_index * math.pi / 2
        local radius = 24
        local default_skill = Class.SKILL:get(skill_id)
        local sprite_index = default_skill:get(4)
        local image_index = default_skill:get(5)
        local cooldown = default_skill:get(6)
        local angular_speed = 1 / math.log(cooldown) * 0.05
        local required_stock = default_skill:get(11)
        inst_wrapped:remove_callback(name)
        local skill = inst_wrapped:get_active_skill(slot_index)
        inst_wrapped:add_callback("onPostDraw", name, function(actor)
            angle = angle + angular_speed
            local x = actor.x + radius * math.cos(angle)
            local y = actor.y + radius * math.sin(angle) + DRONEOFFSET
            if skill.stock < required_stock then
                gm.draw_sprite_ext(sprite_index, image_index, x - 5, y - 5, SKILLSCALE, SKILLSCALE, 0.0, Color.GRAY, 1)
            else
                gm.draw_sprite_ext(sprite_index, image_index, x - 5, y - 5, SKILLSCALE, SKILLSCALE, 0.0, Color.WHITE, 1)
            end
        end)
    end)

    SkillPickup.add_skill_diff("has_been_drone_pickup", function(result, skill)
        result.has_been_drone_pickup = skill.has_been_drone_pickup
    end)

    SkillPickup.add_pre_local_drop_func(function(inst, skill)
        if inst:get_object_index_self() ~= oSkillDrone.value then
            return
        end
        skill.has_been_drone_pickup = 1
    end)

    oSkillDroneItem.obj_sprite = moon
    oSkillDroneItem:onCreate(function(self)
        self:interactable_init(true)
        self.active = 0
        self.value.value = 60
        self.image_speed = 0
        self.interact_scroll_index = 3
        self.child = oSkillDrone.value
        self:interactable_init_cost(self.value, 0, 40)
        self:interactable_init_name()
        local callstack = Array.wrap(gm.debug_get_callstack())
        for i = 0, callstack:size() - 1 do
            if string.find(callstack:get(i), "mapobject_spawn") then
                local slot_index = Utils.get_random(0, 3)
                local skill_id = get_drone_random_skill_id()
                Instance_ext.add_callback(self.value, "pre_destroy", "spawn_with_skill", function(actor)
                    gm.actor_skill_set(actor.spawned_drone, slot_index, skill_id)
                    skill_drone_skill_message_create(actor.spawned_drone, slot_index, skill_id):send_to_all()
                end)
                break
            end
        end
    end)

    -- Create Interactable Card
    local card = Interactable_Card.new("hinyb", "oSkillDroneItem")
    card.object_id = oSkillDroneItem.value
    card.spawn_with_sacrifice = true
    card.spawn_cost = 80
    card.spawn_weight = 6
    card.default_spawn_rarity_override = 1

    -- Add Interactable Card to stages
    local stages = Stage.find_all()
    for _, stage in ipairs(stages) do
        stage:add_interactable(card)
    end
end
Initialize(init)
memory.dynamic_hook_mid("pInteractableDrone_add_spawned_drone", {"rax", "[rbp+80h+10h]"}, {"RValue*", "CInstance*"}, 0,
    gm.get_object_function_address("gml_Object_pInteractableDrone_Step_2"):add(1007), function(args)
        args[2].spawned_drone = args[1].value
    end)
