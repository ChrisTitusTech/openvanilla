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
    mock.values={}
    move(100,200,5)
    value('Zone.ID',101);value('Me.Invis','FALSE');value('Me.State','STAND')
    value('Me.Combat','FALSE');value('Me.CombatState','ACTIVE');value('Me.Casting.ID',0)
    value('Me.XTarget',0);value('Me.XTarget[1].ID',0);value('Me.XTargetSlots',13)
    value('Navigation.MeshLoaded','TRUE');value('Navigation.Active','FALSE')
    value('Group.Members',2);value('Group.Member[1].ID',10);value('Group.Member[1].PctHPs',100)
    value('Group.Member[1].Class.ShortName','WAR')
    value('Group.Member[2].ID',11);value('Group.Member[2].PctHPs',100)
    value('Group.Member[2].Class.ShortName','CLR');value('Group.Member[2].PctMana',100)
    value('Me.AltAbilityReady[Distant Strike]','TRUE');value('Me.AltAbility[Distant Strike].Spell.Range',300)
    value('Me.CombatAbilityReady[Throw Stone]','TRUE');value('Spell[Throw Stone].Range',70)
    local r=setup('mnk')
    eq(r:get({},'AutoPull'),0,'auto pull opt-in')
    eq(r:get({},'ReturnToCamp'),0,'fresh camp required')
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
    r.gui:queue('PullRadius',501);r:pump()
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
    assert(labels['Auto pull'] and labels['Return to camp'],'monk config controls rendered')

    -- Nearest merchant and wrong name are rejected; next reachable mob is chosen.
    local search='npc targetable nopet radius 250'
    value('SpawnCount['..search..']',4)
    for i,id in ipairs({100,101,102,103}) do value('NearestSpawn['..i..','..search..'].ID',id) end
    mob(100,'goblin merchant',105,200,5,true,41)
    mob(101,'an orc',110,200,5,true)
    mob(102,'a goblin',150,200,5,false);value('Navigation.PathExists[id 102]','FALSE')
    mob(103,'a goblin scout',200,200,5,false);value('Navigation.PathExists[id 103]','TRUE')
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
    tick(r,2000)
    eq(r.monk.pullId,103,'reachable matching NPC')
    eq(r.monk.phase,'outbound','begin pull')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 103 distance=292'),'navigate to pull target')
    value('Navigation.Active','TRUE');move(175,200,5)
    mob(103,'a goblin scout',200,200,5,true)
    value('Target.ID',123)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav stop'),'stop owned nav before tagging')
    assert(commandsSince(before,'/squelch /target id 103'),'target confirmed NPC')
    assert(not commandsSince(before,'/aa act Distant Strike'),'do not tag before target confirmation')
    value('Navigation.Active','FALSE');value('Target.ID',103)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/aa act Distant Strike'),'use known AA')
    eq(r.monk.phase,'awaitAggro','await confirmed aggro')

    -- Sparse hostile slot, then return to anchored coordinates.
    value('Me.XTarget',1);value('Me.XTarget[5].ID',103);value('Me.XTarget[5].Type','NPC')
    value('Me.XTarget[5].TargetType','Auto Hater');value('Me.CombatState','ACTIVE')
    tick(r);eq(r.monk.phase,'returning','aggro returns home')
    local home='loc 200.000 100.000 5.000'
    value('Navigation.PathExists['..home..']','TRUE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav '..home..' distance=8'),'navigate back to exact camp')
    value('Navigation.Active','TRUE');move(100,200,5)
    value('Me.CombatState','COMBAT')
    mob(103,'a goblin scout',112,200,5,true);value('Spawn[id 103].PctHPs',90)
    tick(r);eq(r.monk.phase,'idle','arrived back at camp')
    value('Navigation.Active','FALSE');value('Target.MaxRangeTo',20);value('Target.Distance',12)
    value('Me.AbilityReady[Flying Kick]','TRUE');value('Stick.Active','FALSE')
    before=#mock.commands;tick(r,2000)
    eq(r.monk.status,'Fighting at camp','wait during encounter')
    assert(commandsSince(before,'/squelch /attack on'),'melee at camp')
    assert(commandsSince(before,'/squelch /doability Flying Kick'),'monk remaining melee ability')
    assert(not commandsSince(before,'/aa act Distant Strike'),'no chain pull in combat')

    value('Me.XTarget',0);value('Me.XTarget[5].ID',0);value('Me.CombatState','ACTIVE')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/squelch /attack off'),'stop owned melee when fight ends')
    assert(commandsSince(before,'/stick off'),'stop owned stick when fight ends')

    -- Throw Stone fallback and cancel during outbound navigation.
    value('Me.AltAbilityReady[Distant Strike]','FALSE')
    mob(103,'a goblin scout',195,200,5,true)
    tick(r,2000);eq(r.monk.phase,'outbound','next pull after combat')
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/nav id 103 distance=65'),'Throw Stone approach range')
    value('Navigation.Active','TRUE');move(150,200,5);mob(103,'a goblin scout',195,200,5,true)
    before=#mock.commands;tick(r)
    assert(commandsSince(before,'/doability "Throw Stone"'),'Throw Stone fallback')
    eq(r.monk.phase,'awaitAggro','fallback awaits aggro confirmation')
    value('Navigation.Active','FALSE')
    tick(r,7000);eq(r.monk.phase,'returning','unconfirmed pull times out and returns')
    assert(r.monk.rejected[103]>mock.time,'failed target temporarily skipped')
    tick(r)
    before=#mock.commands
    r:dispatch('campoff')
    assert(commandsSince(before,'/nav stop'),'camp off stops owned navigation')
    eq(r.monk.camp,nil,'camp invalidated')
    eq(r:get({},'ReturnToCamp'),0,'camp off persisted')
    r:dispatch('camphere')
    eq(r.monk.camp.x,150,'new camp anchors current location')
    value('Zone.ID',102);tick(r)
    eq(r.monk.camp,nil,'zone change clears camp')
    eq(r:get({},'ReturnToCamp'),0,'no stale-zone camp')
    r:dispatch('pulloff');r:call('inichanges')
    eq(mock.ini['General/AutoPull'],'0','pull off saved')
    -- Graceful stop runs the class cleanup hook, not just mq.exit().
    r:dispatch('camphere')
    r.monk.navOwned=true
    before=#mock.commands
    local ok,err=pcall(function() r:dispatch('stop') end)
    assert(not ok and tostring(err):find('Mock exit',1,true),'graceful stop reached mq.exit')
    assert(commandsSince(before,'/nav stop'),'stop cancels monk-owned navigation')
    eq(r.running,false,'runtime stopped')

    print('PASS monk GUI settings, camp gate, navigation, target eligibility, ranged pull, aggro return, melee, fallback, zoning and cancellation')
    mock.values={}
end
