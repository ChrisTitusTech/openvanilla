-- AutoLua monk regression tests using the existing deterministic MQ fixture.
return function(setup,mock,eq)
    local function value(k,v) mock.values[k]=tostring(v) end
    local function move(x,y,z) value('Me.X',x);value('Me.Y',y);value('Me.Z',z) end
    local function mob(id,name,x,y,z,los,class)
        local e='Spawn[id '..id..']'
        for k,v in pairs({ID=id,Type='NPC',Targetable='TRUE',PctHPs=100,X=x,Y=y,Z=z,
            Distance3D=math.sqrt((x-tonumber(mock.values['Me.X']))^2+(y-tonumber(mock.values['Me.Y']))^2+(z-tonumber(mock.values['Me.Z']))^2),
            LineOfSight=los and 'TRUE' or 'FALSE',CleanName=name}) do value(e..'.'..k,v) end
        value(e..'.Master.ID',0);value(e..'.Class.ID',class or 1)
    end
    local function commandsSince(n,cmd)
        for i=n+1,#mock.commands do if mock.commands[i]==cmd then return true end end
        return false
    end
    local function tick(r,elapsed) mock.time=mock.time+(elapsed or 100);r:call('classmainloop') end
    local scannable={}
    local mq=require('mq')
    local previousScan=mq.getFilteredSpawns
    local previousCmd=mq.cmd
    mq.cmd=function(cmd)
        previousCmd(cmd)
        if cmd=='/melee off' then value('Melee.Enable','FALSE')
        elseif cmd=='/melee on' then value('Melee.Enable','TRUE')
        elseif cmd=='/melee reset' then
            value('Melee.Combat','FALSE');value('Me.Combat','FALSE');value('Stick.Active','FALSE')
        elseif cmd=='/squelch /attack on' then value('Me.Combat','TRUE')
        elseif cmd=='/squelch /attack off' then value('Me.Combat','FALSE')
        elseif cmd=='/stick off' then value('Stick.Active','FALSE')
        elseif cmd:match('^/stick ') then value('Stick.Active','TRUE') end
    end
    mq.getFilteredSpawns=function(predicate)
        local spawns={}
        for _,id in ipairs(scannable) do
            local e='Spawn[id '..id..']'
            local obj={ID=function() return tonumber(mock.values[e..'.ID']) end,
                Type=function() return mock.values[e..'.Type'] end,
                X=function() return tonumber(mock.values[e..'.X']) end,
                Y=function() return tonumber(mock.values[e..'.Y']) end}
            if predicate(obj) then spawns[#spawns+1]=obj end
        end
        return spawns
    end
    mock.values={}
    move(100,200,5)
    value('Zone.ID',101);value('Me.Invis','FALSE');value('Me.State','STAND')
    value('Me.Combat','FALSE');value('Me.CombatState','ACTIVE');value('Me.Casting.ID',0)
    value('Melee.Enable','TRUE');value('Melee.MeleeMode','TRUE');value('Melee.Combat','FALSE')
    value('Me.XTarget',0);value('Me.XTarget[1].ID',0);value('Me.XTargetSlots',13)
    value('Navigation.MeshLoaded','TRUE');value('Navigation.Active','FALSE')
    value('Group.Members',2);value('Group.Member[1].ID',10);value('Group.Member[1].PctHPs',100)
    value('Group.Member[1].Class.ShortName','WAR')
    value('Group.Member[2].ID',11);value('Group.Member[2].PctHPs',100)
    value('Group.Member[2].Class.ShortName','CLR');value('Group.Member[2].PctMana',100)
    value('Me.AltAbilityReady[Distant Strike]','TRUE');value('Me.AltAbility[Distant Strike].ID',12345)
    value('Me.AltAbility[Distant Strike].Spell.MyRange',300)
    value('Me.AltAbility[Distant Strike].Spell.MyCastTime.Raw',0)
    value('Me.CombatAbilityReady[Throw Stone]','TRUE');value('Spell[Throw Stone].Range',70)
    local r=setup('mnk')
    eq(mock.values['Melee.Enable'],'FALSE','disable plugin during initialization')
    eq(r.monk.meleeWasEnabled,true,'remember originally enabled plugin')
    value('Melee.Enable','TRUE');value('Melee.Combat','TRUE');value('Stick.Active','TRUE')
    local reenable=#mock.commands
    tick(r)
    assert(commandsSince(reenable,'/melee reset'),'release plugin-owned engagement')
    eq(mock.values['Melee.Enable'],'FALSE','keep plugin disabled even if manually enabled')
    eq(mock.values['Stick.Active'],'FALSE','plugin-owned stick released')
    eq(r:get({},'AutoPull'),0,'auto pull opt-in')
    eq(r:get({},'ReturnToCamp'),0,'fresh camp required')
    eq(r:get({},'PullRadius'),350,'camp radius default')
    eq(r:get({},'PullZRadius'),90,'vertical radius default')
    eq(r:get({},'PullMaxPath'),1000,'path maximum default')
    eq(r:get({},'PullTimeout'),15,'activation timeout default')
    r:dispatch('pullon')
    local before=#mock.commands
    tick(r,2000)
    eq(r.monk.status,'Set camp here first','no automatic pull without camp')
    eq(#mock.commands,before,'no movement without camp')
    r:dispatch('camphere')
    eq(r.monk.camp.x,100,'camp x');eq(r.monk.camp.y,200,'camp y');eq(r.monk.camp.z,5,'camp z')

    -- GUI applies class settings to the same character INI.
    local G=require('automacros.gui')
    r.gui=G.new(r,'mnk');r:pump()
    r.gui:queue('PullName','goblin');r.gui:queue('PullRadius',250);r:pump()
    eq(mock.ini['General/PullName'],'goblin','NPC name saved')
    eq(mock.ini['General/PullRadius'],'250','pull distance saved')
    assert(r.gui.fields.AutoPull and r.gui.fields.PullMinHealerMana)
    r.gui:queue('PullRadius',10001);r:pump()
    eq(r:get({},'PullRadius'),250,'invalid GUI pull radius rejected')
    r.gui:queue('PullName','a goblin');r:pump()
    eq(mock.ini['General/PullName'],'a goblin','name filter accepts spaces')
    r.gui:queue('PullName','goblin');r:pump()
    local labels={};local noop=function() end
    _G.ImGuiCond={FirstUseEver=1}
    r.gui:draw({
        SetNextWindowSize=noop, Begin=function() return true,true end, End=noop,
        Text=noop, TextWrapped=noop, Separator=noop, SameLine=noop,
        PushID=noop, PopID=noop, SetNextItemWidth=noop,
        SliderInt=function(_,v) return v,false end, InputText=function(_,v) return v,false end,
        Button=function() return false end,
        Checkbox=function(label,v) labels[label]=true;return v,false end,
    })
    assert(labels['Auto pull'] and labels['Return to camp'] and labels['Auto melee'],'monk config controls rendered')

    -- Nearest merchant and wrong name are rejected; next reachable mob is chosen.
    local candidates={100,101,102,104,103,105,106,107}
    mob(100,'goblin merchant',105,200,5,true,41)
    mob(101,'an orc',110,200,5,true)
    mob(102,'a goblin',150,200,5,false);value('Navigation.PathExists[id 102]','FALSE')
    value('Navigation.PathLength[id 102]',-1)
    mob(103,'a goblin scout',200,200,5,false)
    value('Spawn[id 103].PctHPs',0);value('Spawn[id 103].Class.ID',0)
    value('Navigation.PathExists[id 103]','FALSE');value('Navigation.PathLength[id 103]',-1)
    mob(104,'a goblin runner',125,200,5,true);value('Navigation.PathLength[id 104]',-1)
    mob(105,'a goblin upstairs',100,200,200,true);value('Navigation.PathLength[id 105]',20)
    mob(106,'a goblin locked',140,200,5,true);value('Spawn[id 106].CanEngage','FALSE')
    value('Navigation.PathLength[id 106]',40)
    mob(107,'a goblin far path',145,200,5,true);value('Navigation.PathLength[id 107]',1200)
    value('Group.Member[2].PctMana',20)
    before=#mock.commands;tick(r,2000)
    eq(r.monk.status,'Waiting for healer mana','healer mana gate')
    eq(#mock.commands,before,'no pull while healer low')
    value('Group.Member[2].PctMana',100)
    value('Group.Member[1].Aggressive','TRUE')
    tick(r,2000);eq(r.monk.status,'Waiting for group combat to finish','group attack gate')
    value('Group.Member[1].Aggressive','FALSE')
    value('Navigation.MeshLoaded','FALSE')
    tick(r,2000);eq(r.monk.status,'Waiting for MQ2Nav zone mesh','mesh gate')
    value('Navigation.MeshLoaded','TRUE')
    value('Navigation.Active','TRUE')
    before=#mock.commands;tick(r,2000)
    eq(r.monk.status,'Waiting for manual movement or attack to finish','manual navigation gate')
    eq(#mock.commands,before,'manual navigation left alone')
    value('Navigation.Active','FALSE')
    scannable={}
    tick(r,2000);eq(r.monk.status,'No NPCs within 250 units of camp','empty radius diagnosis')
    scannable=candidates
    tick(r,2000)
    assert(r.monk.status:find('service class=1',1,true) and r.monk.status:find('no nav path=3',1,true)
        and r.monk.status:find('name filter=1',1,true) and r.monk.status:find('vertical range=1',1,true)
        and r.monk.status:find('encounter locked=1',1,true) and r.monk.status:find('path too long=1',1,true),
        'rejected candidates diagnosed: '..r.monk.status)
    value('Navigation.PathExists[id 103]','TRUE');value('Navigation.PathLength[id 103]',90)
    value('Navigation.PathExists[id 104]','TRUE');value('Navigation.PathLength[id 104]',200)
    tick(r,2000)
    eq(r.monk.pullId,103,'shortest path wins even if another NPC is closer geographically')
    eq(r.monk.phase,'outbound','begin pull')
    eq(mock.values['Melee.Enable'],'FALSE','plugin remains off before leaving camp')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 103 distance=292 lineofsight=on'),'navigate to pull target')
    value('Navigation.Active','TRUE');move(175,200,5)
    mob(103,'a goblin scout',200,200,5,true)
    value('Target.ID',123)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav stop'),'stop owned nav before tagging')
    assert(commandsSince(before,'/squelch /target id 103'),'target confirmed NPC')
    assert(not commandsSince(before,'/alt act 12345'),'do not tag before target confirmation')
    value('Navigation.Active','FALSE');value('Target.ID',103)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/alt act 12345'),'use known AA')
    eq(r.monk.phase,'awaitAggro','await confirmed aggro')
    before=#mock.commands;tick(r,100)
    eq(#mock.commands,before,'do not immediately spam ability')
    tick(r,500)
    assert(commandsSince(before,'/alt act 12345'),'retry unconfirmed AA request')
    value('Me.AltAbilityReady[Distant Strike]','FALSE')
    tick(r,100)
    eq(r.monk.action.confirmed,true,'cooldown flip confirms activation')
    before=#mock.commands;tick(r,1000)
    eq(r.monk.phase,'awaitAggro','confirmed AA gets an aggro grace period')
    eq(#mock.commands,before,'no premature fallback toward mob')

    -- Sparse hostile slot, then return to anchored coordinates.
    value('Me.XTarget',1);value('Me.XTarget[5].ID',103);value('Me.XTarget[5].Type','NPC')
    value('Me.XTarget[5].TargetType','Auto Hater');value('Me.CombatState','ACTIVE')
    tick(r);eq(r.monk.phase,'returning','aggro returns home')
    local home='loc 200.000 100.000 5.000'
    value('Navigation.PathExists['..home..']','TRUE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav '..home..' distance=8'),'navigate back to exact camp')
    value('Navigation.Active','TRUE')
    value('Me.State','FEIGN');before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav stop'),'feign stops owned navigation')
    eq(r.monk.phase,'returning','retain return phase when feigned')
    eq(r.monk.waitMobId,103,'retain pulled mob during feign')
    eq(mock.values['Melee.Enable'],'FALSE','do not restore plugin mid-pull')
    before=#mock.commands;tick(r,4000)
    eq(#mock.commands,before,'do not repeatedly stop or force standing')
    value('Me.State','STAND');value('Navigation.Active','FALSE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav '..home..' distance=8'),'resume return after standing')
    value('Navigation.Active','TRUE');move(100,200,5)
    value('Me.CombatState','COMBAT')
    mob(103,'a goblin scout',180,200,5,true);value('Spawn[id 103].PctHPs',90)
    tick(r);eq(r.monk.phase,'waitingMob','arrived back at camp, mob not here yet')
    eq(mock.values['Melee.Enable'],'FALSE','keep plugin disabled after return to camp')
    value('Navigation.Active','FALSE')
    before=#mock.commands;tick(r,1000)
    eq(#mock.commands,before,'wait for mob instead of pulling or fighting remotely')
    -- Another NPC is in a sparse non-Auto-Hater slot with no personal
    -- aggro: don't wait for the distant pulled mob before fighting it.
    mob(108,'a goblin add',112,200,5,true);value('Spawn[id 108].PctHPs',70)
    value('Me.XTarget[9].ID',108);value('Me.XTarget[9].Type','NPC')
    value('Me.XTarget[9].TargetType','Group Main Assist Target')
    value('Me.XTarget[9].PctAggro',0);value('Me.XTarget',2)
    before=#mock.commands;tick(r)
    eq(r.monk.phase,'idle','camp add interrupts arrival wait')
    assert(commandsSince(before,'/squelch /target id 108'),'target in-camp add before distant pull')
    value('Target.ID',108)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/squelch /attack on'),'attack add without Auto Hater role')
    value('Target.MaxRangeTo',20);value('Target.Distance',12);value('Stick.Active','FALSE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/stick 16.0 moveback loose uw'),'stick to live camp target')
    value('Spawn[id 108].Type','Corpse');value('Me.XTarget[9].ID',0);value('Me.XTarget',1)
    mob(103,'a goblin scout',112,200,5,true);value('Spawn[id 103].PctHPs',90)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/squelch /attack off'),'release attack after target death')
    assert(commandsSince(before,'/stick off'),'release stick after target death')
    assert(commandsSince(before,'/squelch /target id 103'),'advance to next extended target')
    value('Target.ID',103)
    value('Me.AbilityReady[Flying Kick]','TRUE')
    before=#mock.commands;tick(r,2000)
    eq(r.monk.status,'Fighting extended target','fight subsequent camp target')
    assert(commandsSince(before,'/squelch /attack on'),'attack next target')
    eq(#mock.commands,before+1,'no custom combat abilities')
    tick(r)
    move(150,200,5)
    before=#mock.commands;tick(r,2000)
    eq(#mock.commands,before,'do not steer or pull while fighting outside camp')
    before=#mock.commands;r:dispatch('meleeoff')
    assert(commandsSince(before,'/squelch /attack off'),'melee toggle stops owned attack')
    assert(commandsSince(before,'/stick off'),'melee toggle stops owned stick')
    eq(mock.values['Melee.Enable'],'FALSE','melee toggle never restores plugin')
    r:dispatch('meleeon')
    value('Me.XTarget',0);value('Me.XTarget[5].ID',0);value('Me.CombatState','ACTIVE')
    move(100,200,5)
    before=#mock.commands;tick(r)
    eq(#mock.commands,before,'no fighting without a hostile')

    -- Throw Stone fallback and cancel during outbound navigation.
    value('Me.AltAbilityReady[Distant Strike]','FALSE')
    mob(103,'a goblin scout',195,200,5,true)
    tick(r,2000);eq(r.monk.phase,'outbound','next pull after combat')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 103 distance=65 lineofsight=on'),'Throw Stone approach range')
    value('Navigation.Active','TRUE');move(150,200,5);mob(103,'a goblin scout',195,200,5,true)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav stop'),'stop navigation before Throw Stone')
    assert(not commandsSince(before,'/doability "Throw Stone"'),'wait until navigation stops')
    value('Navigation.Active','FALSE')
    tick(r)
    assert(commandsSince(before,'/doability "Throw Stone"'),'Throw Stone fallback')
    eq(r.monk.phase,'awaitAggro','fallback awaits aggro confirmation')
    value('Navigation.Active','FALSE')
    tick(r,7000);eq(r.monk.phase,'outbound','reposition closer instead of the old 6-second timeout')
    eq(r.monk.approachLimit,32,'reduced approach range after unconfirmed use')
    assert(not r.monk.rejected[103],'do not prematurely blacklist')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 103 distance=32 lineofsight=on'),'closer retry navigation')
    move(170,200,5);mob(103,'a goblin scout',195,200,5,true)
    value('Navigation.Active','FALSE')
    tick(r);eq(r.monk.phase,'awaitAggro','retry at a shorter range')
    tick(r,9000);eq(r.monk.phase,'returning','unconfirmed pull times out after 15s and returns')
    assert(r.monk.rejected[103]>mock.time,'failed target temporarily skipped')
    tick(r)
    before=#mock.commands
    r:dispatch('campoff')
    assert(commandsSince(before,'/nav stop'),'camp off stops owned navigation')
    eq(r.monk.camp,nil,'camp invalidated')
    eq(r:get({},'ReturnToCamp'),0,'camp off persisted')
    eq(mock.values['Melee.Enable'],'FALSE','camp off leaves plugin disabled')
    r:dispatch('camphere')
    eq(r.monk.camp.x,170,'new camp anchors current location')
    value('Zone.ID',102);tick(r)
    eq(r.monk.camp,nil,'zone change clears camp')
    eq(r:get({},'ReturnToCamp'),0,'no stale-zone camp')
    eq(mock.values['Melee.Enable'],'FALSE','zone change leaves plugin disabled')
    r:dispatch('pulloff');r:call('inichanges')
    eq(mock.ini['General/AutoPull'],'0','pull off saved')
    -- Periodically rescan en route; a newly reachable shorter path wins
    -- without restarting the overall pull timeout or firing at the old target.
    move(100,200,5);r:dispatch('camphere');r:dispatch('pullon')
    value('Me.AltAbilityReady[Distant Strike]','TRUE')
    mob(103,'a goblin scout',200,200,5,false);mob(104,'a goblin runner',150,200,5,false)
    value('Navigation.PathLength[id 103]',90);value('Navigation.PathLength[id 104]',200)
    value('Navigation.PathExists[id 103]','TRUE');value('Navigation.PathExists[id 104]','TRUE')
    value('Navigation.Active','FALSE')
    tick(r,2000);eq(r.monk.pullId,103,'initial rescan target')
    tick(r);eq(r.monk.navOwned,true,'owned approach navigation')
    value('Navigation.Active','TRUE')
    value('Navigation.PathLength[id 103]',150);value('Navigation.PathLength[id 104]',40)
    local deadline=r.monk.deadline
    before=#mock.commands;tick(r,5100)
    eq(r.monk.pullId,104,'rescan chose shorter path')
    eq(r.monk.deadline,deadline,'rescan preserves bound')
    assert(commandsSince(before,'/nav stop'),'rescan stops old navigation')
    assert(not commandsSince(before,'/alt act 12345'),'never tag old target on switch')
    value('Navigation.Active','FALSE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 104 distance=292 lineofsight=on'),'start new navigation after old stops')
    r:dispatch('campoff');r:dispatch('pulloff')
    -- Graceful stop restores the original runtime setting.
    r:dispatch('camphere')
    r:dispatch('pullon');tick(r,2000)
    eq(r.monk.phase,'outbound','pull works with plugin disabled')
    r.monk.navOwned=true
    before=#mock.commands
    local ok,err=pcall(function() r:dispatch('stop') end)
    assert(not ok and tostring(err):find('Mock exit',1,true),'graceful stop reached mq.exit')
    assert(commandsSince(before,'/nav stop'),'stop cancels monk-owned navigation')
    eq(r.running,false,'runtime stopped')
    assert(commandsSince(before,'/melee on'),'stop restores initially enabled plugin')
    eq(mock.values['Melee.Enable'],'TRUE','previous plugin state restored')
    value('Melee.Enable','FALSE')
    local disabled=setup('mnk')
    eq(disabled.monk.meleeWasEnabled,false,'remember plugin was disabled')
    before=#mock.commands
    ok,err=pcall(function() disabled:dispatch('stop') end)
    assert(not ok and tostring(err):find('Mock exit',1,true),'second stop reached mq.exit')
    assert(not commandsSince(before,'/melee on'),'stop never enables initially disabled plugin')
    eq(mock.values['Melee.Enable'],'FALSE','previous disabled state preserved')

    print('PASS monk GUI settings, camp gate, navigation, target eligibility, ranged pull, aggro return, basic combat, session-wide MQ2Melee suspension, fallback, zoning and cancellation')
    mock.values={}
    mq.getFilteredSpawns=previousScan;mq.cmd=previousCmd
end
