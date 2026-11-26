-- AutoLua config window. ImGui callbacks only read state and enqueue changes;
-- commands and INI writes execute on the normal Lua runtime coroutine.
local mq = require('mq')
local G = {}
G.__index = G

local common = {
    {'UseMelee', 'Auto melee', 'toggle'},
    {'ReturnToCamp', 'Return to camp', 'toggle'},
    {'AutoCampRadius', 'Camp radius', 'number', 20, 100},
    {'AutoAssistAt', 'Assist at target HP (%)', 'number', 0, 100},
    {'UseFellowship', 'Use fellowship on death', 'toggle'},
    {'InstantRelease', 'Instant release on death', 'toggle'},
    {'acverbose', 'Verbose notifications', 'toggle'},
}
local classes = {
    war = {},
    mnk = {
        {'AutoPull', 'Auto pull', 'toggle'},
        {'PullRadius', 'Pull radius (units)', 'number', 50, 500},
        {'PullZRadius', 'Vertical pull radius (units)', 'number', 10, 100},
        {'PullMinHP', 'Minimum monk/group HP (%)', 'number', 50, 100},
        {'PullMinEndurance', 'Minimum endurance (%)', 'number', 0, 100},
        {'PullMinHealerMana', 'Minimum healer mana (%)', 'number', 0, 100},
        {'PullName', 'NPC name contains (NULL = any)', 'text'},
    },
    brd = {
        {'UseSlow', 'Slow', 'toggle'},
        {'UseMez', 'Mesmerize', 'toggle'},
        {'BringYourOwnSpells', 'Bring your own spells', 'toggle'},
    },
    clr = {
        {'AutoRez', 'Auto resurrection', 'toggle'},
        {'usepromheals', 'Promised heals', 'toggle'},
        {'DivineBuffOn', 'Divine buff', 'toggle'},
        {'usedruid', 'Use druid buffs', 'toggle'},
        {'BringYourOwnSpells', 'Bring your own spells', 'toggle'},
        {'NoCures', 'Disable cures / affected heals (session only)', 'toggle'},
        {'pethealpoint', 'Pet heal HP (%)', 'number', 0, 100},
        {'tbmhealpoint', 'TBM heal HP (%)', 'number', 0, 100},
        {'raidhealpoint', 'Raid heal HP (%)', 'number', 0, 100},
        {'Manatonuke', 'Nuke mana (%)', 'number', 20, 100},
        {'mountitem', 'Mount item', 'text'},
    },
}
local names = {war='Warrior', brd='Bard', clr='Cleric', mnk='Monk'}

function G.new(r, class)
    local self = setmetatable({r=r, class=class, open=true, ready=false, loaded=false,
        phase='Starting AutoLua', started=mq.gettime(),
        fields={}, drafts={}, message='Changes apply to this character only.'}, G)
    for _,group in ipairs({common, assert(classes[class])}) do
        for _,field in ipairs(group) do self.fields[field[1]]=field end
    end
    return self
end

function G:setPhase(phase)
    self.phase=phase
    self.r:log('Startup: '..phase..' ('..math.floor(mq.gettime()-self.started)..' ms)')
end

function G:queue(key, value)
    self.r:enqueue('@gui', key, value)
end

function G:apply(key, value)
    local r = self.r
    if not self.ready then return end
    local field = self.fields[key]
    if field then
        local old = r:get({},key)
        if old == nil then return end
        if field[3]=='toggle' then
            if type(value)~='boolean' then return end
            local wanted=value and 1 or 0
            if old==wanted then return end
            if key=='usepromheals' or key=='DivineBuffOn' then
                -- Preserve the legacy toggle's shared-gem allocation, including
                -- the case where the other spell is not memorized.
                local other=key=='usepromheals' and 'DivineBuff' or 'promheal'
                local gem=key=='usepromheals' and 'promgem' or 'divinegem'
                local slots=r:get({},'spellslots')
                local occupied=r:number({},'${Me.Gem[${'..other..'}]}')
                r:set({},gem,occupied==slots and slots-1 or slots)
                r:set({},key,wanted)
            elseif key=='NoCures' then
                r:set({},key,wanted)
            else
                r:call('bind_togglevariable',key,tostring(wanted))
            end
        elseif field[3]=='number' then
            if type(value)~='number' or value~=math.floor(value) or value<field[4] or value>field[5] then
                self.message='Invalid value for '..field[2]
                return
            end
            if key=='AutoCampRadius' then
                r:dispatch('campradius',tostring(value))
            else
                r:set({},key,value)
                if key=='AutoAssistAt' then
                    -- Loaded by all classes but omitted by legacy inichanges.
                    r:call('setini','General',key,'int',tostring(value))
                end
            end
        elseif field[3]=='text' then
            if key=='PullName' and value=='' then value='NULL' end
            -- Keep names literal through the existing MQ INI adapter.
            if type(value)~='string' or #value>200 or not value:match('^[%w %p]+$')
                or value:find('["$;{}%[%],\\]') or not value:match('%S') then
                self.message='Enter a name without command or INI delimiters.'
                return
            end
            r:set({},key,value)
        end
        if key~='NoCures' and key~='AutoAssistAt' then
            r:set({},'changetoini',1)
        end
    elseif key=='campHere' then
        r:call('bind_togglevariable','ReturnToCamp','1')
    elseif key=='followTarget' then
        if not r:condition({},'${Target.Type.Equal[PC]} && ${Target.ID} != ${Me.ID}') then
            self.message='Select another player before following.'
            return
        end
        local name=r:expand({},'${Target.Name}')
        if name=='' or name=='NULL' then
            self.message='Selected player is unavailable.'
            return
        end
        r:set({},'FollowToonName',name)
        r:set({},'changetoini',1)
    elseif key=='stopFollow' then
        r:dispatch('chaseoff')
        r:set({},'ChaseAssist',0)
    elseif key=='backoff' then
        r:dispatch('backoff')
    elseif key=='newTank' and self.class=='clr' then
        r:dispatch('newtank')
    elseif key=='quietTarget' and self.class=='clr' then
        local id=r:number({},'${Spawn[id ${Target.ID} group].ID}')
        if id<=0 then
            self.message='Select a group member for Quiet Miracle.'
            return
        end
        r:set({},'qmtarget',id)
        r:set({},'changetoini',1)
    elseif key=='clearQuietTarget' and self.class=='clr' then
        r:set({},'qmtarget',0)
        r:set({},'changetoini',1)
    elseif key=='stop' then
        if r:get({},'changetoini')==1 then r:call('inichanges') end
        r:dispatch('stop')
        return
    else
        return
    end
    if r:get({},'changetoini')==1 then r:call('inichanges') end
    self.message='Applied: '..(field and field[2] or key)
