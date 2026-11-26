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
    {'PullRadius','int',200}, {'PullZRadius','int',50},
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
    if s.navOwned then command(r,'/nav stop');s.navOwned=false end
end
local function reset(r,s,message)
    stopNav(r,s)
    s.phase='idle';s.pullId=nil;s.pullName=nil;s.handoffId=nil;s.nextPull=now()+1000
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
    command(r,'/nav '..dest..' distance='..range)
    s.navOwned=true;s.navStarted=now()
    return true
end
local function returnHome(r,s,reason)
    stopNav(r,s)
    s.phase='returning';s.nextNav=0
    status(r,s,'Returning to camp: '..reason)
end

local function hostiles()
    local list={}
    local count=num('Me.XTarget')
    if count<=0 and num('Me.XTarget[1].ID')<=0 then return list end
    local slots=math.min(40,math.max(1,num('Me.XTargetSlots'),count))
    local seen={}
    for i=1,slots do
        local e='Me.XTarget['..i..']'
        local id=num(e..'.ID')
        if id>0 and not seen[id] and read(e..'.Type')=='NPC' and
           (read(e..'.TargetType')=='Auto Hater' or num(e..'.PctAggro')>0) and npc(id) then
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
    if yes('Me.AltAbilityReady[Distant Strike]') then
        local range=num('Me.AltAbility[Distant Strike].Spell.Range')
        if range>0 then return {name='Distant Strike',range=math.max(10,math.floor(range-8)),command='/aa act Distant Strike'} end
    end
    if yes('Me.CombatAbilityReady[Throw Stone]') then
        local range=num('Spell[Throw Stone].Range')
        if range>0 then return {name='Throw Stone',range=math.max(10,math.floor(range-5)),command='/doability "Throw Stone"'} end
    end
end
local function canTag(id,method)
    return method and npc(id) and num(spawn(id)..'.Distance3D')<=method.range and yes(spawn(id)..'.LineOfSight')
