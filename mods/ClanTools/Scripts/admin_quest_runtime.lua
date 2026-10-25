-- Native selected-quest adapter: discovery is reflected, mutation uses original
-- objective success and turn-in pathways. Never writes quest statuses or rewards.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={}
function M.new(ctx,bin,library)
 bin=bin or folder..'../bin/'
 local run=assert(package.loadlib(bin..(library or'admin-quests-v5.dll'),'ClanQuests_run'))
 local nonce=0
 local function invoke(s,entry,command,expected)
  assert(s and s.offline==true and s.phase==4 and not s.combat,'Quests require offline exploration.')
  assert(valid(s.pc)and valid(entry.object),'Selected quest or player is unavailable.')
  local manager=FindFirstOf('WrcSaveManager');assert(valid(manager),'Save manager unavailable.')
  local q=entry.object;assert(tostring(q:GetAddress())==entry.id,'Selected quest changed.')
  assert(valid(q.QuestGraph)and q.QuestGraph.questTag.TagName:ToString()==entry.tag,'Selected quest graph changed.')
  if entry.alias then assert(q.QuestGraph.QuestAlias.TagName:ToString()==entry.alias,'Selected quest alias changed.')end
  nonce=nonce+1;local f=assert(io.open(bin..'admin-quest-request.txt','wb'))
  assert(f:write(string.format('%d %s %x %x %x %d %d\n',nonce,command,q:GetAddress(),s.pc:GetAddress(),manager:GetAddress(),expected and expected.quest_status or 0,expected and expected.count or 0)));f:close();run()
  f=assert(io.open(bin..'admin-quest-status.txt','rb'));local text=f:read('*a');f:close()
  local r={};for k,v in text:gmatch('([%w_]+)=([^\r\n]+)')do r[k]=v end
  assert(tonumber(r.nonce)==nonce,'Stale quest response.')
  assert(r.status==(command=='QUEST_PROBE'and'READY'or'APPLIED'),r.status or'Missing quest response.')
  for _,k in ipairs({'quest_status','result','count','active','in_progress','after','stepped'})do r[k]=tonumber(r[k])end
  return r
 end
 local api={}
 local function displayedTitles()
  local out={}
  for _,row in ipairs(FindAllOf('GuiItemQuest')or{})do
   -- Read the exact title already resolved by the native quest UI, including
   -- the current rank variant. Missing widgets retain the explicit quest tag.
   pcall(function()
    if not valid(row)or not valid(row.QuestRef)then return end
    local title=row.DataQuest.Title:ToString()
    if title~=''and title~='None'then out[tostring(row.QuestRef:GetAddress())]=title end
   end)
  end
  return out
 end
 function api.listQuests(s)
  local out,diagnostics={},{seen=0,candidates=0,errors={}}
  local titles=displayedTitles()
  local manager=FindFirstOf('QuestManager');assert(valid(manager),'Quest manager unavailable.')
  for _,q in ipairs(FindAllOf('MultiObjectiveQuest')or{})do
   diagnostics.seen=diagnostics.seen+1
   if valid(q)then
    local ok,entry=pcall(function()
     local graph=q.QuestGraph;assert(valid(graph),'Quest graph unavailable.')
     assert(valid(graph.QuestBase)and graph.QuestBase:GetAddress()==q:GetAddress(),'Quest graph is a template.')
     local alias=graph.QuestAlias.TagName:ToString()
     if alias==''or alias=='None'then return nil end
     local status=manager:GetQuestStatus(graph.QuestAlias)
     if status~=2 and status~=3 then return nil end
     local e={id=tostring(q:GetAddress()),tag=graph.questTag.TagName:ToString(),alias=alias,object=q,name=graph.questTag.TagName:ToString()}
     assert(e.tag~=''and e.tag~='None','Quest tag unavailable.')
     local state=invoke(s,e,'QUEST_PROBE');for k,v in pairs(state)do e[k]=v end
     diagnostics.candidates=diagnostics.candidates+1
     e.name=titles[e.id]or e.tag
     return e
    end)
    if ok then if entry then out[#out+1]=entry end
    elseif tostring(entry):find('Quest belongs to another player',1,true)then diagnostics.foreign_owners=(diagnostics.foreign_owners or 0)+1
    else diagnostics.errors[#diagnostics.errors+1]={object=q:GetFullName(),reason=tostring(entry)}end
   end
  end
  table.sort(out,function(a,b)return a.tag<b.tag end);return out,diagnostics
 end
 function api.diagnostics(s)
  local report={classes={},quests={},objectives={}}
  for _,name in ipairs({'QuestBase','MultiObjectiveQuest','ObjectiveBase','QuestManager'})do
   report.classes[name]=#(FindAllOf(name)or{})
  end
  for _,q in ipairs(FindAllOf('MultiObjectiveQuest')or{})do
   if valid(q)then
    local e={address=tostring(q:GetAddress())}
    local ok,why=pcall(function()
     e.name=q:GetFullName();e.class=q:GetClass():GetFullName();e.status=q.QuestStatus;e.result=q.QuestResult;e.count=q.Count;e.is_set=q.bIsQuestSet
     local graph=q.QuestGraph;e.graph_valid=valid(graph)
     if e.graph_valid then
      e.graph=graph:GetFullName();e.tag=graph.questTag.TagName:ToString()
      e.alias=graph.QuestAlias.TagName:ToString()
      local manager=FindFirstOf('QuestManager');if valid(manager)then e.persisted_status=manager:GetQuestStatus(graph.QuestAlias)end
      local owner=graph.QuestBase;e.graph_owner_valid=valid(owner);if e.graph_owner_valid then e.graph_owner=tostring(owner:GetAddress())end
      if e.persisted_status==2 or e.persisted_status==3 then
       local nativeOK,r=pcall(invoke,s,{object=q,id=e.address,tag=e.tag},'QUEST_PROBE')
       e.native=nativeOK and r or tostring(r)
      end
     end
    end)
    if not ok then e.error=tostring(why)end;report.quests[#report.quests+1]=e
   end
  end
  for _,obj in ipairs(FindAllOf('ObjectiveBase')or{})do
   if valid(obj)then
    local e={};local ok,why=pcall(function()
     local q=obj.QuestBase;if not valid(q)or not valid(q.QuestGraph)then return end
     local manager=FindFirstOf('QuestManager');if not valid(manager)or manager:GetQuestStatus(q.QuestGraph.QuestAlias)~=2 then return end
     e.name=obj:GetFullName();e.class=obj:GetClass():GetFullName();e.address=tostring(obj:GetAddress());e.quest=tostring(q:GetAddress());e.index=obj.ObjectiveIdx;e.alias=q.QuestGraph.QuestAlias.TagName:ToString()
     local id=obj:GetObjectiveIDString();e.id=id:ToString()
     e.status=manager:GetObjectiveStatus(id)
    end)
    if not ok then e.error=tostring(why)end;if e.name or e.error then report.objectives[#report.objectives+1]=e end
   end
  end
  return report
 end
 api.questProbe=function(s,entry)return invoke(s,entry,'QUEST_PROBE')end
 api.questStep=function(s,entry,expected)return invoke(s,entry,'QUEST_STEP',expected)end
 api.questTurnIn=function(s,entry,expected)return invoke(s,entry,'QUEST_TURN_IN',expected)end
 return api
end
return M