end

function G:drawField(imgui, field)
    local key,label,kind=field[1],field[2],field[3]
    local value=self.r:get({},key)
    if value==nil then return end
    if kind=='toggle' then
        local nextValue,changed=imgui.Checkbox(label,value~=0)
        if changed then self:queue(key,nextValue) end
        return
    end
    local draft=self.drafts[key]
    if not draft or draft.source~=value then
        draft={source=value,value=value}
        self.drafts[key]=draft
    end
    imgui.PushID(key)
    imgui.Text(label)
    imgui.SetNextItemWidth(-75)
    if kind=='number' then
        draft.value=imgui.SliderInt('##value',draft.value,field[4],field[5])
    else
        draft.value=imgui.InputText('##value',draft.value)
    end
    imgui.SameLine()
    if imgui.Button('Apply') then self:queue(key,draft.value) end
    imgui.PopID()
end

function G:draw(imgui)
    if not self.open then return end
    imgui.SetNextWindowSize(510,640,ImGuiCond.FirstUseEver)
    local visible
    self.open,visible=imgui.Begin('AutoLua - '..self.r.character..'###AutoLuaConfig',self.open)
    if visible then
        imgui.Text(names[self.class]..' | '..self.r.character)
        if not self.ready then
            imgui.TextWrapped(self.phase)
            imgui.Text(string.format('Starting for %.1f seconds', (mq.gettime()-self.started)/1000))
        end
        if self.loaded then
            if not self.ready then
                imgui.TextWrapped('Settings loaded. Controls will unlock after setup.')
                imgui.BeginDisabled()
            end
            imgui.TextWrapped(self.message)
            imgui.Separator()
            imgui.Text('General')
            for _,field in ipairs(common) do self:drawField(imgui,field) end
            local follow=self.r:get({},'FollowToonName') or 'NULL'
            if follow=='NULLNULLNULLNULLNULL' or follow=='NULL' then follow='None' end
            imgui.Separator()
            imgui.Text('Movement | Following: '..follow)
            if imgui.Button('Set camp here') then self:queue('campHere') end
            imgui.SameLine()
            if imgui.Button('Follow target') then self:queue('followTarget') end
            imgui.SameLine()
            if imgui.Button('Stop following') then self:queue('stopFollow') end
            if imgui.Button('Back off') then self:queue('backoff') end
            if self.class~='war' then
                imgui.Separator()
                imgui.Text(names[self.class]..' settings')
                for _,field in ipairs(classes[self.class]) do self:drawField(imgui,field) end
                if self.class=='mnk' then
                    imgui.TextWrapped(self.r.monk and self.r.monk.status or 'Set camp here first.')
                    imgui.TextWrapped('Set camp here, then enable Auto pull. MQ2Nav needs a loaded zone mesh.')
                else
                    imgui.TextWrapped('Bring your own spells applies to spell setup on restart.')
                end
                if self.class=='clr' then
                    imgui.Text('Quiet Miracle target ID: '..tostring(self.r:get({},'qmtarget') or 0))
                    if imgui.Button('Set Quiet Miracle target') then self:queue('quietTarget') end
                    imgui.SameLine()
                    if imgui.Button('Clear') then self:queue('clearQuietTarget') end
                    if imgui.Button('Refresh tank / use selected fallback') then self:queue('newTank') end
                end
            end
            imgui.Separator()
            if imgui.Button('Stop AutoLua') then self:queue('stop') end
            if not self.ready then imgui.EndDisabled() end
            imgui.SameLine()
            if imgui.Button('Hide') then self.open=false end
        end
    end
    imgui.End()
end

function G.attach(r,class)
    local gui=G.new(r,class)
    local imgui=require('ImGui')
    mq.imgui.init('AutoLuaConfig',function() gui:draw(imgui) end)
    return gui
end

return G
