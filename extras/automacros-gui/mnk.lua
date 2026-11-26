-- AutoLua monk: one pull at a time, navigate back to an explicitly set camp.
local mq = require('mq')
local shared = require('automacros.shared')
local Obs = require('automacros.observer')
local M = {events={}, binds={pullon='bind_pullon', pulloff='bind_pulloff',
    pullstatus='bind_pullstatus', pullradius='bind_pullradius',namedstatus='bind_namedstatus'}, chat={}}

local settings = {
    {'acverbose','int',0}, {'UseMelee','int',1}, {'ReturnToCamp','int',0},
    {'AutoCampRadius','int',30}, {'AutoAssistAt','int',100},
    {'FollowToonName','string','NULL'}, {'UseFellowship','int',0},
    {'InstantRelease','int',0}, {'AutoPull','int',0},
    {'PullRadius','int',350}, {'PullZRadius','int',90},
    {'PullMaxPath','int',1000}, {'PullTimeout','int',15},
    {'PullMinHP','int',80}, {'PullMinEndurance','int',50},
    {'PullMinHealerMana','int',50}, {'PullMinTankEndurance','int',30}, {'PullName','string','NULL'},
    {'PullExcludeName','string','NULL'},
    {'PullRequireNamedDefense','int',1},
    {'MonkUseAbilities','int',1}, {'MonkAutoFD','int',1}, {'MonkEmergencyFDHP','int',50},
}
local function read(expr) return mq.parse('${'..expr..'}') end
local function num(expr) return tonumber(read(expr)) or 0 end
local function yes(expr) return read(expr)=='TRUE' end
local function sitting() return yes('Me.Sitting') or read('Me.State')=='SIT' end
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
-- Some damage traps are exposed by the client as targetable NPCs.
local function trap(id)
    return tostring(read(spawn(id)..'.CleanName') or ''):lower():find('%f[%a]trap%f[%A]')~=nil
end
local function feigning() return yes('Me.Feigning') or read('Me.State')=='FEIGN' end
local function stunned() return yes('Me.Stunned') or read('Me.State')=='STUN' end
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
    s.action=nil;s.engageDeadline=nil;s.approachLimit=nil;s.navApproachRange=nil;s.waitMobId=nil;s.pausedAt=nil;s.feign=nil;s.restOwned=nil;s.nextRestCommand=nil
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
function M.applycampanchor(r,y,x,z,zone)
    local s=state(r)
    reset(r,s)
    s.camp={x=x,y=y,z=z,zone=zone};s.rejected={}
    status(r,s,string.format('Camp set at %.3f, %.3f, %.3f',y,x,z))
end
local function campDistance(s) return distance(position('Me'),s.camp) end
-- NPCs can stop a few units beyond the camp boundary when the tank catches
-- them. A small combat-only margin avoids leaving the tank fighting alone.
local function combatCampRadius(r) return cfg(r,'AutoCampRadius')+20 end
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
    if sitting() then command(r,'/stand') end
    command(r,'/nav '..dest..' distance='..range..(dest:sub(1,3)=='id ' and ' lineofsight=on' or ''))
    s.navOwned=true;s.navStarted=now()
    return true
end
local function returnHome(r,s,reason,waitMobId)
    stopNav(r,s);stopCombat(r,s)
    s.phase='returning';s.nextNav=0;s.waitMobId=waitMobId;s.returnDeadline=now()+120000
    s.returnPos=position('Me');s.returnProgressAt=now()
    s.action=nil;s.engageDeadline=nil;s.approachLimit=nil;s.navApproachRange=nil
    status(r,s,'Returning to camp: '..reason)
end

