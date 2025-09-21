_addon.name = 'conquestbuy'
_addon.author = 'MrSent'
_addon.version = '1.0.0.4'
_addon.command = 'cb'

require('tables')
require('logger')
packets = require('packets')
db = require('map')
--res_items = require('resources').items

valid_conquest_zones = T{
    -- Bastok NPC's
    [234] = {npc="Crying Wind, I.M.",   menu = 32761, item_name = "axe"}, -- Bastok Mines
    [235] = {npc="Rabid Wolf, I.M.",    menu = 32761, item_name = "Gun"}, -- Bastok Markets
    [236] = {npc="Flying Axe, I.M.",    menu = 32761, item_name = "Gun"}, -- Port Bastok
    -- Windy NPC's
    [241] = {npc="Harara, W.W.",        menu = 32759, item_name = "scythe"}, -- Windurst Woods
    [240] = {npc="Milma-Hapilma, W.W.", menu = 32759, item_name = "scythe"}, -- Port Windurst
    [238] = {npc="Puroiko-Maiko, W.W.", menu = 32759, item_name = "scythe"}, -- Windurst Waters
    -- Sandy NPC's
    [231] = {npc="Achantere, T.K.",     menu = 32762, item_name = "Halberd"}, -- Northern San d'Oria
    [230] = {npc="Aravoge, T.K.",       menu = 32763, item_name = "Halberd"}, -- Southern San d'Oria
    --[230] = {npc="Arpevion, T.K.",      menu = 32763, item_name = "Halberd"}, -- Southern San d'Oria (Note:cant have both npc's in the same zone)
}

item = ''
current_cp = 0
purchase_queue = T{}
col = {}

windower.register_event('load', function()
    --not used yet
end)

windower.register_event('addon command', function (command, ...)
    command = command and command:lower()
    local args = T{...}
    local zone = windower.ffxi.get_info()['zone']
    item = valid_conquest_zones[zone].item_name
    
    if command == 'buy' then
        notice('Buying 1 '..item..'.')
        purchase_queue[1] = build_item(item)
        return
    end

    if command == 'buyall' then
        col = build_item(item)
        local purchasable = math.floor(current_cp/col.Cost)
        
        if purchasable <= 0 then
            notice('You do not have enough conqest points.')
            return
        end
        
        if col then 
            local free_space = count_inv()
            local tobuy = 0
            
            if purchasable > free_space then
                tobuy = free_space
                notice("You have "..tobuy.." free slots, buying "..item.. " until full.")
            else
                notice('Spending '..current_cp..' conquest points to purchase: '..purchasable..' '..item..'s.')
                tobuy = purchasable
            end
            
            for i=1,tobuy do
                table.append(purchase_queue, col)
            end
        end
        return
    end
    
    if command == 'find' then
        table.vprint(build_item(item))
        return
    end
    
    if command == 'test' then
        table.vprint(col)
        table.vprint(purchase_queue)
    end
    
    if command == 'fail' then
        exit_cb()
    end
end)

windower.register_event('incoming chunk',function(id,data,modified,injected,blocked)
    if id == 0x034 or id == 0x032 then
        current_cp = data:unpack('I', 0x20+1)
        if purchase_queue and #purchase_queue > 0 then
            determine_interaction(purchase_queue[1])
            return true
        end
    end
end)

windower.register_event('prerender', function()
    if table.length(purchase_queue) > 0 then
        send_timer = os.clock() - local_timer
        if send_timer >= 4 then
            notice('Timed out.')
            exit_cb()
            local_timer = os.clock()
            return
        end
        if send_timer >= 1.6 then
            purchase_item(purchase_queue[1])
            local_timer = os.clock()
        end
    else
        local_timer = os.clock()
    end
end)

function determine_interaction(obj)
    local index = purchase_queue:find(obj)
    
    if #purchase_queue == 1 then
        notice('Buying Finished.')
    end
    
    if index then
        table.remove(purchase_queue, index)
    end
    
    conquest_packet(obj)
end

function count_inv()
    local playerinv = windower.ffxi.get_items().inventory
    return playerinv.max - playerinv.count
end

