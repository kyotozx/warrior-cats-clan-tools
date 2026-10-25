-- Explicit developer probe, game thread only. Loading this file never starts a quest.
-- Native StartQuestOfTag bypasses the acceptance dialogue and can replace other
-- active quests. This helper therefore accepts one already-Available candidate
-- only in an otherwise idle campaign, after a backup and a fresh identity check.
local M={}
local tag='Quest.Procedural.Combat.MarkTerritory'
function M.new(ctx)
 local api={};local pending,consumed
 local function address(o)assert(ctx.valid(o),'Required object is unavailable.');return o:GetAddress()end
 local function inspect()
  local s=assert(ctx.snapshot(),'Campaign unavailable.')
  assert(s.offline==true and s.phase==4 and not s.combat,'Offline exploration is required.')
  assert(s.worldId=='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P','Unsupported campaign world.')
  assert(type(s.profile)=='string'and #s.profile>0 and type(s.slot)=='number','Save identity unavailable.')
  local key=table.concat({s.worldId,s.profile,s.slot,s.chapter or'',address(s.pawn),address(s.pc)},'|')
  local manager=FindFirstOf('QuestManager');address(manager)
  local candidate;local seen,statuses={},{}
  manager.Quests:ForEach(function(_,v)
   local q=v:get().Quest;local id=address(q)
   assert(not seen[id],'Duplicate quest entry in native manager.');seen[id]=true
   local status=q.QuestStatus;assert(type(status)=='number'and status>=0 and status<=5,'Unknown quest status.')
   statuses[status]=(statuses[status]or 0)+1
   assert(status~=2 and status~=3 and status~=5,'Another quest is active or awaiting completion/dialogue.')
   local graph=q.QuestGraph;address(graph)
   local name=graph.questTag.TagName:ToString()
   -- RVA3CD7460 compares the registered tag's self/parent containers. Native
   -- acceptance therefore selects the FIRST exact tag or descendant in manager
   -- order, irrespective of status. Never select a later Available template.
   if name==tag or name:sub(1,#tag+1)==tag..'.'then
    if not candidate then
     assert(name==tag,'First native match is an unexpected descendant tag.')
     assert(status==1,'The first native MarkTerritory match is not Available.')
     assert(address(graph.QuestBase)==id,'Quest graph owner mismatch.')
     assert(q:GetClass():GetFullName()=='Class /Script/SwtAdventure.SwtAdventureMultiObjectiveQuest','Unsupported quest class.')
     candidate=q
    else
     assert(status==0,'A later native MarkTerritory match is not an inactive template.')
    end
   end
  end)
  assert(candidate,'Available MarkTerritory quest not found in native manager.')
  return{snapshot=s,key=key,manager=manager,quest=candidate,id=address(candidate),managerId=address(manager),statuses=statuses}
 end
 function api.preview()
  assert(not consumed,'This probe has already attempted acceptance; do not retry.')
  pending=inspect()
  return{tag=tag,id=tostring(pending.id),status=1,profile=pending.snapshot.profile,slot=pending.snapshot.slot,statuses=pending.statuses}
 end
 function api.diagnostics()
  local out={};local manager=FindFirstOf('QuestManager');address(manager)
  manager.Quests:ForEach(function(index,v)
   local q=v:get().Quest;address(q);local graph=q.QuestGraph;address(graph)
   local name=graph.questTag.TagName:ToString()
   if name:find('MarkTerritory',1,true)then
    local ranks={};q.AvailableRanks:ForEach(function(_,rank)ranks[#ranks+1]=rank:get()end)
    out[#out+1]={index=index,id=tostring(address(q)),class=q:GetClass():GetFullName(),tag=name,status=q.QuestStatus,count=q.Count,ranks=ranks,graph=graph:GetFullName(),owner=tostring(address(graph.QuestBase))}
   end
  end)
  return out
 end
 function api.accept()
  assert(not consumed and pending,'Preview this isolated acceptance probe first.')
  local current=inspect()
  assert(current.key==pending.key and current.id==pending.id and current.managerId==pending.managerId,'Quest or campaign changed after preview.')
  local backup=assert(ctx.backupSave(current.snapshot),'Save backup failed.')
  local final=inspect()
  assert(final.key==current.key and final.id==current.id and final.managerId==current.managerId,'Quest or campaign changed during backup.')
  consumed=true;pending=nil -- Never retry a native acceptance whose outcome is uncertain.
  final.manager:StartQuestOfTag(final.quest.QuestGraph.questTag,final.snapshot.pc)
  assert(ctx.valid(final.quest),'Quest unavailable after native acceptance.')
  return{tag=tag,id=tostring(final.id),status=final.quest.QuestStatus,result=final.quest.QuestResult,backup=backup}
 end
 return api
end
return M
