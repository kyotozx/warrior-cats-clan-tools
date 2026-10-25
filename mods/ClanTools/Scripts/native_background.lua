-- Borrow the live pause background, including its actual animated materials and
-- Niagara widgets. Both owners stay in the viewport; restore its Canvas slot.
local M={}
function M.new(ctx)
 local api={}
 function api.find(root,name,depth)
  if not ctx.valid(root)or(depth or 0)>12 then return end
  if root:GetFName():ToString()==name then return root end
  local ok,count=pcall(function()return root:GetChildrenCount()end)
  if ok then for i=0,count-1 do local found=api.find(root:GetChildAt(i),name,(depth or 0)+1);if found then return found end end end
 end
 function api.borrow(node,destination,background)
  assert(ctx.valid(node),'Native menu widget unavailable')
  local slot=node.Slot;local a=slot:GetAnchors();local o=slot:GetOffsets();local p=slot:GetAlignment()
  local receipt={node=node,parent=node:GetParent(),anchors={Minimum={X=a.Minimum.X,Y=a.Minimum.Y},Maximum={X=a.Maximum.X,Y=a.Maximum.Y}},
   offsets={Left=o.Left,Top=o.Top,Right=o.Right,Bottom=o.Bottom},alignment={X=p.X,Y=p.Y},z=slot:GetZOrder(),auto=slot:GetAutoSize(),background=background==true}
  local target=destination:AddChild(node)
  if background then target:SetAnchors({Minimum={X=0,Y=0},Maximum={X=1,Y=1}})
   target:SetOffsets({Left=0,Top=0,Right=0,Bottom=0});target:SetAlignment({X=0,Y=0});target:SetZOrder(-10)
  else target:SetAnchors(receipt.anchors);target:SetOffsets(receipt.offsets);target:SetAlignment(receipt.alignment);target:SetZOrder(90)end
  return receipt
 end
 function api.attach(pause,destination)return api.borrow(assert(api.find(pause.WidgetTree.RootWidget,'CanvasBackground'),'Native menu background unavailable'),destination,true)end
 function api.restore(r)
  if not r or not ctx.valid(r.node)then return true end
  if not ctx.valid(r.parent)then return false end
  local slot=r.parent:AddChild(r.node);slot:SetAnchors(r.anchors);slot:SetOffsets(r.offsets)
  local z=r.z
  -- Reparenting appends at the end. Equal-Z siblings would then be covered by
  -- the opaque background, so restore it below the original screen content.
  if r.background then
   for i=0,r.parent:GetChildrenCount()-1 do local child=r.parent:GetChildAt(i)
    if child:GetAddress()~=r.node:GetAddress()then z=math.min(z,child.Slot:GetZOrder()-1)end
   end
  end
  slot:SetAlignment(r.alignment);slot:SetZOrder(z);slot:SetAutoSize(r.auto);return true
 end
 return api
end
return M
