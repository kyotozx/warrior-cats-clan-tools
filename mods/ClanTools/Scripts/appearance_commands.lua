-- Route semantic game commands only for the owned appearance screen.
local M={}
function M.key_command(h,key)
 if key=='Tab'then return 23 end
 if key=='BackSpace'or key=='Escape'then return 25 end
 if key=='R'or key=='Gamepad_FaceButton_Left'then return 27 end
 if not h.footerMode then return nil end
 return ({Left=4,A=4,Right=3,D=3,Up=1,W=1,Enter=26,SpaceBar=26})[key]
end
function M.canonical(command)
 return ({[8]=23,[18]=4,[17]=3,[15]=1})[command]or command
end
-- Raw keys and generated semantic commands can arrive for both the private
-- editor and the suspended native pause screen in one input frame.
function M.route_once(h,command,event,dispatch,defer)
 local id=M.canonical(command);h.handledCommands=h.handledCommands or{}
 if (event==0 or event==2)and h.handledCommands[id]then return true end
 local consumed=M.route(h,command,event,dispatch)
 if consumed and(event==0 or event==2)then
  h.handledCommands[id]=true
  defer(function()h.handledCommands[id]=nil end)
 end
 return consumed
end
function M.route(h,command,event,dispatch)
 if h.closed then return false end
 local actions=h.footerActions or{'reset','cancel','apply'}
 local default=h.footerDefault or 2
 if command==25 then
  if event==0 then dispatch(h.backAction or'cancel')end
  return true -- suppress release/repeat too; native Back is a hold-to-create flow
 end
 -- Generic Button_X (7) is also E on keyboard: E belongs to preview rotation.
 -- Randomize has its own command (27), including the controller X mapping.
 if command==27 then
  if event==0 then dispatch('randomize')end
  return true
 end
 if command==23 or command==8 then
  if event==0 then h.footerMode=not h.footerMode;h.footerIndex=default end
  return true
 end
 if not h.footerMode then return h.comparing==true end
 if event==0 or event==2 then
  if command==4 or command==18 then h.footerIndex=(h.footerIndex or default)-1
  elseif command==3 or command==17 then h.footerIndex=(h.footerIndex or default)+1
  elseif command==1 or command==15 then h.footerMode=false
  elseif command==26 and event==0 then dispatch(actions[h.footerIndex or default])end
  h.footerIndex=((h.footerIndex or default)-1)%math.max(1,#actions)+1
 end
 return true
end
return M
