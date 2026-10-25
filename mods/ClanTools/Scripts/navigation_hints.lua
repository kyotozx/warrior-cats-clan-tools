-- Shared wording derived from the active common menu mappings.
local M={}
local labels={Gamepad_FaceButton_Bottom='A (Cross)',Gamepad_FaceButton_Right='B (Circle)',
 Gamepad_FaceButton_Left='X (Square)',Gamepad_FaceButton_Top='Y (Triangle)',
 Gamepad_LeftShoulder='LB (L1)',Gamepad_RightShoulder='RB (R1)',
 Gamepad_Special_Left='View (Touchpad)',Gamepad_Special_Right='Menu (Options)',
 Gamepad_LeftThumbstick='L3',Gamepad_RightThumbstick='R3',One='1',Two='2',Three='3',Four='4',
 SpaceBar='Space',BackSpace='Backspace',LeftControl='Left Ctrl',RightControl='Right Ctrl'}
local function label(key)return labels[key]or key:gsub('Gamepad_DPad_','D-pad ')end
function M.build(rows)
 local function binding(command,device,fallback,original)
  local found
  for _,r in ipairs(rows or{})do if r.command==command and r.device==device and r.key then
   if not found then found=r.key end
   if original and r.original==original then return label(r.key)end
  end end
  return label(found or fallback)
 end
 local confirm=binding(26,'keyboard','Enter')..' / '..binding(5,'gamepad','Gamepad_FaceButton_Bottom')
 local back=binding(25,'keyboard','BackSpace')..' / '..binding(6,'gamepad','Gamepad_FaceButton_Right')
 local tabs=binding(9,'keyboard','One')..' / '..binding(10,'keyboard','Two')..' | '..binding(9,'gamepad','Gamepad_LeftShoulder')..' / '..binding(10,'gamepad','Gamepad_RightShoulder')
 local names={binding(1,'keyboard','Up','Up'),binding(2,'keyboard','Down','Down'),binding(4,'keyboard','Left','Left'),binding(3,'keyboard','Right','Right')}
 local nav=table.concat(names,' / ')
 if nav=='Up / Down / Left / Right'then nav='Arrows'end
 return{navigate=nav..' / D-pad / left stick',tabs=tabs,actions=confirm..': select     '..back..': back'}
end
return M
