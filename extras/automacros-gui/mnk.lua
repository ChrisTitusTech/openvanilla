-- AutoLua monk: one pull at a time, navigate back to an explicitly set camp.
local mq = require('mq')
local shared = require('automacros.shared')
local M = {events={}, binds={pullon='bind_pullon', pulloff='bind_pulloff',
    pullstatus='bind_pullstatus', pullradius='bind_pullradius'}, chat={}}

local settings = {
    {'acverbose','int',0}, {'UseMelee','int',1}, {'ReturnToCamp','int',0},
    {'AutoCampRadius','int',30}, {'AutoAssistAt','int',100},
    {'FollowToonName','string','NULL'}, {'UseFellowship','int',0},
    {'InstantRelease','int',0}, {'AutoPull','int',0},
    {'PullRadius','int',350}, {'PullZRadius','int',90},
    {'PullMaxPath','int',1000}, {'PullTimeout','int',15},
    {'PullMinHP','int',80}, {'PullMinEndurance','int',50},
    {'PullMinHealerMana','int',50}, {'PullName','string','NULL'},
}
local function read(expr) return mq.parse('${'..expr..'}') end
local function num(expr) return tonumber(read(expr)) or 0 end
local function yes(expr) return read(expr)=='TRUE' end
local function cfg(r,key) return r:get({},key) end
local function clamp(v,low,high) return math.max(low,math.min(high,v)) end
local function command(r,line) r:command({},line) end
local function now() return mq.gettime() end
local function state(r)
    if not r.monk then r.monk={phase='idle',status='Set camp here first',rejected={},nextPull=0} end
    return r.monk
end
local function status(r,s,message)
    if s.status~=message then s.status=message;r:log('Monk: '..message) end
end
local function position(base)
    local x,y,z=tonumber(read(base..'.X')),tonumber(read(base..'.Y')),tonumber(read(base..'.Z'))
    if x and y and z then return {x=x,y=y,z=z} end
end
local function distance(a,b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2+(a.z-b.z)^2)
end
local function horizontalDistance(a,b)
    if not a or not b then return math.huge end
    return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2)
end
local function spawn(id) return 'Spawn[id '..id..']' end
local function npc(id)
    if not id or id<=0 then return false end
    local e=spawn(id)
    return num(e..'.ID')==id and read(e..'.Type')=='NPC' and yes(e..'.Targetable') and not yes(e..'.Dead')
end
local function followName(r)
    local name=cfg(r,'FollowToonName') or ''
    if name=='' or name:lower()=='null' or name:lower()=='nullnullnullnullnull' then return nil end
    return name
end
local function stopNav(r,s)
    if s.navOwned then
        -- A completed path no longer needs stopping. Allow cancellation of
        -- a just-requested path that has not appeared in Navigation.Active.
        if yes('Navigation.Active') or now()-(s.navStarted or now())<1000 then
            command(r,'/nav stop')
        end
        s.navOwned=false
    end
end
-- Keep the plugin disabled for the entire monk session. Remember the
-- original runtime setting once, without changing the plugin's INI.
local function suspendMelee(r,s)
    if not yes('Plugin[MQ2Melee].IsLoaded') then return end
    local enabled=read('Melee.Enable')
    if enabled~='TRUE' and enabled~='FALSE' then return end
    if s.meleeWasEnabled==nil then s.meleeWasEnabled=enabled=='TRUE' end
    if enabled=='TRUE' then
        -- Disabling the plugin alone does not release an existing stick or
        -- attack state. Clear only an engagement the plugin already owns.
        if yes('Melee.Combat') then command(r,'/melee reset') end
        command(r,'/melee off')
        r:log('Monk: MQ2Melee disabled while AutoLua is running')
    end
end
local function resumeMelee(r,s)
    if s.meleeWasEnabled and yes('Plugin[MQ2Melee].IsLoaded') and not yes('Melee.Enable') then
        command(r,'/melee on')
        r:log('Monk: previous MQ2Melee state restored')
    end
    s.meleeWasEnabled=nil
