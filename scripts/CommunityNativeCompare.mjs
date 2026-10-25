import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
function sections(path){
 const b=fs.readFileSync(path),pe=b.readUInt32LE(60),n=b.readUInt16LE(pe+6),s=pe+24+b.readUInt16LE(pe+20),out={};
 for(let i=0;i<n;i++){const p=s+i*40,name=b.toString('ascii',p,p+8).replace(/\0/g,''),size=b.readUInt32LE(p+16),offset=b.readUInt32LE(p+20);out[name]=hash(b.subarray(offset,offset+size));}
 return {sha256:hash(b),sections:out};
}
const rows=[["workshop.dll","workshop.c"],['clanparty.dll','mods/ClanParty/native/bridge.c','party-reconcile/clanparty-next.dll'],['clanappearance-skins-v8.dll','appearance_bridge.c'],['item-feedback-v5.dll','item_feedback.c'],['crafting-v4.dll','crafting.c'],['admin-heal.dll','admin_heal.c','admin-heal-next.dll'],['admin-progression-v2.dll','admin_progression.c'],['admin-sandbox.dll','admin_sandbox.c'],['admin-inventory.dll','admin_inventory.c'],['admin-quests-v5.dll','admin_quests.c'],['follower-appearance-v4.dll','follower_appearance.c'],['settings-bridge-v2.dll','settings_bridge.c'],['settings-remap-v3.dll','settings_remap.c'],['enemy-cleanup.dll','enemy_cleanup.c']];
const inputPaths=[...new Set([...rows.map(([,s])=>s.includes('/')?s:'mods/ClanTools/native/'+s),...fs.readdirSync('mods/ClanTools/native').filter(n=>n.endsWith('.h')).map(n=>'mods/ClanTools/native/'+n)])];
const initialHashes=new Map(inputPaths.map(p=>[p,hash(fs.readFileSync(p))]));
const results=rows.map(([name,source,rebuildName=name])=>{
 if(!source.includes('/'))source='mods/ClanTools/native/'+source;
 const output=path.resolve('analysis/community/native-verify/'+rebuildName);fs.mkdirSync(path.dirname(output),{recursive:true});
 const args=['cc','-shared','-O2','-Wall','-Wextra',path.resolve(source),'-o',output];if(name==='clanparty.dll')args.push('-lshell32');
 const build=spawnSync(process.env.CLANTOOLS_ZIG || path.resolve('tools/compiler/zig-x86_64-windows-0.15.2/zig.exe'),args,{encoding:'utf8',windowsHide:true});
 if(build.status!==0)throw new Error(`Fresh build failed: ${name}\n${build.stdout}\n${build.stderr}`);
 const original=sections('mods/ClanTools/bin/'+name),rebuilt=sections('analysis/community/native-verify/'+rebuildName);
 const changed=[...new Set([...Object.keys(original.sections),...Object.keys(rebuilt.sections)])].filter(k=>original.sections[k]!==rebuilt.sections[k]);
 return {name,source,rebuildName,sourceSha256:hash(fs.readFileSync(source)),original,rebuilt,changedSections:changed,productionSectionsMatch:changed.every(k=>k==='.buildid')};
});
for(const p of inputPaths)if(initialHashes.get(p)!==hash(fs.readFileSync(p)))throw new Error('Source changed during audit: '+p);
const headers=fs.readdirSync('mods/ClanTools/native').filter(n=>n.endsWith('.h')).map(n=>{const path='mods/ClanTools/native/'+n;return{path,sha256:hash(fs.readFileSync(path))}});
fs.writeFileSync('analysis/community/native-verify/source-binary-audit.json',JSON.stringify({createdUtc:new Date().toISOString(),note:'Isolated fresh recompilation using production build flags. Ignore only linker .buildid; all executable, readonly data, runtime data, exception/unwind, TLS and relocation sections must match.',headers,results},null,2)+'\n');
for(const r of results)console.log(`${r.productionSectionsMatch?'PASS':'MISMATCH'} ${r.name}: ${r.changedSections.join(',')||'byte-identical sections'}`);
if(results.some(r=>!r.productionSectionsMatch))process.exitCode=1;


