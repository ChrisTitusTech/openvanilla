-- Shared, exact XYZ camp anchors and nonblocking return movement.
local mq=require('mq')
local M={}
local function read(e) return mq.parse('${'..e..'}') end
local function num(e) return tonumber(read(e)) or 0 end
local function yes(e) return read(e)=='TRUE' end
local function finite(v) return v and v==v and math.abs(v)<1000000 end
local function position()
    return tonumber(read('Me.Y')),tonumber(read('Me.X')),tonumber(read('Me.Z'))
end
local function combat() return num('Me.XTarget[1].ID')>0 or yes('Me.Combat') end
function M.stop(r)
    if r.campMovement=='nav' then r:command({},'/nav stop')
    elseif r.campMovement=='moveto' then r:command({},'/moveto off') end
    r.campMovement=nil
end
local function coordinates(r,y,x,z,zone)
    r:set({},'AutoCampY',y);r:set({},'AutoCampX',x);r:set({},'AutoCampZ',z)
    r:set({},'AutoCampZone',zone)
end
function M.capture(r)
    local y,x,z=position()
    local zone=num('Zone.ID')
    if finite(y) and finite(x) and finite(z) and zone>0 then
        M.stop(r); coordinates(r,y,x,z,zone)
        return true
    end
    return false
end
local function apply(r,p)
    M.stop(r)
    coordinates(r,p.y,p.x,p.z,p.zone)
    r:set({},'ReturnToCamp',1)
    r:set({},'FollowToonName','NULL');r:set({},'ChaseAssist',0)
    r:set({},'changetoini',1)
    if yes('AdvPath.Following') then r:command({},'/afollow off') end
    if r.funcs.applycampanchor then r:call('applycampanchor',p.y,p.x,p.z,p.zone) end
    local msg=string.format('Camp anchor Y=%.3f X=%.3f Z=%.3f zone=%d',p.y,p.x,p.z,p.zone)
    r:log(msg);print('[AutoLua] '..msg)
end
function M.request(r,y,x,z,zone)
    y,x,z=tonumber(y),tonumber(x),tonumber(z)
    if zone==nil then zone=num('Zone.ID') else zone=tonumber(zone) end
    if not (finite(y) and finite(x) and finite(z) and zone and zone>0 and zone==num('Zone.ID')) then
        print('[AutoLua] Usage: /autolua campcoords <Y> <X> <Z> [zone ID]; zone must match')
        return false
    end
    local p={y=y,x=x,z=z,zone=zone}
    if combat() or yes('Me.Hovering') or yes('Me.Zoning') then
        r.pendingCamp=p;r:log('Camp anchor queued until combat/zoning clears');return true
    end
    apply(r,p);return true
end
function M.beforePulse(r)
    if r.campMovement and (combat() or yes('Me.Zoning') or (r:get({},'ReturnToCamp') or 0)==0) then M.stop(r) end
    if r.pendingCamp and not combat() and not yes('Me.Zoning') and not yes('Me.Hovering') then
        local p=r.pendingCamp;r.pendingCamp=nil
        if p.zone==num('Zone.ID') then apply(r,p) end
    end
end
function M.status(r)
    local msg=string.format('Camp anchor Y=%.3f X=%.3f Z=%.3f zone=%d enabled=%s radius=%s',
        r:get({},'AutoCampY') or 0,r:get({},'AutoCampX') or 0,r:get({},'AutoCampZ') or 0,
        r:get({},'AutoCampZone') or 0,tostring(r:get({},'ReturnToCamp')),tostring(r:get({},'AutoCampRadius')))
    r:log(msg);print('[AutoLua] '..msg)
end
function M.groupHere(r)
    local y,x,z=position();local zone=num('Zone.ID')
    if not (finite(y) and finite(x) and finite(z) and zone>0) then return end
    r:command({},string.format('/dggaexecute /autolua campcoords %.3f %.3f %.3f %d',y,x,z,zone))
end
function M.returnTick(r)
    -- The monk owns its pull/return navigation state separately.
    if r.monk then return end
    if r:get({},'ReturnToCamp')~=1 or r:get({},'AutoCampZone')~=num('Zone.ID') or
        combat() or yes('Me.Hovering') or yes('Me.Zoning') then M.stop(r);return end
    local follow=(r:get({},'FollowToonName') or 'NULL'):lower()
    if (follow~='null' and follow~='nullnullnullnullnull' and follow~='') or yes('AdvPath.Following') then return end
    -- Stick left over from the macro's last encounter is not manual following.
    -- Never disable the saved camp because of ordinary combat movement.
    if yes('Stick.Active') or read('Stick.Status')=='ON' then
        local targetType=read('Target.Type')
        if r.campStickOwned or targetType=='Corpse' or targetType=='NULL' then r:command({},'/stick off') end
        return
    end
    local y,x,z=position()
    if not (finite(y) and finite(x) and finite(z)) then return end
    local cy,cx,cz=r:get({},'AutoCampY'),r:get({},'AutoCampX'),r:get({},'AutoCampZ')
    if not (finite(cy) and finite(cx) and finite(cz)) then return end
    local dist=math.sqrt((y-cy)^2+(x-cx)^2+(z-cz)^2)
    if r.campMovement then
        if dist<=5 then M.stop(r);return end
        local active=r.campMovement=='nav' and yes('Navigation.Active') or r.campMovement=='moveto' and yes('MoveTo.Moving')
        if active then return end
        r.campMovement=nil
    end
    if dist<=(r:get({},'AutoCampRadius') or 30) or dist>400 then return end
    if yes('Navigation.Active') or yes('MoveTo.Moving') or yes('Me.Moving') then return end
    if num('Me.Casting.ID')>0 then
        if read('Me.Class.ShortName')=='BRD' and (r:get({},'castready') or 0)==0 then r:command({},'/stopcast') end
        return
    end
    local now=mq.gettime();if now<(r.campNextMove or 0) then return end
    r.campNextMove=now+1500
    if yes('Me.Sitting') then r:command({},'/stand');return end
    if yes('Navigation.MeshLoaded') then
        r:command({},string.format('/nav loc %.3f %.3f %.3f distance=5',cy,cx,cz))
        r.campMovement='nav'
    elseif math.abs(z-cz)<=5 then
        r:command({},string.format('/moveto loc %.3f %.3f',cy,cx));r.campMovement='moveto'
    else
        r:logAction('camp-no-mesh','Camp return needs a navigation mesh for different Z coordinates');return
    end
    r:logAction('camp-return',string.format('Returning to camp Y=%.3f X=%.3f Z=%.3f distance=%.1f',cy,cx,cz,dist))
end
return M