end
local function stopCombat(r,s)
    if s.attackOwned then command(r,'/squelch /attack off') end
    if s.stickOwned then command(r,'/stick off') end
    s.attackOwned=nil;s.stickOwned=nil;s.combatId=nil;s.nextAttack=nil;s.nextStick=nil
end
local function reset(r,s,message)
    stopNav(r,s);stopCombat(r,s)
    s.phase='idle';s.pullId=nil;s.pullName=nil;s.nextPull=now()+1000
    s.action=nil;s.engageDeadline=nil;s.approachLimit=nil;s.navApproachRange=nil;s.waitMobId=nil;s.pausedAt=nil
    if message then status(r,s,message) end
end
local function invalidateCamp(r,s,message)
    reset(r,s,message);s.camp=nil;s.rejected={}
    if cfg(r,'ReturnToCamp')==1 then
        r:set({},'ReturnToCamp',0);r:set({},'changetoini',1)
    end
end
local function rememberCamp(r,s)
    local p=position('Me')
    local zone=num('Zone.ID')
    if not p or zone<=0 then
        invalidateCamp(r,s,'Cannot set camp: position unavailable')
        return
    end
    reset(r,s)
    p.zone=zone;s.camp=p;s.rejected={}
    if yes('AdvPath.Following') then command(r,'/afollow off') end
    r:set({},'FollowToonName','NULL')
    r:set({},'ChaseAssist',0)
    status(r,s,string.format('Camp set at %.1f, %.1f, %.1f',p.y,p.x,p.z))
end
local function campDistance(s) return distance(position('Me'),s.camp) end
local function campCommand(s)
    return string.format('loc %.3f %.3f %.3f',s.camp.y,s.camp.x,s.camp.z)
end
local function pathExists(dest) return yes('Navigation.MeshLoaded') and yes('Navigation.PathExists['..dest..']') end
local function startNav(r,s,dest,range)
    if yes('Navigation.Active') and not s.navOwned then
        status(r,s,'Waiting for manual navigation to finish')
        return false
    end
    if not pathExists(dest) then return false end
    if yes('Me.Sitting') then command(r,'/stand') end
    command(r,'/nav '..dest..' distance='..range..(dest:sub(1,3)=='id ' and ' lineofsight=on' or ''))
    s.navOwned=true;s.navStarted=now()
    return true
end
local function returnHome(r,s,reason,waitMobId)
    stopNav(r,s);stopCombat(r,s)
    s.phase='returning';s.nextNav=0;s.waitMobId=waitMobId;s.returnDeadline=now()+120000
    s.action=nil;s.engageDeadline=nil;s.approachLimit=nil;s.navApproachRange=nil
    status(r,s,'Returning to camp: '..reason)
end

