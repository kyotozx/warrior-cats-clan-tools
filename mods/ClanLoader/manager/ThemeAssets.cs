using System;
using System.IO;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// Read only the exact, hash-verified texture/font blocks listed in the recipe.
// Game artwork is cached locally, never included in a release package.
public static class ClanThemeAssets {
 public class Block { public long offset; public int size,raw; public bool compressed; public string sha256; }
 public class Asset { public string name,source,sha256,format; public int skip,length,width,height,dataOffset; public bool font; public Block[] blocks; }
 public class Recipe { public int schema; public string build; public Asset[] assets; }
 public static volatile string Progress="Preparing original game artwork...";
 public static Task<string> Begin(string game,string root) { return Task.Factory.StartNew(()=>Prepare(game,root)); }
 static string Hash(byte[] b) { using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(b)).Replace("-","").ToLowerInvariant(); }
 static void Require(bool value,string message) {if(!value)throw new InvalidDataException(message);}
 public static string Prepare(string game,string root) {
  string paks=Path.Combine(game,"Wrc/Content/Paks"),json=File.ReadAllText(Path.Combine(root,"theme-assets.json"));
  var recipe=new JavaScriptSerializer().Deserialize<Recipe>(json);
  Require(recipe.schema==1&&recipe.assets.Length<=24,"Unsupported theme recipe.");
  string fingerprint=Path.GetFullPath(paks)+json;
  foreach(string source in new[]{"pakchunk0-Windows.pak","pakchunk0-Windows.ucas","pakchunk0-Windows.utoc"}){
   var info=new FileInfo(Path.Combine(paks,source));Require(info.Exists,"Game artwork not found. Choose the installed game folder.");fingerprint+=info.Length+":"+info.LastWriteTimeUtc.Ticks;
  }
  string cache=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"ClanTools/ThemeCache/"+Hash(Encoding.UTF8.GetBytes(fingerprint)).Substring(0,24));
  Directory.CreateDirectory(cache);
  string marker=Path.Combine(cache,"complete.json");
  if(File.Exists(marker)){
   try {var checks=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,string>>(File.ReadAllText(marker));bool valid=true;
    foreach(var check in checks){string f=Path.Combine(cache,Path.GetFileName(check.Key));if(!File.Exists(f)||Hash(File.ReadAllBytes(f))!=check.Value){valid=false;break;}}
    if(valid&&checks.Count==recipe.assets.Length){Progress="Original game artwork loaded.";return cache;}
   }catch{}
  }
  string scratch=Path.Combine(cache,"work-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(scratch);
  var outputHashes=new System.Collections.Generic.Dictionary<string,string>();
  try {
   for(int index=0;index<recipe.assets.Length;index++){
    Asset a=recipe.assets[index];Progress="Loading game artwork  "+(index+1)+" / "+recipe.assets.Length;
    Require(a.source=="pakchunk0-Windows.pak"||a.source=="pakchunk0-Windows.ucas","Invalid asset source.");
    Require(System.Text.RegularExpressions.Regex.IsMatch(a.name,"^[a-z]+$")&&a.length>0&&a.length<32*1024*1024,"Invalid asset bounds.");
    byte[] raw;
    using(var source=File.OpenRead(Path.Combine(paks,a.source)))using(var joined=new MemoryStream()){
     foreach(Block b in a.blocks){
      Require(b.offset>=0&&b.size>0&&b.size<=1024*1024&&b.raw>0&&b.raw<=1024*1024&&b.offset+b.size<=source.Length,"Invalid asset block.");
      source.Position=b.offset;byte[] data=new byte[b.size];int got=0;while(got<data.Length){int read=source.Read(data,got,data.Length-got);if(read==0)throw new EndOfStreamException();got+=read;}
      Require(Hash(data)==b.sha256,"Game artwork differs from the supported build. Update Clan Loader and verify your game installation.");
      if(b.compressed){
       string input=Path.Combine(scratch,"block.ooz"),output=Path.Combine(scratch,"block.raw");
       using(var writer=new BinaryWriter(File.Create(input))){writer.Write((long)b.raw);writer.Write(data);}
       var start=new ProcessStartInfo(Path.Combine(root,"theme-tools/ooz.exe"),"-d -f \""+input+"\" \""+output+"\""){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true};
       using(var process=Process.Start(start)){var errorTask=process.StandardError.ReadToEndAsync();if(!process.WaitForExit(15000)){process.Kill();throw new IOException("Artwork decoder timed out.");}Require(process.ExitCode==0,"Could not decode game artwork.");errorTask.Wait();}
       data=File.ReadAllBytes(output);Require(data.Length==b.raw,"Decoded artwork size mismatch.");
      }else Require(data.Length==b.raw,"Raw artwork size mismatch.");
      joined.Write(data,0,data.Length);
     }
     Require(a.skip>=0&&(long)a.skip+a.length<=joined.Length,"Incomplete artwork.");raw=new byte[a.length];Buffer.BlockCopy(joined.ToArray(),a.skip,raw,0,a.length);
    }
    Require(Hash(raw)==a.sha256,"Decoded artwork integrity check failed.");
    string name=a.name+(a.font?".ttf":".png"),dest=Path.Combine(cache,name);
    if(a.font){int length=BitConverter.ToInt32(raw,0);Require(length>100&&length<=raw.Length-4,"Invalid font data.");byte[] font=new byte[length];Buffer.BlockCopy(raw,4,font,0,length);File.WriteAllBytes(dest,font);}
    else SaveTexture(raw,a,dest);
    outputHashes[name]=Hash(File.ReadAllBytes(dest));
   }
   File.WriteAllText(marker,new JavaScriptSerializer().Serialize(outputHashes));
  }finally{if(Directory.Exists(scratch))Directory.Delete(scratch,true);}
  Progress="Original game artwork loaded.";return cache;
 }
 static int[] Color565(int v){return new[]{((v>>11)&31)*255/31,((v>>5)&63)*255/63,(v&31)*255/31};}
 static void SaveTexture(byte[] data,Asset a,string dest){
  Require(a.width>0&&a.width<=4096&&a.height>0&&a.height<=4096,"Invalid texture dimensions.");
  byte[] rgba=new byte[a.width*a.height*4];int p=a.dataOffset;
  Require(a.format=="PF_DXT1"||a.format=="PF_DXT5","Unsupported texture format.");bool dxt5=a.format=="PF_DXT5";
  int expected=((a.width+3)/4)*((a.height+3)/4)*(dxt5?16:8);Require(p>=0&&p+expected<=data.Length,"Truncated texture.");
  for(int by=0;by<a.height;by+=4)for(int bx=0;bx<a.width;bx+=4){
   int[] alpha=new int[8];ulong abits=0;
   if(dxt5){alpha[0]=data[p];alpha[1]=data[p+1];for(int k=0;k<6;k++)abits|=((ulong)data[p+2+k])<<(8*k);
    if(alpha[0]>alpha[1])for(int k=2;k<8;k++)alpha[k]=((8-k)*alpha[0]+(k-1)*alpha[1])/7;
    else{for(int k=2;k<6;k++)alpha[k]=((6-k)*alpha[0]+(k-1)*alpha[1])/5;alpha[6]=0;alpha[7]=255;}p+=8;
   }
   int v0=BitConverter.ToUInt16(data,p),v1=BitConverter.ToUInt16(data,p+2);int[][] c=new[]{Color565(v0),Color565(v1),new int[3],new int[3]};
   for(int k=0;k<3;k++){c[2][k]=(v0>v1||dxt5)?(2*c[0][k]+c[1][k])/3:(c[0][k]+c[1][k])/2;c[3][k]=(v0>v1||dxt5)?(c[0][k]+2*c[1][k])/3:0;}
   uint bits=BitConverter.ToUInt32(data,p+4);p+=8;
   for(int i=0;i<16;i++){int x=bx+i%4,y=by+i/4;if(x>=a.width||y>=a.height)continue;int ci=(int)((bits>>(i*2))&3),ai=dxt5?alpha[(int)((abits>>(i*3))&7)]:((ci==3&&v0<=v1)?0:255),o=(y*a.width+x)*4;
    bool mask=a.name=="button"||a.name=="noise"||a.name=="base"||a.name=="line";
    rgba[o]=(byte)(mask?255:c[ci][2]);rgba[o+1]=(byte)(mask?255:c[ci][1]);rgba[o+2]=(byte)(mask?255:c[ci][0]);rgba[o+3]=(byte)(mask?ai*c[ci][0]/255:ai);
   }
  }
  var bitmap=BitmapSource.Create(a.width,a.height,96,96,PixelFormats.Bgra32,null,rgba,a.width*4);bitmap.Freeze();
  var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var stream=File.Create(dest))encoder.Save(stream);
 }
}
