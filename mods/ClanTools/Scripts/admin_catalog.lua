-- Exact packaged pickup paths from analysis/containers/package-paths.csv.
-- Names are English; no arbitrary class paths or quest pickups accepted.
local out = { items = {}, enemies = {} }
local labels=dofile(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')..'item_labels.lua')
local pickupRoot = '/Game/Gameplay/Blueprints/WorldElements/Pickups/BP_Pickup_'
for _, name in ipairs({
    'SmallHealingHerb', 'MediumHealingHerb', 'BigHealingHerb',
    'FullHealingHerb', 'SuperHealingHerb', 'SmallCatnip', 'MediumCatnip', 'BigCatnip',
    'AntidoteHerbPouch', 'CatThymePouch', 'CatnipPouch', 'ChamomilePouch',
    'ChestnutPouch', 'EyewortPouch', 'FishScalePouch', 'GingerRootPouch',
    'HealingHerbPouch', 'HerbSpicesPouch', 'LavenderPouch', 'PeppermintPouch',
    'SagePouch', 'ValerianRootPouch'
}) do
    out.items[#out.items + 1] = { id = name, label = (labels['Gameplay.Inventory.Consumable.'..name]or{}).name or name:gsub('(%l)(%u)', '%1 %2'),
        class = pickupRoot .. name .. '.BP_Pickup_' .. name .. '_C' }
end
-- Parsed DT_Combat_Generator: single-member fixed encounters with no dialogues.
-- Tag names and character types intentionally differ for TitanSnake/TitanBadger.
for _, e in ipairs({
    {'WeakMice','WeakMice',1}, {'Mice','Mice',6},
    {'WeakSquirrel','WeakSquirrel',1}, {'Squirrel','Squirrel',6},
    {'WeakRabbit','WeakRabbit',1}, {'Rabbit','Rabbit',6},
    {'WeakBird','WeakBird',1}, {'WeakRat','WeakRat',1},
    {'Snake','TitanSnake',11}, {'Badger','TitanBadger',11},
    {'TitanFox','TitanFox',11}, {'TitanDog','TitanDog',11}
}) do
    out.enemies[#out.enemies + 1] = {id=e[1],label=e[1]:gsub('(%l)(%u)','%1 %2')..' (Level '..e[3]..')',
        level=e[3], setupTag='Gameplay.Combat.Generator.Fixed.'..e[2]..'.01.L'..e[3]}
end
return out