local function hostiles()
    local list,hate={},{byId={},max=0}
    local count=num('Me.XTarget')
    local slots=math.min(40,math.max(1,num('Me.XTargetSlots'),count))
    local seen,occupied={},0
    for i=1,slots do
        local e='Me.XTarget['..i..']'
        local id=num(e..'.ID')
        if id>0 then occupied=occupied+1 end
        -- Sparse slots and non-Auto-Hater roles are valid encounter NPCs.
        if not seen[id] and npc(id) and not trap(id) then
            seen[id]=true;list[#list+1]=id
            local pct=num(e..'.PctAggro')
            if pct>=0 and pct<=100 then hate.byId[id]=pct end
        end
        if count>0 and occupied>=count then break end
    end
    return list,hate
end
local function assistTarget()
    local id=num('Me.GroupAssistTarget.ID')
    local hp=num(spawn(id)..'.PctHPs')
    if npc(id) and not trap(id) and hp>0 and hp<100 then return id end
end
local function aggroSnapshot(hate,assist)
    local target,me=num('Target.ID'),num('Me.ID')
    if target>0 and (hate.byId[target]~=nil or target==assist) then
        local pct=num('Me.PctAggro')
        if pct>=0 and pct<=100 then
            hate.byId[target]=math.max(hate.byId[target] or 0,pct)
        end
        local victim=num('Me.TargetOfTarget.ID')
        if victim>0 and me>0 then
            -- The actual target of our current NPC is more direct than
            -- a stale 100% aggro meter following a taunt or feign.
            if victim==me then hate.byId[target]=100
            elseif hate.byId[target]==100 then hate.byId[target]=99 end
        end
    end
    for id,pct in pairs(hate.byId) do
        hate.max=math.max(hate.max,pct)
        if pct>=100 then hate.top=true end
    end
    return hate
end
local function groupTank()
    local assigned=num('Group.MainTank.ID')
    local me=num('Me.ID')
    local fallback
    for i=1,math.min(5,num('Group.Members')) do
        local e='Group.Member['..i..']'
        local id=num(e..'.ID')
        if id>0 and id~=me and not yes(e..'.Offline') and not yes(e..'.OtherZone') and not yes(e..'.Hovering') and
            read(e..'.Type')~='Corpse' and num(e..'.PctHPs')>0 then
            local class=read(e..'.Class.ShortName')
            local dist=tonumber(read(e..'.Distance')) or distance(position(spawn(id)),position('Me'))
            if dist<=100 and (id==assigned or class=='WAR' or class=='PAL' or class=='SHD') then
                local tank={id=id,hp=num(e..'.PctHPs'),endu=tonumber(read(e..'.PctEndurance')),
                    fighting=yes(e..'.Aggressive') or yes(spawn(id)..'.Aggressive')}
                if id==assigned then return tank end
                fallback=fallback or tank
            end
        end
    end
    return fallback
end
local function hasGroupTank()
    if num('Group.MainTank.ID')>0 then return true end
    for i=1,math.min(5,num('Group.Members')) do
        local class=read('Group.Member['..i..'].Class.ShortName')
        if class=='WAR' or class=='PAL' or class=='SHD' then return true end
    end
    return false
end
local function livingGroupTank()
    local assigned=num('Group.MainTank.ID')
    for i=1,math.min(5,num('Group.Members')) do
        local e='Group.Member['..i..']';local class=read(e..'.Class.ShortName')
        local id=num(e..'.ID')
        if id>0 and (id==assigned or class=='WAR' or class=='PAL' or class=='SHD') and
            num(e..'.PctHPs')>0 and not yes(e..'.Hovering') and read(e..'.Type')~='Corpse' and
            not yes(e..'.Offline') and not yes(e..'.OtherZone') then return true end
    end
    return false
end
local function combatTargetInCamp(r,s,id)
    local p=position(spawn(id))
    local d=distance(p,s.camp)
    if d<=combatCampRadius(r) then return true end
    -- The warrior may have intercepted an add farther out. Assist a damaged
    -- extended target near the living tank, but never chase distant roamers.
    if d>cfg(r,'AutoCampRadius')+50 or num(spawn(id)..'.PctHPs')>=100 then return false end
    local tank=groupTank()
    return tank and distance(p,position(spawn(tank.id)))<=35 or false
end
local function groupReady(r)
    if num('Me.PctHPs')<cfg(r,'PullMinHP') then return false,'Waiting for monk health' end
    local endu=num('Me.PctEndurance')
    if endu<cfg(r,'PullMinEndurance') then
        return false,string.format('Waiting for endurance (%d%% / %d%% required)',endu,cfg(r,'PullMinEndurance'))
    end
    local manaMin=cfg(r,'PullMinHealerMana')
    local tankEndMin=cfg(r,'PullMinTankEndurance')
    for i=1,math.min(5,num('Group.Members')) do
        local e='Group.Member['..i..']'
        if yes(e..'.Mercenary') and num(e..'.ID')<=0 then
            return false,'Waiting for group mercenary revival'
        end
        if yes(e..'.Offline') or yes(e..'.OtherZone') or num(e..'.ID')<=0 then
            return false,'Waiting for group member to be present'
        end
        if num(e..'.PctHPs')<cfg(r,'PullMinHP') then return false,'Waiting for group health' end
        if yes(e..'.Aggressive') then return false,'Waiting for group combat to finish' end
        local class=read(e..'.Class.ShortName')
        if tankEndMin>0 and (class=='WAR' or class=='PAL' or class=='SHD') then
            local tankEnd=tonumber(read(e..'.PctEndurance'))
            if tankEnd and tankEnd>=0 and tankEnd<tankEndMin then
                return false,string.format('Waiting for tank endurance (%d%% / %d%% required)',tankEnd,tankEndMin)
            end
        end
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
    if trap(id) then return 'trap' end
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
    local name=tostring(read(e..'.CleanName') or ''):lower()
    if filter~='' and filter:lower()~='null' and not name:find(filter:lower(),1,true) then
        return 'name filter'
    end
    local excluded=cfg(r,'PullExcludeName') or ''
    if excluded~='' and excluded:lower()~='null' and name:find(excluded:lower(),1,true) then
        return 'excluded name'
    end
end
local function eligible(r,s,id) return candidateReason(r,s,id)==nil end
function M.namedPullReady(r,id,diagnostic)
    if not diagnostic and (cfg(r,'PullRequireNamedDefense')~=1 or not yes(spawn(id)..'.Named')) then return true end
    local roles={WAR={key='namedWarDefense',query=Obs.warDefenseQuery,label='warrior sustained defense'},
        CLR={key='namedClrDefense',query=Obs.clrDefenseQuery,label='cleric emergency heal'},
        BRD={key='namedBrdDefense',query=Obs.brdDefenseQuery,label='bard group support'}}
    local checked={}
    local waitReason
    for i=1,math.min(5,num('Group.Members')) do
        local e='Group.Member['..i..']';local class=read(e..'.Class.ShortName');local role=roles[class]
        if role and not checked[class] then
            checked[class]=true
            local memberId=num(e..'.ID');local name=read(e..'.Name')
            Obs.ensure(r,role.key,name,role.query,memberId)
            local payload=Obs.read(r,role.key)
            local ready=false
            if payload and class=='WAR' then
                -- Require the strongest learned sustained defense, not a
                -- weaker obsolete discipline on a separate ready timer.
                for j=3,#payload-2,2 do
                    if (tonumber(payload[j]) or 0)>0 then ready=payload[j+1]=='TRUE';break end
                end
            elseif payload then
                for j=3,#payload-1 do if payload[j]=='TRUE' then ready=true;break end end
            end
            if diagnostic then r:log('Named pull readiness class='..class..' member='..name..' ready='..tostring(ready)..' data='..(payload and table.concat(payload,'|') or 'unavailable')) end
            if not ready and not waitReason then
                waitReason='Waiting for named pull: '..role.label..(payload and ' cooldown' or ' readiness data')
            end
        end
    end
    return not waitReason,waitReason
end
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
        local ready,reason=M.namedPullReady(r,best)
        if not ready then
            s.scanSummary=reason..' ('..tostring(read(spawn(best)..'.CleanName'))..')'
            return nil
        end
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
    if stunned() then status(r,s,'Stunned; waiting before tagging');return end
    if not yes('Me.Standing') then command(r,'/stand');status(r,s,'Standing to pull');return end
    if yes('Navigation.Active') or yes('Me.Moving') then status(r,s,'Waiting for movement to stop before tagging');return end
    if s.abilityPending or num('Me.Casting.ID')>0 then status(r,s,'Waiting for current ability before tagging');return end
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

-- Highest learned discipline in each family. Order is newest to oldest,
-- not cooldown order. The client is authoritative for rank and ownership.
local discFamilies={
    aura={"Master's Aura","Disciple's Aura"},
    recovery={"Breather","Rest","Reprieve","Respite"},
    combatRecovery={"Hiatus V","Convalesce","Night's Calming","Relax","Hiatus"},
    wind={"Seventh Wind","Sixth Wind","Fifth Wind","Fourth Wind","Third Wind","Second Wind"},
    breaths={"Moment of Stillness","Breath of Stillness","Breath of Tranquility","Nine Breaths","Eight Breaths","Seven Breaths","Six Breaths","Five Breaths"},
    form={"Diametric Form","Reciprocal Form","Ecliptic Form","Composite Form","Dissident Form","Dichotomic Form"},
    drunken={"Drunken Monkey Style"},
    curse={"Curse of Eighteen Desires","Curse of Seventeen Facets","Curse of Sixteen Shadows","Curse of Fifteen Strikes","Curse of Fourteen Fists","Curse of the Thirteen Fingers"},
    fang={"Uncia's Fang","Zlexak's Fang","Hoshkar's Fang","Zalikor's Fang","Dragon Fang"},
    fists={"Wheel of Fists XII","Flurry of Fists","Buffeting of Fists","Barrage of Fists","Firestorm of Fists","Torrent of Fists","Eight-Step Pattern","Seven-Step Pattern","Six-Step Pattern","Whorl of Fists","Wheel of Fists","Clawstriker Flurry","Leopard Claw"},
    phantom={"Phantom Fisticuffs","Phantom Pummeling","Phantom Partisan","Cloud of Fists"},
    precision={"Lifewalker's Precision Strike","Fatewalker's Precision Strike","Bloodwalker's Precision Strike","Icewalker's Precision Strike","Firewalker's Precision Strike","Doomwalker's Precision Strike"},
    shuriken={"Vigorous Shuriken"},
    synergy={"Lifewalker's Synergy","Fatewalker's Synergy","Bloodwalker's Synergy","Icewalker's Synergy","Firewalker's Synergy","Doomwalker's Synergy","Shadewalker's Synergy","Veilwalker's Synergy","Dreamwalker's Synergy","Calanin's Synergy"},
    storm={"Eye of the Storm"},
    wu={"Fists of Wu"},
    earth={"Earthforce Discipline","Earthwalk Discipline"},
    shade={"Shaded Step","Void Step"},
    death={"Delay Death XI","Defy Death","Repeal Death","Rescind Death","Reject Death","Refuse Death","Forestall Death","Decry Death","Deny Death","Defer Death","Delay Death"},
    dodge={"Veiled Body","Void Body"},
    iron={"Ironfist Discipline","Scaledfist Discipline","Ashenhand Discipline"},
    heel={"Heel of Zagali","Heel of Kojai","Heel of Kai","Rapid Kick Discipline","Heel of Kanji"},
    speed={"Speed Focus Discipline","Hundred Fists Discipline"},
    palm={"Terrorpalm Discipline","Diamondpalm Discipline","Crystalpalm Discipline","Innerflame Discipline"},
    stance={"Heron Stance","Crane Stance"},
    balance={"Eagle's Symmetry","Tiger's Symmetry","Dragon's Poise","Eagle's Poise","Tiger's Poise","Dragon's Balance"},
}
local aaNames={"Imitate Death","Purify Body","Zan Fi's Whistle","Two-Finger Wasp Touch","Five Point Palm",
    "Ton Po's Stance","Spire of the Sensei","Infusion of Thunder","Focused Destructive Force","Silent Strikes","Swift Tails' Chant"}
local skillNames={"Feign Death","Mend","Flying Kick","Round Kick","Kick","Tiger Claw","Eagle Strike","Dragon Punch","Tail Rake","Intimidation"}
local function present(value) return value and value~='' and value~='NULL' end
local function baseName(name) return (name:gsub(' Rk%. I+$','')) end
local function discoverAbilities(r,s)
    local learned,disc,aa,skill={},{},{},{}
    -- CombatAbility[n] returns the learned spell (whereas [name] returns
    -- its index). Enumerate once, not a full name/rank scan every pulse.
    for i=1,400 do
        local name=read('Me.CombatAbility['..i..'].Name')
        if present(name) then
            local base=baseName(name):lower()
            local rank=name:match(' Rk%. III$') and 3 or (name:match(' Rk%. II$') and 2 or 1)
            if not learned[base] or rank>learned[base].rank then learned[base]={name=name,rank=rank} end
        end
    end
    local summary,classified={},{}
    for family,names in pairs(discFamilies) do
        for _,base in ipairs(names) do
            local spell=learned[base:lower()]
            if spell then
                classified[base:lower()]=true
                if not disc[family] then
                    local name=spell.name
                    disc[family]={kind='disc',name=name,ready='Me.CombatAbilityReady['..name..']',
                        line=string.format('/doability %q',name),spell=name,
                        cost=num('Spell['..name..'].EnduranceCost'),
                        cast=num('Spell['..name..'].MyCastTime.Raw'),
                        trigger=read('Spell['..name..'].Trigger[1].Name')}
                    if family=='recovery' or family=='combatRecovery' then
                        -- The recovery line's third effect is its endurance
                        -- activation cap (Dantea's Breather III is 29%).
                        local cap=num('Spell['..name..'].Base[3]')
                        disc[family].enduCap=(cap>0 and cap<=100) and cap or 15
                    end
                    summary[#summary+1]=family..'='..name..(disc[family].enduCap and ' (endurance cap '..disc[family].enduCap..'%)' or '')
                end
            end
        end
    end
    for _,name in ipairs(aaNames) do
        local e='Me.AltAbility['..name..']'
        local id=num(e..'.ID')
        if id>0 then
            aa[name]={kind='aa',name=name,ready='Me.AltAbilityReady['..name..']',
                line='/alt act '..id,spell=read(e..'.Spell.Name'),cast=num(e..'.Spell.MyCastTime.Raw'),
                trigger=read(e..'.Spell.Trigger[1].Name')}
            summary[#summary+1]='AA='..name
        end
    end
    for _,name in ipairs(skillNames) do
        if num('Me.Skill['..name..']')>0 then
            skill[name]={kind='skill',name=name,ready='Me.AbilityReady['..name..']',
                line='/doability '..name,cast=0}
            summary[#summary+1]='skill='..name
        end
    end
    table.sort(summary)
    s.abilities={disc=disc,aa=aa,skill=skill};s.abilityRetry={};s.abilityPending=nil
    s.abilityLevel=num('Me.Level');s.nextAbilityScan=now()+300000
    r:log('Monk abilities resolved: '..(#summary>0 and table.concat(summary,'; ') or 'no classified abilities learned'))
    local unclassified={}
    for base,entry in pairs(learned) do
        if not classified[base] then unclassified[#unclassified+1]=entry.name end
    end
    if #unclassified>0 then
        table.sort(unclassified)
        r:log('Monk learned disciplines not auto-used: '..table.concat(unclassified,'; '))
    end
end
local function discActive()
    return num('Me.ActiveDisc.ID')>0 or present(read('Me.ActiveDisc.Name'))
end
local function buffActive(name)
    return present(name) and (num('Me.Buff['..name..'].ID')>0 or num('Me.Song['..name..'].ID')>0)
end
local function observeAbility(r,s,t)
    local p=s.abilityPending
    if not p then return end
    local a=p.ability
    if read(a.ready)=='FALSE' or (a.kind=='disc' and read('Me.ActiveDisc.Name')==a.name) or
       (a.cast>0 and num('Me.Casting.ID')>0) or (a.buff and (buffActive(a.spell) or buffActive(a.trigger))) then
        s.abilityPending=nil;s.lastAbility=a.name
        r:log('Monk ability confirmed: '..a.name)
    elseif t>=p.deadline then
        s.abilityPending=nil;s.abilityRetry[a.name]=t+3000
        r:log('Monk ability unconfirmed: '..a.name..'; retry deferred')
    end
end
local function useAbility(r,s,a,options)
    if not a or s.abilityPending or not yes(a.ready) or now()<(s.abilityRetry[a.name] or 0) then return false end
    options=options or {}
    if (a.cast or 0)>0 and (yes('Me.Moving') or options.instant) then return false end
    if a.cost and a.cost>0 and num('Me.CurrentEndurance')<a.cost then return false end
    if a.enduCap and num('Me.PctEndurance')>a.enduCap then return false end
    if options.slot and discActive() and not (options.defensive and read('Spell['..a.spell..'].StacksWithDiscs')=='TRUE') then return false end
    if options.buff and (buffActive(a.spell) or buffActive(a.trigger) or (present(a.spell) and read('Spell['..a.spell..'].Stacks')=='FALSE')) then return false end
    a.buff=options.buff
    command(r,a.line)
    local t=now()
    s.abilityPending={ability=a,deadline=t+math.max(1000,(a.cast or 0)+500)}
    s.abilityRetry[a.name]=t+500
    r:log('Monk ability request: '..a.name..' ('..a.kind..')')
    return true
end
-- Recovery and defensives can fire during an emergency return, but
-- only instant abilities are allowed while navigating.
local function selfProtection(r,s,mode)
    if cfg(r,'MonkUseAbilities')~=1 or not s.abilities or s.abilityPending or
       num('Me.Casting.ID')>0 or not yes('Me.Standing') or feigning() or yes('Me.Stunned') then return false end
    local kit=s.abilities
    local hp=num('Me.PctHPs')
    local moving=mode=='pull'
    local function use(a,options)
        options=options or {};options.instant=moving
        return useAbility(r,s,a,options)
    end
    if hp>0 and hp<=(moving and 75 or 70) and use(kit.skill.Mend) then return true end
    if kit.aa['Purify Body'] and yes(kit.aa['Purify Body'].ready) then
        local detrimental=num('Me.CountersDisease')+num('Me.CountersPoison')+num('Me.CountersCurse')+num('Me.CountersCorruption')>0
        if not detrimental then
            for _,effect in ipairs({'Dotted','Rooted','Snared','Slowed','Silenced'}) do
                if num('Me.'..effect..'.ID')>0 then detrimental=true;break end
            end
        end
        if detrimental and use(kit.aa['Purify Body']) then return true end
    end
    if mode=='pull' or mode=='combat' or mode=='recovery' then
        if hp>0 and hp<=35 and use(kit.disc.death,{slot=true,defensive=true}) then return true end
        if hp>0 and hp<=65 then
            for _,key in ipairs({'earth','shade','dodge'}) do
                if use(kit.disc[key],{slot=true,defensive=true}) then return true end
            end
        end
    end
    return false
end
-- An automatic feign is owned by the macro. Never stand a player who
-- manually feigned or resume attacking before the hate has dropped.
local function requestFeign(r,s,mode,reason)
    if cfg(r,'MonkAutoFD')~=1 or not s.abilities or now()<(s.nextFeign or 0) or
       feigning() or yes('Me.Stunned') or not yes('Me.Standing') then return false end
    s.fdRetry=s.fdRetry or {}
    local kit=s.abilities
    local function ready(a)
        return a and yes(a.ready) and now()>=(s.fdRetry[a.name] or 0)
    end
    local aa=kit.aa['Imitate Death']
    local skill=kit.skill['Feign Death']
    local a=ready(aa) and aa or (ready(skill) and skill)
    if not a then
        r:logAction('monk-fd-unavailable','Monk aggro dump unavailable: '..reason)
        return false
    end
    if num('Me.Casting.ID')>0 then
        -- Actual top hate or critical HP takes priority over a cast;
        -- even a previously observed cast may still be in progress.
        command(r,'/stopcast');s.abilityPending=nil
        s.nextFeign=now()+250
        return true
    end
    local wasInvis=yes('Me.Invis')
    local ownedAttack,ownedStick=s.attackOwned,s.stickOwned
    stopNav(r,s);stopCombat(r,s)
    -- Native attack can still be on if the player initiated it manually.
    if not ownedAttack and yes('Me.Combat') then command(r,'/squelch /attack off') end
    if not ownedStick and yes('Stick.Active') then command(r,'/stick off') end
    s.abilityPending=nil
    command(r,a.line)
    local t=now()
    s.feign={mode=mode,stage='requested',name=a.name,deadline=t+math.max(750,(a.cast or 0)+500,3*num('EverQuest.Ping')),wasInvis=wasInvis}
    status(r,s,'Aggro dump: '..a.name..' ('..reason..')')
    r:log('Monk FD request: '..a.name..' mode='..mode..' hp='..num('Me.PctHPs')..' reason='..reason)
    return true
end
local function finishFeign(r,s,p)
    s.feign=nil;s.nextFeign=now()+1500;s.nextPull=now()+1500;s.pausedAt=nil
    if p.mode=='pull' then
        if s.pullId then s.rejected[s.pullId]=now()+30000 end
        returnHome(r,s,'Recovering from emergency feign')
    else
        s.phase='idle';s.pullId=nil;s.pullName=nil;s.waitMobId=nil
        status(r,s,'Aggro dumped; resuming camp combat')
    end
    r:log('Monk FD recovery complete: '..p.name..' mode='..p.mode)
end
local function handleFeign(r,s,hostile,hate)
    local p=s.feign
    if not p then return false end
    local t=now()
    if p.stage=='requested' then
        if feigning() then
            p.stage='down';p.downAt=t
            status(r,s,'Feign confirmed; waiting for aggro to clear')
            r:log('Monk FD confirmed: '..p.name)
        elseif t>=p.deadline then
            s.fdRetry[p.name]=t+5000;s.feign=nil;s.nextNav=0
            r:log('Monk FD unconfirmed: '..p.name..'; will try alternate if ready')
            if p.name=='Imitate Death' and not p.wasInvis and yes('Me.Invis') then command(r,'/makemevisible') end
        end
        return true
    end
    if p.stage=='down' then
        if not feigning() then p.stage='standing';p.nextStand=0
        else
            local hp=num('Me.PctHPs')
            local healthy=hp>=math.max(60,cfg(r,'MonkEmergencyFDHP')+10)
            local tank=groupTank()
            local noTank=p.mode=='camp' and hasGroupTank() and not tank
            if noTank then p.waitTankRecovery=true end
            local recoveringTank=p.mode=='camp' and p.waitTankRecovery and tank and
                (tank.hp<70 or (tank.endu and tank.endu>=0 and tank.endu<20))
            if noTank or recoveringTank then status(r,s,'Feigning until the group tank is alive and recovered') end
            if t-p.downAt<1000 or hate.top or hate.max>=80 or not healthy or noTank or recoveringTank or (p.mode=='pull' and p.abortAdds and #hostile>0) then
                r:logAction('monk-fd-wait','Monk FD waiting: hp='..hp..' aggro='..hate.max..' hostile='..#hostile)
                return true
            end
            command(r,'/stand');p.stage='standing';p.nextStand=t+1000
            return true
        end
    end
    if feigning() then
        if t>=(p.nextStand or 0) then command(r,'/stand');p.nextStand=t+1000 end
        return true
    end
    -- Imitate Death supplies its own temporary invisibility. Remove only
    -- invisibility created by this automated escape, not a manual buff.
    if p.name=='Imitate Death' and not p.wasInvis and yes('Me.Invis') then
        if t>=(p.nextVisible or 0) then command(r,'/makemevisible');p.nextVisible=t+1000 end
        return true
    end
    finishFeign(r,s,p)
    return true
end
-- One nonblocking ability request at a time. Offensive abilities are
-- restricted to confirmed camp fights, not the pulling state machine.
local function abilityTick(r,s,mode,hostile)
    if cfg(r,'MonkUseAbilities')~=1 or cfg(r,'UseMelee')~=1 or not s.abilities or
       s.abilityPending or num('Me.Casting.ID')>0 or yes('Navigation.Active') or
       not yes('Me.Standing') or yes('Me.Invis') or feigning() or stunned() then return false end
    if selfProtection(r,s,mode) then return true end
    local kit=s.abilities
    local hp,endu=num('Me.PctHPs'),num('Me.PctEndurance')
    local function d(key,options) return useAbility(r,s,kit.disc[key],options) end
    local function aa(name,options) return useAbility(r,s,kit.aa[name],options) end
    local function skill(name) return useAbility(r,s,kit.skill[name]) end
    local slot={slot=true};local buff={buff=true}
    if mode=='idle' then
        if endu<cfg(r,'PullMinEndurance') then
            -- Let a regeneration buff work instead of chaining recovery
            -- discs, especially the 12-second Breaths cast.
            local regenActive=false
            for _,key in ipairs({'combatRecovery','recovery','wind'}) do
                local a=kit.disc[key]
                if a and (not a.enduCap or endu<a.enduCap) and (buffActive(a.spell) or buffActive(a.trigger)) then regenActive=true;break end
            end
            if not regenActive and (d('combatRecovery',buff) or d('recovery',buff) or
               aa("Swift Tails' Chant",buff) or d('wind',buff) or (endu<=25 and d('breaths'))) then return true end
            return false -- sit before spending time on incidental aura refreshes
        end
        if not present(read('Me.Aura[1].Name')) and d('aura') then return true end
        return false
    end
    if mode~='combat' then return false end
    if endu<=25 and (d('combatRecovery',buff) or aa("Swift Tails' Chant",buff) or d('wind',buff)) then return true end
    local e=spawn(s.combatId)
    local range=num('Target.MaxRangeTo')
    local dist=tonumber(read(e..'.Distance3D'))
    if range<=0 or not dist or dist>range*0.95 or not yes(e..'.LineOfSight') then return false end
    local targetHP=num(e..'.PctHPs')
    -- Shed hate before spending more endurance or starting damage burns.
    if math.max(s.maxAggro or 0,num('Me.PctAggro'))>=80 and aa('Silent Strikes',buff) then return true end
    -- Count only live encounter NPCs physically inside the anchored camp.
    -- Extended targets still on the way or elsewhere in the zone are not adds.
    local burn=yes(e..'.Named')
    if not burn then
        local inCamp,includesTarget=0,false
        for _,id in ipairs(hostile) do
            if id==s.combatId then includesTarget=true end
            if combatTargetInCamp(r,s,id) then
                inCamp=inCamp+1
            end
        end
        -- A group-assist target may be engaged before it appears on our XTarget.
        if not includesTarget and combatTargetInCamp(r,s,s.combatId) then
            inCamp=inCamp+1
        end
        burn=inCamp>=3
    end
    if aa("Zan Fi's Whistle",buff) or d('drunken',buff) or d('wu',buff) then return true end
    if burn and hp>65 and (targetHP==0 or targetHP>20) then
        if d('form') or (endu>=70 and aa("Ton Po's Stance",buff)) or
           d('heel',slot) or d('speed',slot) or d('iron',slot) or d('palm',slot) or
           aa('Spire of the Sensei',buff) or aa('Infusion of Thunder',buff) or
           d('stance') or d('balance') or (endu<85 and aa("Swift Tails' Chant",buff)) then return true end
        -- Single-target version only, and only with Speed Focus. Do not
        -- break mez or pull extra nearby mobs with Destructive Force.
        if kit.disc.speed and read('Me.ActiveDisc.Name')==kit.disc.speed.name and aa('Focused Destructive Force',buff) then return true end
    end
    if hp>65 and d('storm',slot) then return true end
    if d('synergy') or (targetHP>25 and (d('curse') or aa('Two-Finger Wasp Touch'))) or
       d('fists') or d('phantom') or d('fang') or d('precision') or d('shuriken') or
       (hp>=80 and targetHP>20 and aa('Five Point Palm')) then return true end
    if num('Me.AltAbility[Intimidation].Rank')>1 and skill('Intimidation') then return true end
    return skill('Flying Kick') or skill('Round Kick') or skill('Kick') or
        (endu<25 and skill('Eagle Strike')) or skill('Tiger Claw') or skill('Dragon Punch') or skill('Tail Rake')
end

-- Basic camp combat uses the same attack and stick primitives as the
-- bard/warrior; trained monk abilities are scheduled after engagement.
local function engageCombat(r,s,hostile,assist)
    if cfg(r,'UseMelee')~=1 or not s.camp or yes('Navigation.Active') then return end
    if not s.combatId and campDistance(s)>cfg(r,'AutoCampRadius')+50 then return end
    local function valid(id)
        if not npc(id) or trap(id) then return false end
        local e=spawn(id)
        local hp=num(e..'.PctHPs')
        local threshold=cfg(r,'AutoAssistAt')
        return read(e..'.CanEngage')~='FALSE' and yes(e..'.LineOfSight') and
            ((hp>0 and hp<=threshold) or (hp==0 and threshold==100)) and
            combatTargetInCamp(r,s,id)
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
    if stunned() then return true end
    if not yes('Me.Standing') then command(r,'/stand');return true end
    local t=now()
    s.combatId=id
    local maxRange=num('Target.MaxRangeTo')
    local targetDistance=tonumber(read(spawn(id)..'.Distance3D'))
    local inRange=maxRange>0 and targetDistance and targetDistance<=maxRange*0.95 and yes(spawn(id)..'.LineOfSight')
    local function approach()
        if not yes('Stick.Active') and yes('Plugin[MQ2MoveUtils].IsLoaded') and t>=(s.nextStick or 0) then
            local range=maxRange*0.8
            if range>0 then
                command(r,string.format('/stick %.1f moveback loose uw',range>29 and 25 or range))
                s.stickOwned=true;s.nextStick=t+500
                return true
            end
        end
        return false
    end
    if not yes('Me.Combat') then
        -- Start movement before attack when the tank has caught a mob
        -- outside melee reach. Native attack otherwise immediately emits
        -- several out-of-range swings on every engagement.
        if not inRange then
            approach()
            r:logAction('monk-approach:'..id,'Monk combat closing to melee range id='..id..' distance='..tostring(targetDistance))
            return true
        end
        if t>=(s.nextAttack or 0) then
            command(r,'/squelch /attack on')
            s.attackOwned=true;s.nextAttack=t+500
            r:log('Monk combat: attack target '..id)
        end
        return true
    end
    if approach() then return true end
    abilityTick(r,s,'combat',hostile)
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
    local s=state(r)
    suspendMelee(r,s)
    discoverAbilities(r,s)
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
function M.bind_namedstatus(r)
    local ready,reason=M.namedPullReady(r,nil,true)
    local msg=ready and 'Named pull defense ready' or reason
    r:log(msg);print('[AutoLua] '..msg)
end
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
    observeAbility(r,s,t)
    if yes('Me.Zoning') or (s.camp and s.camp.zone~=num('Zone.ID')) or yes('Me.Hovering') then
        invalidateCamp(r,s,'Zone or respawn changed; set a new camp')
        return
    end
    if cfg(r,'ReturnToCamp')~=1 and s.camp then invalidateCamp(r,s,'Camp disabled') end
    local hostile,hate=hostiles()
    local assist=assistTarget()
    hate=aggroSnapshot(hate,assist);s.maxAggro=hate.max
    if handleFeign(r,s,hostile,hate) then return end
    if yes('Me.Invis') or feigning() then
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
        s.pausedAt=nil;s.nextNav=0;s.returnProgressAt=t;s.returnPos=position('Me')
    end
    if followName(r) then
        if s.camp then invalidateCamp(r,s,'Following; camp disabled') end
        if not yes('Me.Combat') and #hostile==0 and num('Spawn[pc '..followName(r)..'].ID')>0 then r:call('followtoon') end
        return
    end
    maintainCombat(r,s,hostile,assist)
    local engaged=#hostile>0 or read('Me.CombatState')=='COMBAT' or yes('Me.Combat')
    -- A dead owned mercenary retains a group slot with ID 0. Revive it
    -- when safely idle instead of blocking all subsequent pulls forever.
    if not engaged and not assist and read('Mercenary.State')=='DEAD' and
       not yes('Me.Moving') and not yes('Navigation.Active') and not yes('MoveTo.Moving') and
       num('Me.Casting.ID')==0 and t>=(s.nextMercRevive or 0) then
        s.nextMercRevive=t+15000
        command(r,'/notify MMGW_ManageWnd MMGW_SuspendButton LeftMouseUp')
        r:log('Monk: Requested revival of own dead mercenary')
        return
    end
    -- Stand on incoming aggro before any attempt to fight or feign.
    if (engaged or assist) and s.restOwned and sitting() then
        if t>=(s.nextRestCommand or 0) then
            command(r,'/stand');s.nextRestCommand=t+500
        end
        return
    end
    if s.restOwned and not sitting() and yes('Me.Standing') and t>=(s.nextRestCommand or 0) then s.restOwned=nil end
    if not s.camp then
        -- Out-of-combat recovery is useful after a death or before camp is
        -- established, too. Do not require an active pull or camp to sit.
        local endu=num('Me.PctEndurance')
        if not engaged and not assist and endu<cfg(r,'PullMinEndurance') and
           not yes('Me.Moving') and not yes('Navigation.Active') and not yes('MoveTo.Moving') and
           not yes('Stick.Active') and num('Me.Casting.ID')==0 and not s.abilityPending then
            status(r,s,string.format('Recovering endurance (%d%% / %d%%)',endu,cfg(r,'PullMinEndurance')))
            if read('Me.CombatState')~='DEBUFFED' and yes('Me.Standing') and t>=(s.nextRestCommand or 0) then
                command(r,'/sit');s.restOwned=true;s.nextRestCommand=t+500
            end
        else status(r,s,'Set camp here first') end
        return
    end
    local pullPhase=s.phase=='outbound' or s.phase=='awaitAggro' or s.phase=='returning'
    local hp=num('Me.PctHPs')
    local stuckReturn=false
    if s.phase=='returning' then
        local pos=position('Me')
        if not s.returnPos or distance(pos,s.returnPos)>3 then s.returnPos=pos;s.returnProgressAt=t end
        stuckReturn=s.navOwned and yes('Navigation.Active') and t-(s.returnProgressAt or t)>=3000
        if stuckReturn then
            r:logAction('monk-return-stuck','Monk return stalled: hp='..hp..' campdist='..string.format('%.0f',campDistance(s)))
        end
    end
    if hp>0 and hp<=75 and (engaged or pullPhase) then
        r:logAction('monk-survival','Monk survival: phase='..s.phase..' hp='..hp..' aggro='..hate.max..' hostiles='..#hostile)
    end
    local emergencyHP=cfg(r,'MonkEmergencyFDHP')
    if stuckReturn and engaged then emergencyHP=math.max(emergencyHP,65) end
    -- Abort a three-plus accidental pull away from camp rather than hand
    -- the whole pack to a tank expecting a single mob.
    if pullPhase and #hostile>=3 and campDistance(s)>combatCampRadius(r) then
        if requestFeign(r,s,'pull','accidental three-plus pull outside camp') then
            if s.feign then s.feign.abortAdds=true end
            return
        end
    end
    if not pullPhase and engaged and hasGroupTank() and not livingGroupTank() then
        stopCombat(r,s)
        if requestFeign(r,s,'camp','group tank unavailable') then return end
        selfProtection(r,s,'recovery');status(r,s,'Holding combat: group tank unavailable');return
    end
    if (engaged or pullPhase) and hp>0 and hp<=emergencyHP and (pullPhase or hate.top or hp<=30) then
        if requestFeign(r,s,pullPhase and 'pull' or 'camp',stuckReturn and 'stalled return under attack' or 'critical health') then return end
    end
    if pullPhase then
        -- Self-only instant actions may protect a returning puller without
        -- stopping its path. Routine aggro during a healthy pull is expected.
        selfProtection(r,s,'pull')
    elseif hate.top and (campDistance(s)<=cfg(r,'AutoCampRadius') or s.combatId) then
        local tank=groupTank()
        local threatInCamp=false
        for id,pct in pairs(hate.byId) do
            if pct>=100 and (id==s.combatId or combatTargetInCamp(r,s,id)) then
                threatInCamp=true;break
            end
        end
        if tank and threatInCamp then
            if (s.attackOwned or yes('Me.Combat') or tank.fighting) and requestFeign(r,s,'camp','monk has top aggro') then return end
            -- If the tank hasn't established hate yet, don't add DPS hate.
            if not s.combatId then
                selfProtection(r,s,'recovery')
                status(r,s,'Waiting for tank to take aggro')
                return
            end
            -- FD may be unavailable; stop offensive actions until the tank
            -- takes over, rather than continuing to generate more hate.
            stopCombat(r,s)
            selfProtection(r,s,'recovery')
            status(r,s,'Holding DPS while monk has aggro')
            return
        end
    end
    if cfg(r,'AutoPull')~=1 and (s.phase=='outbound' or s.phase=='awaitAggro') then
        returnHome(r,s,'Auto pull disabled')
    end
    if s.phase=='returning' then
        if campDistance(s)<=math.min(12,cfg(r,'AutoCampRadius')) then
            stopNav(r,s);s.nextPull=t+1500
            local waitId=s.waitMobId
            if npc(waitId) and (distance(position(spawn(waitId)),s.camp)>cfg(r,'AutoCampRadius') or (not engaged and not assist)) then
                s.phase='waitingMob';s.waitMobDeadline=t+120000
                -- Hate may temporarily disappear while an NPC paths around
                -- geometry. Budget travel time before declaring it lost.
                s.waitMobGrace=t+clamp(math.ceil((s.pathLength or 0)/15)*1000+8000,25000,45000)
                s.waitMobDistance=distance(position(spawn(waitId)),s.camp);s.waitMobProgressAt=t
                status(r,s,'Back at camp; waiting for '..tostring(read(spawn(waitId)..'.CleanName')))
            else
                s.phase='idle';s.pullId=nil;s.pullName=nil;s.waitMobId=nil
                status(r,s,'Back at camp')
            end
        elseif t>=(s.returnDeadline or math.huge) then
            invalidateCamp(r,s,'Return to camp timed out; set camp again')
        elseif stuckReturn and t-(s.returnProgressAt or t)>=5000 and not yes('Me.Stunned') and num('Me.Rooted.ID')==0 then
            stopNav(r,s);s.nextNav=0;s.returnProgressAt=t
            status(r,s,'Replanning stalled return to camp')
        elseif t>=(s.nextNav or 0) and (not s.navOwned or (not yes('Navigation.Active') and t-(s.navStarted or 0)>1000)) then
            stopNav(r,s);s.nextNav=t+2000
            if not startNav(r,s,campCommand(s),8) then status(r,s,'Waiting for a navigable path back to camp') end
        end
        return
    end
    if s.phase=='waitingMob' then
        local id=s.waitMobId
        local living=npc(id)
        local dist=living and distance(position(spawn(id)),s.camp) or math.huge
        local remote=living and dist>cfg(r,'AutoCampRadius')
        if living and dist<(s.waitMobDistance or math.huge)-5 then
            s.waitMobDistance=dist;s.waitMobProgressAt=t
        end
        local lost=living and not engaged and not assist and t>=s.waitMobGrace and
            t-(s.waitMobProgressAt or 0)>=5000
        if lost then
            -- Avoid immediately pulling the same mob over and over when
            -- it loses hate or leashes before reaching camp.
            s.rejected[id]=t+15000
            r:log('Monk incoming mob lost aggro: ID '..id..'; retry after 15 seconds')
        end
        if engageCombat(r,s,hostile,assist) or not living or (not remote and (engaged or assist)) or t>=s.waitMobDeadline or lost then
            s.phase='idle';s.pullId=nil;s.pullName=nil;s.waitMobId=nil;s.nextPull=t+1500
            status(r,s,lost and 'Mob lost aggro before arriving; temporarily skipping' or 'Mob arrival wait complete')
        elseif campDistance(s)<=cfg(r,'AutoCampRadius') then
            abilityTick(r,s,'recovery',hostile)
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
        local namedReady,namedReason=M.namedPullReady(r,s.pullId)
        if not namedReady then returnHome(r,s,namedReason);return end
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
        -- A nav route can continue to point-blank range if LOS is blocked.
        -- Refuse to enter a dense pack to tag a single target.
        if campDistance(s)>cfg(r,'AutoCampRadius') and num(spawn(s.pullId)..'.Distance3D')<=60 and
            num('SpawnCount[npc radius 45 zradius 25]')>=3 then
            reject(r,s,'Unsafe crowded pull approach');return
        end
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
        local me,actualTarget=num('Me.ID'),num('Target.ID')
        local pct=num('Me.PctAggro')
        local tagHate=actualTarget==s.pullId and ((pct>0 and pct<=100) or
            (me>0 and num('Me.TargetOfTarget.ID')==me))
        if #hostile>0 or tagHate then
            returnHome(r,s,'Aggro confirmed',hostile[1] or s.pullId);return
        end
        -- A damaging AA can flip CombatState before the mob is actually
        -- on our hate list. Keep waiting for concrete evidence.
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
    local busyMovement=yes('Navigation.Active') or yes('MoveTo.Moving') or yes('Stick.Active') or yes('Me.Combat') or yes('Me.Moving')
    if engaged or assist then s.nextPull=t+1500 end
    if s.combatId then
        status(r,s,'Fighting extended target')
        engageCombat(r,s,hostile,assist)
        return
    end
    if (engaged or assist) and engageCombat(r,s,hostile,assist) then
        status(r,s,'Fighting extended target')
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
        abilityTick(r,s,'recovery',hostile)
        return
    end
    if not busyMovement and num('Me.Casting.ID')==0 then
        if not s.abilityPending and (s.abilityLevel~=num('Me.Level') or t>=(s.nextAbilityScan or 0)) then
            discoverAbilities(r,s)
        end
        if s.abilityPending or abilityTick(r,s,'idle',hostile) then return end
    end
    -- Rest only when safely in camp and no cast, movement or encounter
    -- needs attention. Sitting permits fast out-of-combat regeneration.
    if not busyMovement and num('Me.Casting.ID')==0 and not s.abilityPending then
        local endu=num('Me.PctEndurance')
        local health=num('Me.PctHPs')
        local endGoal,hpGoal=cfg(r,'PullMinEndurance'),cfg(r,'PullMinHP')
        if endu<endGoal or (health>0 and health<hpGoal) then
            local message=endu<endGoal and string.format('Recovering endurance (%d%% / %d%%)',endu,endGoal)
                or string.format('Recovering health (%d%% / %d%%)',health,hpGoal)
            status(r,s,message)
            if read('Me.CombatState')~='DEBUFFED' and yes('Me.Standing') and t>=(s.nextRestCommand or 0) then
                command(r,'/sit');s.restOwned=true;s.nextRestCommand=t+500
            end
            return
        elseif cfg(r,'AutoPull')==1 and sitting() then
            if t>=(s.nextRestCommand or 0) then
                command(r,'/stand');s.nextRestCommand=t+500
                status(r,s,'Recovered; standing to pull')
            end
            return
        end
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