end
local function candidateReason(r,s,id)
    if not id or id<=0 then return 'missing spawn' end
    local e=spawn(id)
    if num(e..'.ID')~=id or read(e..'.Type')~='NPC' then return 'not NPC' end
    if not yes(e..'.Targetable') then return 'untargetable' end
    if yes(e..'.Dead') then return 'dead' end
    if num(e..'.Master.ID')>0 then return 'pet' end
    local p=position(e)
    if not p then return 'unknown position' end
    if math.abs(p.z-s.camp.z)>cfg(r,'PullZRadius') then return 'vertical range' end
    if distance(p,s.camp)>cfg(r,'PullRadius') then return 'camp range' end
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
local function selectTarget(r,s,method)
    local radius=clamp(cfg(r,'PullRadius'),50,500)
    -- Search from the monk, then enforce the actual camp-centered limit.
    local searchRadius=math.ceil(radius+campDistance(s))
    local search='npc radius '..searchRadius
    local count=num('SpawnCount['..search..']')
    local t=now();local rejected={};local samples={}
    for i=1,count do
        local id=num('NearestSpawn['..i..','..search..'].ID')
        local reason=candidateReason(r,s,id)
        if not reason and (s.rejected[id] or 0)>t then reason='retry cooldown' end
        if not reason and not canTag(id,method) and not pathExists('id '..id) then reason='no nav path' end
        if not reason then
            s.scanSummary=string.format('Found %d NPCs; selected ID %d',count,id)
            return id
        end
        rejected[reason]=(rejected[reason] or 0)+1
        if #samples<6 and id>0 then
            samples[#samples+1]=string.format('%s (%d): %s',tostring(read(spawn(id)..'.CleanName')),id,reason)
        end
    end
    local counts={}
    for reason,n in pairs(rejected) do counts[#counts+1]=reason..'='..n end
    table.sort(counts)
    if count==0 then
        s.scanSummary='No NPCs within '..radius..' units of camp'
    else
        s.scanSummary='Found '..count..' NPCs; rejected: '..table.concat(counts,', ')
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
-- MQ2Melee owns all attack, stick, skills, disciplines and AA rotation.
-- /killthis is its documented way to hand over a confirmed combat target.
local function handoffCombat(r,s,hostile,assist)
    if cfg(r,'UseMelee')~=1 or not s.camp or campDistance(s)>cfg(r,'AutoCampRadius') or not yes('Plugin[MQ2Melee].IsLoaded') or
       not yes('Melee.Enable') or not yes('Melee.MeleeMode') then return end
    if yes('Melee.Combat') or yes('Me.Combat') or yes('Stick.Active') or yes('Navigation.Active') then return end
    local function valid(id)
        if not npc(id) then return false end
        local e=spawn(id)
        local hp=num(e..'.PctHPs')
        local threshold=cfg(r,'AutoAssistAt')
        return yes(e..'.LineOfSight') and ((hp>0 and hp<=threshold) or (hp==0 and threshold==100)) and
            distance(position(e),s.camp)<=cfg(r,'AutoCampRadius')
    end
    local id=valid(assist) and assist or nil
    if not id then for _,candidate in ipairs(hostile) do if valid(candidate) then id=candidate;break end end end
    if not id then return end
    if num('Target.ID')~=id then command(r,'/squelch /target id '..id);return end
    if s.handoffId~=id or now()>=(s.nextHandoff or 0) then
        command(r,'/killthis')
        s.handoffId=id;s.nextHandoff=now()+2000
    end
end

function M.classvarsetup(r)
    for _,f in ipairs(settings) do r:call('loadini','General',f[1],f[2],tostring(f[3])) end
    -- A persisted toggle cannot safely restore an old coordinate in a new zone.
    r:set({},'ReturnToCamp',0)
    state(r)
end
function M.setupspells(r)
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
        -- The setting only controls AutoLua's handoff, never MQ2Melee itself.
        local v=tostring(value or ''):lower()
        local enabled
        if v=='1' or v=='on' then enabled=1
        elseif v=='0' or v=='off' then enabled=0
        elseif v=='' or v=='null' then enabled=cfg(r,'UseMelee')==1 and 0 or 1
        else return end
        r:set({},'UseMelee',enabled);r:set({},'changetoini',1)
        print('[AutoLua] MQ2Melee handoff: '..(enabled==1 and 'On' or 'Off'))
        return
    end
    shared.bind_togglevariable(r,key,value,...)
    if k=='returntocamp' then
        if cfg(r,'ReturnToCamp')==1 then rememberCamp(r,s)
        else invalidateCamp(r,s,'Camp disabled') end
    elseif k=='autopull' and cfg(r,'AutoPull')~=1 then
        if s.camp and s.phase~='idle' then returnHome(r,s,'Auto pull disabled')
        else reset(r,s,'Auto pull disabled') end
    end
end
function M.bind_pullon(r) M.bind_togglevariable(r,'AutoPull','1') end
function M.bind_pulloff(r) M.bind_togglevariable(r,'AutoPull','0') end
function M.bind_pullradius(r,value)
    local n=tonumber(value)
    if n and n==math.floor(n) and n>=50 and n<=500 then
        r:set({},'PullRadius',n);r:set({},'changetoini',1)
        print('[AutoLua] Pull radius '..n)
    else print('[AutoLua] Pull radius must be 50-500') end
end
function M.bind_pullstatus(r) print('[AutoLua] Monk: '..state(r).status) end
function M.bind_backoff(r)
    r:set({},'AutoPull',0);r:set({},'UseMelee',0);r:set({},'changetoini',1)
    local s=state(r);reset(r,s,'Back off: auto pull and MQ2Melee handoff disabled')
end
function M.event_zoned(r,line)
    local s=state(r)
    if s.camp and (tostring(line):find('LOADING, PLEASE WAIT',1,true) or
        s.camp.zone~=num('Zone.ID') or yes('Me.Zoning')) then
        invalidateCamp(r,s,'Zone changed; set a new camp')
    end
end
function M.onstop(r)
    reset(r,state(r),'Stopped')
    if cfg(r,'changetoini')==1 then M.inichanges(r) end
end

function M.classmainloop(r)
    local s=state(r);local t=now()
    if yes('Me.Zoning') or (s.camp and s.camp.zone~=num('Zone.ID')) or yes('Me.Hovering') then
        invalidateCamp(r,s,'Zone or respawn changed; set a new camp')
        return
    end
    if yes('Me.Invis') or read('Me.State')=='FEIGN' then
        reset(r,s,'Paused: invisible or feigned');return
    end
    if cfg(r,'ReturnToCamp')~=1 and s.camp then invalidateCamp(r,s,'Camp disabled') end
    if followName(r) then
        if s.camp then invalidateCamp(r,s,'Following; camp disabled') end
        if not yes('Me.Combat') and #hostiles()==0 and num('Spawn[pc '..followName(r)..'].ID')>0 then r:call('followtoon') end
        return
    end
    local hostile=hostiles()
    local assist=assistTarget()
    local meleeActive=yes('Plugin[MQ2Melee].IsLoaded') and yes('Melee.Combat')
    local engaged=#hostile>0 or read('Me.CombatState')=='COMBAT' or meleeActive
    if not s.camp then
        status(r,s,'Set camp here first')
        return
    end
    if s.phase~='idle' and meleeActive then
        reset(r,s,'MQ2Melee engaged; waiting for combat to finish');return
    end
    if cfg(r,'AutoPull')~=1 and (s.phase=='outbound' or s.phase=='awaitAggro') then
        returnHome(r,s,'Auto pull disabled')
    end
    if s.phase=='returning' then
        if campDistance(s)<=math.min(12,cfg(r,'AutoCampRadius')) then
            stopNav(r,s);s.phase='idle';s.pullId=nil;s.pullName=nil;s.nextPull=t+1500
            status(r,s,'Back at camp')
        elseif t>=(s.nextNav or 0) and (not s.navOwned or (not yes('Navigation.Active') and t-(s.navStarted or 0)>1000)) then
            stopNav(r,s);s.nextNav=t+2000
            if not startNav(r,s,campCommand(s),8) then status(r,s,'Waiting for a navigable path back to camp') end
        end
        return
    end
    if s.phase=='outbound' then
        if engaged then returnHome(r,s,'Aggro acquired on approach');return end
        if assist then returnHome(r,s,'Group already fighting');return end
        local ready,reason=groupReady(r)
        if not ready then returnHome(r,s,reason);return end
        if not eligible(r,s,s.pullId) or t>=s.deadline then reject(r,s,'Pull target unavailable or unreachable');return end
        local method=pullMethod()
        if canTag(s.pullId,method) then
            stopNav(r,s)
            if num('Target.ID')~=s.pullId then command(r,'/squelch /target id '..s.pullId);return end
            if yes('Me.Sitting') then command(r,'/stand');return end
            if num('Me.Casting.ID')>0 then return end
            command(r,method.command)
            s.phase='awaitAggro';s.deadline=t+6000
            status(r,s,'Tagged '..s.pullName..' with '..method.name..'; waiting for aggro')
        elseif not s.navOwned or (not yes('Navigation.Active') and t-(s.navStarted or 0)>1000) then
            if not method then status(r,s,'Waiting for pull ability');return end
            stopNav(r,s)
            if not startNav(r,s,'id '..s.pullId,method.range) then reject(r,s,'No path to pull target') end
        end
        return
    end
    if s.phase=='awaitAggro' then
        if num('Me.Casting.ID')>0 and t<s.deadline then return end
        if engaged then returnHome(r,s,'Aggro confirmed')
        elseif t>=s.deadline or not npc(s.pullId) then reject(r,s,'Pull not confirmed') end
        return
    end
    local busyMovement=yes('Navigation.Active') or yes('MoveTo.Moving') or yes('Stick.Active') or yes('Me.Combat')
    if engaged or assist then s.nextPull=t+1500 end
    if campDistance(s)>cfg(r,'AutoCampRadius') then
        if busyMovement or meleeActive then
            status(r,s,'Waiting for movement or attack to finish');return
        end
        returnHome(r,s,'Outside camp radius');return
    end
    if engaged or assist then
        status(r,s,'Waiting for combat; MQ2Melee handles combat')
        handoffCombat(r,s,hostile,assist)
        return
    end
    s.handoffId=nil
    if cfg(r,'AutoPull')~=1 then status(r,s,'Camp active; auto pull off');return end
    if not yes('Navigation.MeshLoaded') then status(r,s,'Waiting for MQ2Nav zone mesh');return end
    if busyMovement then status(r,s,'Waiting for manual movement or attack to finish');return end
    if t<s.nextPull then return end
    if num('Me.Casting.ID')>0 then return end
    local ready,reason=groupReady(r)
    if not ready then status(r,s,reason);s.nextPull=t+1000;return end
    local method=pullMethod()
    if not method then status(r,s,'Waiting for Distant Strike or Throw Stone');s.nextPull=t+1000;return end
    local id=selectTarget(r,s,method)
    if not id then status(r,s,s.scanSummary or 'No eligible reachable NPC in pull radius');s.nextPull=t+1000;return end
    s.pullId=id;s.pullName=read(spawn(id)..'.CleanName');s.phase='outbound';s.deadline=t+45000
    status(r,s,'Pulling '..s.pullName..' (ID '..id..')')
end

function M.main(r)
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