local function hostiles()
    local list={}
    local slots=math.min(40,math.max(1,num('Me.XTargetSlots'),num('Me.XTarget')))
    local seen={}
    for i=1,slots do
        local e='Me.XTarget['..i..']'
        local id=num(e..'.ID')
        -- Like bard/warrior, consider every live NPC in occupied XTarget
        -- slots, not just Auto Hater roles or mobs with nonzero personal aggro.
        if not seen[id] and npc(id) then
            seen[id]=true;list[#list+1]=id
        end
    end
    return list
end
local function assistTarget()
    local id=num('Me.GroupAssistTarget.ID')
    local hp=num(spawn(id)..'.PctHPs')
    if npc(id) and hp>0 and hp<100 then return id end
end
local function groupReady(r)
    if num('Me.PctHPs')<cfg(r,'PullMinHP') then return false,'Waiting for monk health' end
    if num('Me.PctEndurance')<cfg(r,'PullMinEndurance') then return false,'Waiting for endurance' end
    local manaMin=cfg(r,'PullMinHealerMana')
    for i=1,math.min(5,num('Group.Members')) do
        local e='Group.Member['..i..']'
        if yes(e..'.Offline') or yes(e..'.OtherZone') or num(e..'.ID')<=0 then
            return false,'Waiting for group member to be present'
        end
        if num(e..'.PctHPs')<cfg(r,'PullMinHP') then return false,'Waiting for group health' end
        if yes(e..'.Aggressive') then return false,'Waiting for group combat to finish' end
        local class=read(e..'.Class.ShortName')
        if manaMin>0 and (class=='CLR' or class=='DRU' or class=='SHM') and num(e..'.PctMana')<manaMin then
            return false,'Waiting for healer mana'
        end
    end
    return true
end
local function pullMethod()
    local aa='Me.AltAbility[Distant Strike]'
    local aaReady='Me.AltAbilityReady[Distant Strike]'
    if yes(aaReady) then
        local id=num(aa..'.ID')
        local range=num(aa..'.Spell.MyRange')
        if range<=0 then range=num(aa..'.Spell.Range') end
        if id>0 and range>0 then
            return {name='Distant Strike',range=math.max(10,math.floor(range-8)),
                command='/alt act '..id,ready=aaReady,castTime=num(aa..'.Spell.MyCastTime.Raw')}
        end
    end
    local stoneReady='Me.CombatAbilityReady[Throw Stone]'
    if yes(stoneReady) then
        local range=num('Spell[Throw Stone].MyRange')
        if range<=0 then range=num('Spell[Throw Stone].Range') end
        if range>0 then
            return {name='Throw Stone',range=math.max(10,math.floor(range-5)),
                command='/doability "Throw Stone"',ready=stoneReady,castTime=num('Spell[Throw Stone].MyCastTime.Raw')}
        end
    end
end
local function canTag(id,method,limit)
    if not method or not npc(id) then return false end
    local dist=tonumber(read(spawn(id)..'.Distance3D'))
    return dist and dist>=0 and dist<=math.min(method.range,limit or method.range)
        and yes(spawn(id)..'.LineOfSight')
end
local function candidateReason(r,s,id)
    if not id or id<=0 then return 'missing spawn' end
    local e=spawn(id)
    if num(e..'.ID')~=id or read(e..'.Type')~='NPC' then return 'not NPC' end
    if not yes(e..'.Targetable') then return 'untargetable' end
    if yes(e..'.Dead') then return 'dead' end
    if num(e..'.Master.ID')>0 then return 'pet' end
    if read(e..'.CanEngage')=='FALSE' then return 'encounter locked' end
    local p=position(e)
    if not p then return 'unknown position' end
    if math.abs(p.z-s.camp.z)>cfg(r,'PullZRadius') then return 'vertical range' end
    if horizontalDistance(p,s.camp)>cfg(r,'PullRadius') then return 'camp range' end
    -- NPC HP is not always populated before targeting. Type/Dead, rather
    -- than an exact 100% HP reading, identify a living pull candidate.
    -- Unknown class (0) is possible; exclude known service classes.
    local class=num(e..'.Class.ID')
    if class>16 then return 'service class' end
    local filter=cfg(r,'PullName') or ''
    if filter~='' and filter:lower()~='null' and not tostring(read(e..'.CleanName') or ''):lower():find(filter:lower(),1,true) then
        return 'name filter'
    end
end
local function eligible(r,s,id) return candidateReason(r,s,id)==nil end
-- Enumerate loaded spawns directly, rather than depending on NearestSpawn's
-- 3D radius / ordering. Filter horizontal camp radius and Z independently.
local function scanIds(r,s)
    local radius=clamp(cfg(r,'PullRadius'),50,10000)
    local ids={}
    if type(mq.getFilteredSpawns)=='function' then
        local cx,cy=s.camp.x,s.camp.y
        local spawns=mq.getFilteredSpawns(function(sp)
            local id=sp.ID()
            if not id or id<=0 or sp.Type()~='NPC' then return false end
            local x,y=sp.X(),sp.Y()
            return x and y and (x-cx)^2+(y-cy)^2<=radius^2
        end)
        for _,sp in ipairs(spawns) do
            local id=sp.ID()
            if id and id>0 then ids[#ids+1]=id end
        end
    else
        -- Keep compatibility with previous MQ Lua versions.
        local searchRadius=math.ceil(math.sqrt(radius^2+cfg(r,'PullZRadius')^2)+campDistance(s))
        local search='npc radius '..searchRadius
        for i=1,num('SpawnCount['..search..']') do ids[#ids+1]=num('NearestSpawn['..i..','..search..'].ID') end
    end
    return ids,radius
end
local function selectTarget(r,s)
    local ids,radius=scanIds(r,s)
    local t=now();local rejected={};local samples={}
    local best,bestPath
    for _,id in ipairs(ids) do
        local reason=candidateReason(r,s,id)
        if not reason and (s.rejected[id] or 0)>t then reason='retry cooldown' end
        local path
        if not reason then
            path=num('Navigation.PathLength[id '..id..']')
            if path<=0 then reason='no nav path'
            elseif path>cfg(r,'PullMaxPath') then reason='path too long' end
        end
        if not reason then
            if not best or path<bestPath or (path==bestPath and id<best) then best,bestPath=id,path end
        else
            rejected[reason]=(rejected[reason] or 0)+1
            if #samples<6 and id>0 then
                samples[#samples+1]=string.format('%s (%d): %s',tostring(read(spawn(id)..'.CleanName')),id,reason)
            end
        end
    end
    if best then
        s.scanSummary=string.format('Found %d NPCs; selected ID %d (path %.0f)',#ids,best,bestPath)
        return best,bestPath
    end
    local counts={}
    for reason,n in pairs(rejected) do counts[#counts+1]=reason..'='..n end
    table.sort(counts)
    if #ids==0 then
        s.scanSummary='No NPCs within '..radius..' units of camp'
    else
        s.scanSummary='Found '..#ids..' NPCs; rejected: '..table.concat(counts,', ')
    end
    local detail=s.scanSummary..(#samples>0 and ' | '..table.concat(samples,'; ') or '')
    if s.lastScan~=detail or t>=(s.nextScanLog or 0) then
        r:log('Monk pull scan: '..detail)
        s.lastScan=detail;s.nextScanLog=t+10000
    end
end
local function reject(r,s,reason)
    if s.pullId then s.rejected[s.pullId]=now()+30000 end
    returnHome(r,s,reason)
end
local function setPullTarget(r,s,id,path)
    s.pullId=id;s.pullName=tostring(read(spawn(id)..'.CleanName'))
    s.pathLength=path;s.nextRescan=now()+5000;s.faceId=nil;s.navApproachRange=nil
    status(r,s,string.format('Pulling %s (ID %d, path %.0f)',s.pullName,id,path or 0))
end
local function requestTag(r,s,method,t)
    stopNav(r,s)
    -- Do not fire on a previous target or while navigation is still stopping.
    if num('Target.ID')~=s.pullId then
        command(r,'/squelch /target id '..s.pullId);status(r,s,'Targeting '..s.pullName);return
    end
    if not yes('Me.Standing') then command(r,'/stand');status(r,s,'Standing to pull');return end
    if yes('Navigation.Active') or yes('Me.Moving') then status(r,s,'Waiting for movement to stop before tagging');return end
    if num('Me.Casting.ID')>0 then status(r,s,'Waiting for current cast before tagging');return end
    if not yes(method.ready) then status(r,s,'Waiting for '..method.name..' readiness');return end
    if s.faceId~=s.pullId then command(r,'/face fast');s.faceId=s.pullId end
    local ping=math.max(0,num('EverQuest.Ping'))
    local confirmWindow=math.max(300,3*ping)
    s.engageDeadline=s.engageDeadline or (t+cfg(r,'PullTimeout')*1000)
    command(r,method.command)
    s.navApproachRange=nil
    s.action={name=method.name,ready=method.ready,requested=t,confirmed=false,
        confirmAt=t+method.castTime+confirmWindow}
    s.nextAction=t+math.max(500,method.castTime+confirmWindow)
    s.phase='awaitAggro'
    r:log(string.format('Monk pull request: %s target=%d distance=%.1f range=%d ready=TRUE command=%s',
        method.name,s.pullId,num(spawn(s.pullId)..'.Distance3D'),method.range,method.command))
    status(r,s,'Requested '..method.name..' on '..s.pullName..'; waiting for activation')
end
local function observeAction(r,s,t)
    local a=s.action
    if not a or a.confirmed then return end
    if read(a.ready)=='FALSE' or num('Me.Casting.ID')>0 then
        a.confirmed=true;a.aggroGrace=t+3000
        r:log('Monk pull activation confirmed: '..a.name..' target='..s.pullId)
        status(r,s,'Activated '..a.name..'; waiting for aggro')
    elseif t>=a.confirmAt and not a.reported then
        a.reported=true
        r:log('Monk pull activation not confirmed: '..a.name..' target='..s.pullId..' readiness='..tostring(read(a.ready)))
    end
end

-- Basic camp combat uses the same attack and stick primitives as the
-- bard/warrior. No independent discipline or AA rotation is added.
local function engageCombat(r,s,hostile,assist)
    if cfg(r,'UseMelee')~=1 or not s.camp or yes('Navigation.Active') then return end
    if not s.combatId and campDistance(s)>cfg(r,'AutoCampRadius') then return end
    local function valid(id)
        if not npc(id) then return false end
        local e=spawn(id)
        local hp=num(e..'.PctHPs')
        local threshold=cfg(r,'AutoAssistAt')
        return read(e..'.CanEngage')~='FALSE' and yes(e..'.LineOfSight') and
            ((hp>0 and hp<=threshold) or (hp==0 and threshold==100)) and
            distance(position(e),s.camp)<=cfg(r,'AutoCampRadius')
    end
    local id=s.combatId or (valid(assist) and assist or nil)
    local lowest=101
    if not id then
        for _,candidate in ipairs(hostile) do
            if valid(candidate) then
                local hp=num(spawn(candidate)..'.PctHPs')
                if hp==0 then hp=100 end
                if hp<lowest then id=candidate;lowest=hp end
            end
        end
    end
    if not id then
        local details={}
        for _,candidate in ipairs(hostile) do
            local e=spawn(candidate)
            details[#details+1]=string.format('%d hp=%d campdist=%.0f los=%s',candidate,
                num(e..'.PctHPs'),distance(position(e),s.camp),read(e..'.LineOfSight'))
            if #details>=5 then break end
        end
        r:logAction('monk-no-camp-target','Monk combat waiting: no eligible NPC inside camp (XTargets='..#hostile..') '..table.concat(details,'; '))
        return
    end
    if num('Target.ID')~=id then
        command(r,'/squelch /target id '..id)
        r:logAction('monk-target:'..id,'Monk combat target request id='..id)
        return true
    end
    if not yes('Me.Standing') then command(r,'/stand');return true end
    local t=now()
    s.combatId=id
    if not yes('Me.Combat') then
        if t>=(s.nextAttack or 0) then
            command(r,'/squelch /attack on')
            s.attackOwned=true;s.nextAttack=t+500
            r:log('Monk combat: attack target '..id)
        end
        return true
    end
    if not yes('Stick.Active') and yes('Plugin[MQ2MoveUtils].IsLoaded') and t>=(s.nextStick or 0) then
        local range=num('Target.MaxRangeTo')*0.8
        if range>0 then
            command(r,string.format('/stick %.1f moveback loose uw',range>29 and 25 or range))
            s.stickOwned=true;s.nextStick=t+500
        end
    end
    return true
end

local function maintainCombat(r,s,hostile,assist)
    if not s.combatId then return end
    local listed=s.combatId==assist
    for _,id in ipairs(hostile) do if id==s.combatId then listed=true;break end end
    if cfg(r,'UseMelee')~=1 or not listed or not npc(s.combatId) or num('Target.ID')~=s.combatId then
        stopCombat(r,s)
    end
end

function M.classvarsetup(r)
    for _,f in ipairs(settings) do r:call('loadini','General',f[1],f[2],tostring(f[3])) end
    -- A persisted toggle cannot safely restore an old coordinate in a new zone.
    r:set({},'ReturnToCamp',0)
    state(r)
end
function M.setupspells(r)
    suspendMelee(r,state(r))
    if not yes('Plugin[MQ2Nav].IsLoaded') then command(r,'/plugin MQ2Nav load noauto') end
end
function M.inichanges(r)
    r:set({},'changetoini',0)
    for _,f in ipairs(settings) do r:call('setini','General',f[1],f[2],tostring(cfg(r,f[1]))) end
end
function M.classaliassetup(r)
    -- Unlike the old toggle alias, repeated camphere always re-anchors camp.
    r.aliases.camphere='/togglevariable ReturnToCamp 1'
end
function M.bind_togglevariable(r,key,value,...)
    local s=state(r);local k=tostring(key):lower()
    if k=='usemelee' then
        -- Toggle only AutoLua's basic combat; MQ2Melee stays disabled.
        local v=tostring(value or ''):lower()
        local enabled
        if v=='1' or v=='on' then enabled=1
        elseif v=='0' or v=='off' then enabled=0
        elseif v=='' or v=='null' then enabled=cfg(r,'UseMelee')==1 and 0 or 1
        else return end
        r:set({},'UseMelee',enabled);r:set({},'changetoini',1)
        if enabled==0 then stopCombat(r,s) end
        print('[AutoLua] Auto melee: '..(enabled==1 and 'On' or 'Off'))
        return
    end
    shared.bind_togglevariable(r,key,value,...)
    if k=='returntocamp' then
        if cfg(r,'ReturnToCamp')==1 then rememberCamp(r,s)
        else invalidateCamp(r,s,'Camp disabled') end
    elseif k=='autopull' and cfg(r,'AutoPull')~=1 then
        if s.camp and (s.phase=='outbound' or s.phase=='awaitAggro') then
            returnHome(r,s,'Auto pull disabled')
        end
    end
end
function M.bind_pullon(r) M.bind_togglevariable(r,'AutoPull','1') end
function M.bind_pulloff(r) M.bind_togglevariable(r,'AutoPull','0') end
function M.bind_pullradius(r,value)
    local n=tonumber(value)
    if n and n==math.floor(n) and n>=50 and n<=10000 then
        r:set({},'PullRadius',n);r:set({},'changetoini',1)
        print('[AutoLua] Pull radius '..n)
    else print('[AutoLua] Pull radius must be 50-10000') end
end
function M.bind_pullstatus(r) print('[AutoLua] Monk: '..state(r).status) end
function M.bind_backoff(r)
    r:set({},'AutoPull',0);r:set({},'UseMelee',0);r:set({},'changetoini',1)
    local s=state(r);reset(r,s,'Back off: auto pull and auto melee disabled')
end
function M.event_zoned(r,line)
    local s=state(r)
    if s.camp and (tostring(line):find('LOADING, PLEASE WAIT',1,true) or
        s.camp.zone~=num('Zone.ID') or yes('Me.Zoning')) then
        invalidateCamp(r,s,'Zone changed; set a new camp')
    end
end
function M.onstop(r)
    local s=state(r)
    reset(r,s,'Stopped');resumeMelee(r,s)
    if cfg(r,'changetoini')==1 then M.inichanges(r) end
end

function M.classmainloop(r)
    local s=state(r);local t=now()
    suspendMelee(r,s)
    if yes('Me.Zoning') or (s.camp and s.camp.zone~=num('Zone.ID')) or yes('Me.Hovering') then
        invalidateCamp(r,s,'Zone or respawn changed; set a new camp')
        return
    end
    if cfg(r,'ReturnToCamp')~=1 and s.camp then invalidateCamp(r,s,'Camp disabled') end
    if yes('Me.Invis') or read('Me.State')=='FEIGN' then
        stopNav(r,s);stopCombat(r,s)
        s.pausedAt=s.pausedAt or t
        status(r,s,'Paused: invisible or feigned (pull state retained)')
        return
    end
    if s.pausedAt then
        local elapsed=t-s.pausedAt
        -- Keep the original camp and pull, without counting time spent feigned.
        for _,key in ipairs({'deadline','engageDeadline','returnDeadline','waitMobDeadline','waitMobGrace'}) do
            if s[key] then s[key]=s[key]+elapsed end
        end
        s.pausedAt=nil;s.nextNav=0
    end
    if followName(r) then
        if s.camp then invalidateCamp(r,s,'Following; camp disabled') end
        if not yes('Me.Combat') and #hostiles()==0 and num('Spawn[pc '..followName(r)..'].ID')>0 then r:call('followtoon') end
        return
    end
    local hostile=hostiles()
    local assist=assistTarget()
    maintainCombat(r,s,hostile,assist)
    local engaged=#hostile>0 or read('Me.CombatState')=='COMBAT' or yes('Me.Combat')
    if not s.camp then
        status(r,s,'Set camp here first')
        return
    end
    if cfg(r,'AutoPull')~=1 and (s.phase=='outbound' or s.phase=='awaitAggro') then
        returnHome(r,s,'Auto pull disabled')
    end
    if s.phase=='returning' then
        if campDistance(s)<=math.min(12,cfg(r,'AutoCampRadius')) then
            stopNav(r,s);s.nextPull=t+1500
            local waitId=s.waitMobId
            if npc(waitId) and distance(position(spawn(waitId)),s.camp)>cfg(r,'AutoCampRadius') then
                s.phase='waitingMob';s.waitMobDeadline=t+120000;s.waitMobGrace=t+3000
                status(r,s,'Back at camp; waiting for '..tostring(read(spawn(waitId)..'.CleanName')))
            else
                s.phase='idle';s.pullId=nil;s.pullName=nil;s.waitMobId=nil
                status(r,s,'Back at camp')
            end
        elseif t>=(s.returnDeadline or math.huge) then
            invalidateCamp(r,s,'Return to camp timed out; set camp again')
        elseif t>=(s.nextNav or 0) and (not s.navOwned or (not yes('Navigation.Active') and t-(s.navStarted or 0)>1000)) then
            stopNav(r,s);s.nextNav=t+2000
            if not startNav(r,s,campCommand(s),8) then status(r,s,'Waiting for a navigable path back to camp') end
        end
        return
    end
    if s.phase=='waitingMob' then
        local id=s.waitMobId
        if engageCombat(r,s,hostile,assist) or not npc(id) or distance(position(spawn(id)),s.camp)<=cfg(r,'AutoCampRadius') or
           t>=s.waitMobDeadline or (not engaged and t>=s.waitMobGrace) then
            s.phase='idle';s.pullId=nil;s.pullName=nil;s.waitMobId=nil;s.nextPull=t+1500
            status(r,s,'Mob arrival wait complete')
        end
        return
    end
    if s.phase=='outbound' then
        if engaged then returnHome(r,s,'Aggro acquired on approach',hostile[1] or s.pullId);return end
        if assist then returnHome(r,s,'Group already fighting');return end
        local ready,reason=groupReady(r)
        if not ready then returnHome(r,s,reason);return end
        if not eligible(r,s,s.pullId) or t>=s.deadline or (s.engageDeadline and t>=s.engageDeadline) then
            reject(r,s,'Pull target unavailable, unreachable or timed out');return
        end
        if s.navOwned and yes('Navigation.Active') and not s.engageDeadline and t>=(s.nextRescan or 0) then
            s.nextRescan=t+5000
            local id,path=selectTarget(r,s)
            local current=num('Navigation.PathLength[id '..s.pullId..']')
            if id and id~=s.pullId and (current<=0 or path+5<current) then
                stopNav(r,s);setPullTarget(r,s,id,path)
                return
            end
        end
        local method=pullMethod()
        if canTag(s.pullId,method,s.approachLimit) then
            requestTag(r,s,method,t)
        elseif not s.navOwned or (not yes('Navigation.Active') and t-(s.navStarted or 0)>1000) then
            if not method then status(r,s,'Waiting for pull ability');return end
            if yes('Navigation.Active') and not s.navOwned then status(r,s,'Waiting for navigation to stop');return end
            local range=math.min(method.range,s.approachLimit or method.range)
            if s.navOwned then
                -- MQ2Nav can report arrival at a mesh-projected destination
                -- even though the actual NPC does not satisfy our tag range
                -- or line-of-sight checks. Don't repeat that same path.
                s.navOwned=false
                local previous=s.navApproachRange or range
                r:log(string.format('Monk pull approach ended before tag: id=%d nav_range=%d distance=%.1f los=%s',
                    s.pullId,previous,num(spawn(s.pullId)..'.Distance3D'),read(spawn(s.pullId)..'.LineOfSight')))
                if previous<=10 then
                    reject(r,s,'Navigation ended without a valid tag position');return
                end
                range=math.min(range,math.max(10,math.floor(previous/2)))
                status(r,s,'Approaching closer after early navigation arrival: '..range..' units')
            elseif s.navApproachRange then
                -- Preserve a tighter approach after a manual pause.
                range=math.min(range,s.navApproachRange)
            end
            s.navApproachRange=range
            if not startNav(r,s,'id '..s.pullId,range) then reject(r,s,'No path to pull target') end
        end
        return
    end
    if s.phase=='awaitAggro' then
        observeAction(r,s,t)
        if num('Me.Casting.ID')>0 and t<s.engageDeadline then return end
        if engaged then
            returnHome(r,s,'Aggro confirmed',hostile[1] or s.pullId);return
        end
        if t>=s.engageDeadline or not eligible(r,s,s.pullId) then
            reject(r,s,'Pull not confirmed before timeout');return
        end
        local ready,reason=groupReady(r)
        if not ready then returnHome(r,s,reason);return end
        if assist then returnHome(r,s,'Group already fighting');return end
        if t<(s.nextAction or 0) or (s.action and s.action.aggroGrace and t<s.action.aggroGrace) then return end
        local method=pullMethod()
        if not method then return end
        if not canTag(s.pullId,method) or (s.action and s.action.reported and not s.approachLimit and
            num(spawn(s.pullId)..'.Distance3D')>math.max(10,math.floor(method.range/2))) then
            s.approachLimit=math.max(10,math.floor(method.range/2))
            s.phase='outbound'
            status(r,s,'Repositioning closer for '..method.name)
        else
            requestTag(r,s,method,t)
        end
        return
    end
    local busyMovement=yes('Navigation.Active') or yes('MoveTo.Moving') or yes('Stick.Active') or yes('Me.Combat')
    if engaged or assist then s.nextPull=t+1500 end
    if s.combatId then
        status(r,s,'Fighting extended target')
        engageCombat(r,s,hostile,assist)
        return
    end
    if campDistance(s)>cfg(r,'AutoCampRadius') then
        if busyMovement then
            status(r,s,'Waiting for movement or attack to finish');return
        end
        returnHome(r,s,'Outside camp radius');return
    end
    if engaged or assist then
        status(r,s,'Fighting extended target')
        engageCombat(r,s,hostile,assist)
        return
    end
    if cfg(r,'AutoPull')~=1 then status(r,s,'Camp active; auto pull off');return end
    if not yes('Navigation.MeshLoaded') then status(r,s,'Waiting for MQ2Nav zone mesh');return end
    if busyMovement then status(r,s,'Waiting for manual movement or attack to finish');return end
    if t<s.nextPull then return end
    if num('Me.Casting.ID')>0 then return end
    local ready,reason=groupReady(r)
    if not ready then status(r,s,reason);s.nextPull=t+1000;return end
    local method=pullMethod()
    if not method then status(r,s,'Waiting for Distant Strike or Throw Stone');s.nextPull=t+1000;return end
    local id,path=selectTarget(r,s)
    if not id then status(r,s,s.scanSummary or 'No eligible reachable NPC in pull radius');s.nextPull=t+1000;return end
    s.phase='outbound';s.deadline=t+45000
    s.action=nil;s.engageDeadline=nil;s.approachLimit=nil;s.waitMobId=nil
    setPullTarget(r,s,id,path)
end

function M.main(r)
    suspendMelee(r,state(r))
    command(r,'/doevents flush')
    r:call('autoversioncheck','9')
    r:call('varsetup');r:call('classvarsetup');r:call('aliassetup');r:call('classaliassetup');r:call('setupspells')
    while r.running do
        r:pump()
        if cfg(r,'changetoini')==1 then r:call('inichanges') end
        r:call('classmainloop')
        if yes('Me.Hovering') then r:call('deathsub') end
        mq.delay(100)
    end
end
return M