function purchase_item(obj)
    local zone = windower.ffxi.get_info()['zone']
    local distance = windower.ffxi.get_mob_by_id(obj.Target).distance:sqrt()
    
    if distance > 6 then
        warning('Too far from NPC, cancelling.')
        purchase_queue = T{}
        return
    end
    
    if valid_conquest_zones[zone] and obj['enl'] then
        notice("Buying "..obj['enl']..'.')
    else
        if #purchase_queue % 5 == 0 then
            notice('Buying #'..#purchase_queue..'.')
        end
    end
    poke_npc(obj['Target'],obj['Target Index'])
end

function build_item(item)
    local zone = windower.ffxi.get_info()['zone']
    local target_index,target_id,distance
    local result = {}
    local distance = 50
    
    if valid_conquest_zones[zone] then
        for i,v in pairs(get_marray()) do
            if v['name'] == windower.ffxi.get_player().name then
                result['me'] = v.id
            elseif v['name'] == valid_conquest_zones[zone].npc then
                target_index = v['index']
                target_id = v['id']
                npc_name = v['name']
                result['Menu ID'] = valid_conquest_zones[zone].menu
                distance = windower.ffxi.get_mob_by_id(target_id).distance
            end
        end

        if math.sqrt(distance)<6 then
            local iitem = fetch_db(item)
            if iitem then
                result['Target'] = target_id
                result['Option Index'] = iitem['Option']
                result['_unknown1'] = iitem['Index']
                result['Target Index'] = target_index
                result['Zone'] = zone
                result['Cost'] = iitem['Cost']
                result['enl'] = iitem['Name']:lower()
            end
        else
            warning("Too far from NPC.")
            return nil
        end
    else
        warning("Not in a zone with valid NPC.")
        return nil
    end
    if result['Zone'] == nil then result = nil end
    return result
end

function fetch_db(item)
    for i,v in pairs(db) do
        if string.lower(v.Name) == string.lower(item) then
            return v
        end
    end
end

function get_cb_update()
    local packet = packets.new('outgoing', 0x117, {["_unknown2"]=0})
    packets.inject(packet)
end

function poke_npc(npc,target_index)
    if npc and target_index then
        local packet = packets.new('outgoing', 0x01A, {
        ["Target"]=npc,
        ["Target Index"]=target_index,
        ["Category"]=0,
        ["Param"]=0,
        ["_unknown1"]=0})
        packets.inject(packet)
    end
end

function conquest_packet(obj)
    local zone = windower.ffxi.get_info().zone
    local menuid = 0
    if valid_conquest_zones[zone] then
        menuid = valid_conquest_zones[zone].menu
    end

    if valid_conquest_zones[zone] then
        local packet = packets.new('outgoing', 0x05B)
        packet["Target"] = obj['Target']
        packet["Option Index"] = obj["Option Index"]
        packet["_unknown1"] = obj["_unknown1"]
        packet["Target Index"] = obj["Target Index"]
        packet["Automated Message"] = true
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menuid
        packets.inject(packet)
        
        local packet = packets.new('outgoing', 0x05B)
        packet["Target"] = obj['Target']
        packet["Option Index"] = obj["Option Index"]
        packet["_unknown1"] = 0
        packet["Target Index"] = obj["Target Index"]
        packet["Automated Message"] = false
        packet["_unknown2"] = 0
        packet["Zone"] = zone
        packet["Menu ID"] = menuid
        packets.inject(packet)
    end
    
    local packet = packets.new('outgoing', 0x016, {["Target Index"]=obj['me'],})
    packets.inject(packet)
end

function exit_cb()
    local zone = windower.ffxi.get_info()['zone']
    local menuid = valid_conquest_zones[zone].menu
    local me = 0
    local target_index = 0
    local target_id = 0
    if valid_conquest_zones[zone] then
        for i,v in pairs(get_marray()) do
            if v['name'] == valid_conquest_zones[zone].npc then
                target_index = v['index']
                target_id = v['id']
            elseif v['name'] == windower.ffxi.get_player().name then
                me = v['index']
            end
        end
    end

    local packet = packets.new('outgoing', 0x05B)
    packet["Target"] = target_id
    packet["Option Index"]=0
    packet["_unknown1"]=16384
    packet["Target Index"]=target_index
    packet["Automated Message"]=false
    packet["_unknown2"]=0
    packet["Zone"]=zone
    packet["Menu ID"]=menuid
    packets.inject(packet)

    local packet = packets.new('outgoing', 0x016, {["Target Index"]=me,})
    packets.inject(packet)
end

function get_marray(--[[optional]]name)
    local marray = windower.ffxi.get_mob_array()
    local target_name = name or nil
    local new_marray = T{}
    
    for i,v in pairs(marray) do
        if v.id == 0 or v.index == 0 then
            marray[i] = nil
        end
    end
    
    -- If passed a target name, strip those that do not match
    if target_name then
        for i,v in pairs(marray) do
            if v.name ~= target_name then
                marray[i] = nil
            end
        end
    end
    
    for i,v in pairs(marray) do 
        new_marray[#new_marray + 1] = windower.ffxi.get_mob_by_index(i)
    end
    return new_marray
end
