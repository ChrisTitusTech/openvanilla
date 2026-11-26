-- Uses the installed AutoLua deterministic MQ fixture; never accesses a game.
return function(setup,mock,eq)
    local G=require('automacros.gui')
    mock.values={}
    for _,class in ipairs({'war','brd','clr'}) do
        local r=setup(class)
        local gui=G.new(r,class)
        r.gui=gui
        local originalClassSetup=r.funcs.classvarsetup
        r.funcs.classvarsetup=function()
            eq(gui.phase,'Loading class settings','startup phase during setup')
            eq(gui.loaded,false,'settings not loaded yet')
        end
        r:call('classvarsetup')
        r.funcs.classvarsetup=originalClassSetup
        eq(gui.loaded,true,'settings shown before spell setup completes')
        eq(gui.ready,false,'controls still locked')
        local disabled,finished=0,0
        local noop=function() end
        _G.ImGuiCond={FirstUseEver=1}
        gui:draw({
            SetNextWindowSize=noop, Begin=function() return true,true end,
            End=noop, Text=noop, TextWrapped=noop, Separator=noop,
            SameLine=noop, PushID=noop, PopID=noop, SetNextItemWidth=noop,
            SliderInt=function(_,v) return v,false end,
            InputText=function(_,v) return v,false end,
            Button=function() return false end,
            Checkbox=function(_,v) return v,false end,
            BeginDisabled=function() disabled=disabled+1 end,
            EndDisabled=function() finished=finished+1 end,
        })
        eq(disabled,1,'loaded settings visible but disabled during startup')
        eq(finished,1,'disabled scope balanced')
        mock.values['Me.Zoning']='FALSE'
        local before=mock.time
        r:set({},'FollowToonName','NULLNULLNULLNULLNULL')
        r:call('zoning')
        eq(mock.time-before,5000,'no minute-long wait for placeholder follow target')
        eq(gui.phase,'Waiting for zone to settle','zoning startup phase')
        before=mock.time
        r:set({},'FollowToonName','NULL')
        r:call('zoning')
        eq(mock.time-before,5000,'no wait for NULL follow target')
        before=mock.time
        r:set({},'FollowToonName','TestFriend')
        r:call('zoning')
        eq(mock.time-before,65000,'preserve wait for real absent follow target')
        r:set({},'FollowToonName','NULL')
        mock.values={}
        r:pump()
        eq(gui.ready,true,'ready on runtime pump')
        eq(gui.phase,'Ready','startup phase complete')
        -- Simulate an actual checkbox click; no game actions occur while drawing.
        r:set({},'UseMelee',1)
        local ended,labels=0,{}
        local noop=function() end
        _G.ImGuiCond={FirstUseEver=1}
        gui:draw({
            SetNextWindowSize=noop, Begin=function() return true,true end,
            End=function() ended=ended+1 end, Text=noop, TextWrapped=noop,
            Separator=noop, SameLine=noop, PushID=noop, PopID=noop,
            SetNextItemWidth=noop, SliderInt=function(_,v) return v,false end,
            InputText=function(_,v) return v,false end, Button=function() return false end,
            Checkbox=function(label,v)
                labels[label]=true
                if label=='Auto melee' then return false,true end
                return v,false
            end,
        })
        eq(ended,1,'visible window End')
        eq(r:get({},'UseMelee'),1,'checkbox only enqueues')
        eq(labels['Slow'],class=='brd' and true or nil,'bard visibility')
        eq(labels['Auto resurrection'],class=='clr' and true or nil,'cleric visibility')
        gui:queue('AutoCampRadius',45)
        gui:queue('AutoAssistAt',73)
        assert(mock.ini['General/AutoCampRadius']~='45','draw queue must not change INI')
        r:pump()
        eq(r:get({},'UseMelee'),0,'GUI melee off')
        eq(mock.ini['General/UseMelee'],'0','GUI melee saved')
        eq(mock.ini['General/AutoCampRadius'],'45','GUI camp radius saved')
        eq(mock.ini['General/AutoAssistAt'],'73','GUI assist threshold saved')
        gui:queue('AutoCampRadius',101)
        r:pump()
        eq(r:get({},'AutoCampRadius'),45,'out-of-range radius ignored')
        gui:queue('campHere')
        r:pump()
        eq(r:get({},'ReturnToCamp'),1,'camp toggle on')
        eq(mock.ini['General/ReturnToCamp'],'1','camp saved')
        mock.values['Target.Type']='PC'
        mock.values['Target.Name']='TestFriend'
        gui:queue('followTarget')
        r:pump()
        eq(r:get({},'FollowToonName'),'TestFriend','follow selected player')
        eq(mock.ini['General/FollowToonName'],'TestFriend','follow saved')
        gui:queue('stopFollow')
        r:pump()
        eq(r:get({},'FollowToonName'),'NULL','stop follow')
        mock.values['Target.Type']='NPC'
        gui:queue('followTarget')
        r:pump()
        eq(r:get({},'FollowToonName'),'NULL','reject NPC follow target')
        mock.values={}
        gui.open=false
        mock.binds['/autolua']('gui')
        r:pump()
        eq(gui.open,true,'GUI reopens via bind')
        if class=='brd' then
            gui:queue('UseSlow',false)
            gui:queue('UseMez',false)
            r:pump()
            eq(mock.ini['General/UseSlow'],'0','slow saved')
            eq(mock.ini['General/UseMez'],'0','mez saved')
        elseif class=='clr' then
            local lastGem=r:get({},'spellslots')
            mock.values['Me.Gem['..r:get({},'DivineBuff')..']']=tostring(lastGem)
            gui:queue('usepromheals',false)
            gui:queue('DivineBuffOn',true)
            gui:queue('AutoRez',false)
            gui:queue('Manatonuke',60)
            gui:queue('mountitem',"Test's Mount")
            gui:queue('NoCures',true)
            r:pump()
            eq(mock.ini['General/usepromheals'],'0','promised saved')
            eq(r:get({},'promgem'),lastGem-1,'promised avoids occupied gem')
            eq(mock.ini['General/DivineBuffOn'],'1','divine buff saved')
            eq(mock.ini['General/AutoRez'],'0','rez saved')
            eq(mock.ini['General/Manatonuke'],'60','mana threshold saved')
            eq(mock.ini['Spells/mountitem'],"Test's Mount",'mount saved')
            eq(r:get({},'NoCures'),1,'session setting applied')
            eq(mock.ini['General/NoCures'],nil,'session setting not persisted')
            gui:queue('mountitem','bad"; /echo bad')
            gui:queue('NoCures',false)
            r:pump()
            eq(mock.ini['Spells/mountitem'],"Test's Mount",'invalid mount rejected')
            eq(r:get({},'NoCures'),0,'session setting reversible')
            mock.values['Spawn[id 123 group].ID']='123'
            gui:queue('quietTarget')
            gui:queue('newTank')
            r:pump()
            eq(mock.ini['General/qmtarget'],'123','Quiet Miracle recipient saved')
            eq(r:get({},'newtank'),1,'tank refresh requested')
            gui:queue('clearQuietTarget')
            r:pump()
            eq(mock.ini['General/qmtarget'],'0','Quiet Miracle recipient cleared')
        else
            gui:queue('AutoRez',true)
            r:pump()
            eq(r:get({},'AutoRez'),nil,'unsupported class setting ignored')
        end

        -- Verify that the renderer balances Begin/End even when collapsed.
        ended=0
        gui:draw({
            SetNextWindowSize=function() end,
            Begin=function() return true,false end,
            End=function() ended=ended+1 end,
        })
        eq(ended,1,'collapsed window End')
        print('PASS '..class..' GUI queued settings, persistence and reopen')
    end
end
