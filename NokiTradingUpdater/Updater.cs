using System;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using System.Threading.Tasks;
using System.IO.Compression;
using System.Diagnostics;

static class Program {
 [STAThread] static void Main(){Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new Updater());}
}
sealed class Updater : Form {
 ComboBox region=new ComboBox(),ruleset=new ComboBox(),faction=new ComboBox();
 TextBox folder=new TextBox(); Label status=new Label(); Button update=new Button(); CheckBox auto=new CheckBox(), notify=new CheckBox(); Timer timer=new Timer(), addonTimer=new Timer();
 bool loading=true; string availableVersion, availableCommit, lastNotifiedVersion; Button installAddon=new Button(); Label versionStatus=new Label();
 string cacheDir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NokiTradingUpdater");
 string settings { get { return Path.Combine(cacheDir,"settings.txt"); } }
 public Updater(){
  Text="Noki Trading Updater";ClientSize=new Size(590,460);FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
  Controls.Add(new Label{Text="AHledger market data for Noki Market",Left=20,Top=15,Width=540,Height=24,Font=new Font(Font,FontStyle.Bold)});
  AddLabel("Region",20,53);AddLabel("Ruleset",175,53);AddLabel("Faction",365,53);
  Setup(region,20,75,140,new[]{"US","EU","CN"});Setup(ruleset,175,75,175,new[]{"Normal","PvP","RP","RP PvP"});Setup(faction,365,75,200,new[]{"Alliance","Horde"});
  AddLabel("NokiTrading addon folder",20,118);folder.SetBounds(20,141,445,25);folder.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),@"World of Warcraft\_forever_\Interface\AddOns\NokiTrading");Controls.Add(folder);
  Button browse=new Button{Text="Browse",Left=475,Top=139,Width=90,Height=27};browse.Click+=(s,e)=>{using(var dialog=new FolderBrowserDialog()){dialog.Description="Select your NokiTrading addon folder";if(dialog.ShowDialog()==DialogResult.OK)folder.Text=dialog.SelectedPath;}};Controls.Add(browse);
  update.Text="Update now";update.SetBounds(20,183,145,32);update.Click+=async(s,e)=>await RunUpdate();Controls.Add(update);
  auto.Text="Update every 30 minutes while open";auto.SetBounds(185,188,300,24);auto.CheckedChanged+=(s,e)=>{timer.Enabled=auto.Checked;SaveSettings();};Controls.Add(auto);
  status.SetBounds(20,227,550,72);status.Text="Choose your market, then click Update now. Reload the game after an update.";Controls.Add(status);
  
  versionStatus.SetBounds(20,300,550,34);versionStatus.Text="Addon update check has not run.";Controls.Add(versionStatus);
  var checkAddon=new Button{Text="Check addon updates",Left=20,Top=341,Width=150,Height=30};checkAddon.Click+=async(s,e)=>await CheckAddon();Controls.Add(checkAddon);
  installAddon.Text="Install addon update";installAddon.SetBounds(180,341,150,30);installAddon.Enabled=false;installAddon.Click+=async(s,e)=>await InstallAddon();Controls.Add(installAddon);
  var fallback=new LinkLabel{Text="Open GitHub repository",Left=345,Top=349,Width=190,Height=22};fallback.LinkClicked+=(s,e)=>OpenDownloadPage();Controls.Add(fallback);
  notify.Text="Notify me when an addon update is ready";notify.SetBounds(20,383,340,24);notify.CheckedChanged+=(s,e)=>SaveSettings();Controls.Add(notify);
  var migrate=new Button{Text="Migrate old data",Left=20,Top=416,Width=150,Height=30};migrate.Click+=(s,e)=>MigrateBetaData();Controls.Add(migrate);
  timer.Interval=30*60*1000;timer.Tick+=async(s,e)=>await RunUpdate(); addonTimer.Interval=30*60*1000;addonTimer.Tick+=async(s,e)=>await CheckAddon();addonTimer.Start(); LoadSettings(); loading=false;
  Shown+=async(s,e)=>await CheckAddon();
 }
 void AddLabel(string text,int x,int y){Controls.Add(new Label{Text=text,Left=x,Top=y,Width=180,Height=20});}
 void Setup(ComboBox box,int x,int y,int w,string[] items){box.SetBounds(x,y,w,25);box.DropDownStyle=ComboBoxStyle.DropDownList;box.Items.AddRange(items);box.SelectedIndex=0;box.SelectedIndexChanged+=(s,e)=>SaveSettings();Controls.Add(box);}
 string MarketRegion(){return region.SelectedItem.ToString().ToLowerInvariant();}
 string Ruleset(){return ruleset.SelectedItem.ToString().ToLowerInvariant().Replace(" ","");}
 string Faction(){return faction.SelectedItem.ToString().ToLowerInvariant();}
 void SaveSettings(){try{if(loading)return;if(region.SelectedItem==null||ruleset.SelectedItem==null||faction.SelectedItem==null)return;Directory.CreateDirectory(cacheDir);File.WriteAllLines(settings,new[]{region.SelectedIndex.ToString(),ruleset.SelectedIndex.ToString(),faction.SelectedIndex.ToString(),folder.Text,auto.Checked.ToString(),notify.Checked.ToString()});}catch{}}
 void LoadSettings(){try{if(!File.Exists(settings))return;string[] a=File.ReadAllLines(settings);if(a.Length<5)return;int n;if(int.TryParse(a[0],out n)&&n>=0&&n<region.Items.Count)region.SelectedIndex=n;if(int.TryParse(a[1],out n)&&n>=0&&n<ruleset.Items.Count)ruleset.SelectedIndex=n;if(int.TryParse(a[2],out n)&&n>=0&&n<faction.Items.Count)faction.SelectedIndex=n;if(a[3].Length>0)folder.Text=a[3];bool v;if(bool.TryParse(a[4],out v))auto.Checked=v;if(a.Length>5&&bool.TryParse(a[5],out v))notify.Checked=v;}catch{}}
 async Task RunUpdate(){
  update.Enabled=false;timer.Stop();status.Text="Downloading market data...";
  string reg=MarketRegion(),rule=Ruleset(),fact=Faction(),dir=folder.Text.Trim();SaveSettings();
  try{int count=await Task.Run(()=>FetchAndWrite(reg,rule,fact,dir));status.Text="Updated "+count+" items for "+rule+" / "+fact+" / "+reg+". Type /reload in game to load the update. Prices from AHledger (ahledger.com).";}
  catch(Exception e){status.Text="Update failed: "+e.Message+". Previous data was kept.";}
  finally{update.Enabled=true;if(auto.Checked)timer.Start();}
 }
 int FetchAndWrite(string reg,string rule,string fact,string dir){
  string tocName="NokiTrading.toc";
  if(!File.Exists(Path.Combine(dir,tocName)))throw new Exception("Select the NokiTrading addon folder");
  string toc=File.ReadAllText(Path.Combine(dir,tocName));if(!toc.Contains("UpdaterData.lua"))throw new Exception("The addon does not support market updates");
  string url="https://devvy.xyz/noki-crafting/market-data.php?region="+reg+"&ruleset="+rule+"&faction="+fact;
  ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
  string text;using(var client=new WebClient()){client.Headers.Add(HttpRequestHeader.UserAgent,"NokiTradingUpdater/1.0");text=client.DownloadString(url);}
  string market="forever/"+rule+"/"+fact+"/"+reg; Validate(text,market);
  Directory.CreateDirectory(cacheDir);string key=rule+"_"+fact+"_"+reg;File.WriteAllText(Path.Combine(cacheDir,key+".txt"),text,new UTF8Encoding(false));
  var result=new StringBuilder("-- Data from AHledger (ahledger.com), fetched by Noki Trading Updater.\nNokiUnifiedTables = NokiUnifiedTables or {}\n");int count=0;
  foreach(string file in Directory.GetFiles(cacheDir,"*.txt")){
   string name=Path.GetFileNameWithoutExtension(file);if(!Regex.IsMatch(name,@"^(normal|pvp|rp|rppvp)_(alliance|horde)_(us|eu|cn)$"))continue;
   string[] parts=name.Split('_');string m="forever/"+parts[0]+"/"+parts[1]+"/"+parts[2];string item=File.ReadAllText(file);string[] parsed=Validate(item,m);if(m==market)count=int.Parse(parsed[2]);
   result.Append("if not NokiUnifiedTables[\"").Append(m).Append("\"] or (NokiUnifiedTables[\"").Append(m).Append("\"].updated or 0) < ").Append(parsed[1]).Append(" then\nNokiUnifiedTables[\"").Append(m).Append("\"]={updated=").Append(parsed[1]).Append(",count=").Append(parsed[2]).Append(",text=[==[\n").Append(parsed[3]).Append("\n]==]}\nend\n");
  }
  string target=Path.Combine(dir,"UpdaterData.lua"),tmp=Path.Combine(dir,"UpdaterData.lua.tmp");try{File.WriteAllText(tmp,result.ToString(),new UTF8Encoding(false));if(File.Exists(target))File.Replace(tmp,target,null);else File.Move(tmp,target);}finally{if(File.Exists(tmp))File.Delete(tmp);}return count;
 }
 static string[] Validate(string text,string market){
  if(text.Length>2000000)throw new Exception("Data is too large");text=text.Replace("\r","");int i=text.IndexOf('\n');if(i<0)throw new Exception("Invalid AHledger table");string[] h=text.Substring(0,i).Split('|');long ts;int count;
  if(h.Length!=4||h[0]!="AHL1"||h[1]!=market||!long.TryParse(h[2],out ts)||ts<=0||ts>DateTimeOffset.UtcNow.ToUnixTimeSeconds()+300||!int.TryParse(h[3],out count)||count<1||count>100000)throw new Exception("Invalid market or table header");
  string body=text.Substring(i+1).Trim();string[] lines=body.Split('\n');if(lines.Length!=count)throw new Exception("Incomplete market table");foreach(string row in lines)if(!Regex.IsMatch(row,@"^\d+(?::\d*){8}$"))throw new Exception("Invalid market row");return new[]{market,h[2],h[3],body};
 }

 void MigrateBetaData(){
  try{string message=MigrateSavedData(folder.Text.Trim());MessageBox.Show(message,"Noki Trading migration");}
  catch(Exception e){MessageBox.Show("Migration was not completed: "+e.Message,"Noki Trading migration");}
 }
 static string MigrateSavedData(string addonDir){
  if(Process.GetProcessesByName("Wow").Length>0||Process.GetProcessesByName("WowClassic").Length>0)throw new Exception("Close WoW before migrating saved data");
  string addon=Path.GetFullPath(addonDir);if(!File.Exists(Path.Combine(addon,"NokiTrading.toc")))throw new Exception("Select the NokiTrading addon folder");
  var addons=Directory.GetParent(addon);var iface=addons==null?null:addons.Parent;var game=iface==null?null:iface.Parent;
  if(addons==null||iface==null||game==null||!addons.Name.Equals("AddOns",StringComparison.OrdinalIgnoreCase)||!iface.Name.Equals("Interface",StringComparison.OrdinalIgnoreCase)||!game.Name.Equals("_forever_",StringComparison.OrdinalIgnoreCase))throw new Exception("The addon must be inside the Forever Interface/AddOns folder");
  string accounts=Path.Combine(game.FullName,"WTF","Account");int copied=0,skipped=0;
  if(Directory.Exists(accounts))foreach(string account in Directory.GetDirectories(accounts)){
   string saved=Path.Combine(account,"SavedVariables");if(!Directory.Exists(saved))continue;string target=Path.Combine(saved,"NokiTrading.lua");
   string unified=Path.Combine(saved,"NokiUnifiedBeta.lua");if(File.Exists(target)){skipped++;continue;}if(File.Exists(unified)){File.Copy(unified,target,false);copied++;continue;}
   var files=new List<string>();foreach(string name in new[]{"NokiTradingBeta.lua","NokiMarketBeta.lua","NokiCraftingBeta.lua"}){string path=Path.Combine(saved,name);if(File.Exists(path))files.Add(path);}
   if(files.Count==0)continue;if(File.Exists(target)){skipped++;continue;}
   var pieces=new List<string>();long size=0;foreach(string file in files){size+=new FileInfo(file).Length;if(size>50000000)throw new Exception("Saved data is unusually large; migrate it manually");string piece=File.ReadAllText(file);string name=Path.GetFileName(file);string from=name=="NokiTradingBeta.lua"?"NokiTradingBetaDB":name=="NokiMarketBeta.lua"?"NokiMarketBetaDB":"NokiCraftingBetaDB";string to=name=="NokiTradingBeta.lua"?"NokiUnifiedCoreDB":name=="NokiMarketBeta.lua"?"NokiUnifiedMarketDB":"NokiUnifiedCraftDB";var declaration=new Regex(@"(?m)^\s*"+from+@"\s*=");if(!declaration.IsMatch(piece))throw new Exception("Could not identify beta saved data in "+name);pieces.Add(declaration.Replace(piece,to+" =",1));}
   bool created=false;try{using(var stream=new FileStream(target,FileMode.CreateNew,FileAccess.Write,FileShare.None)){created=true;using(var writer=new StreamWriter(stream,new UTF8Encoding(false))){writer.WriteLine("-- Migrated from Noki beta saved variables; originals remain unchanged.");foreach(string piece in pieces){writer.WriteLine(piece);writer.WriteLine();}}}copied++;}catch{if(created&&File.Exists(target))try{File.Delete(target);}catch{}throw;}
  }
  string update=Path.Combine(addon,"UpdaterData.lua");string previous=Path.Combine(addons.FullName,"NokiUnifiedBeta","UpdaterData.lua");if(!File.Exists(previous))previous=Path.Combine(addons.FullName,"NokiCraftingBeta","UpdaterData.lua");
  bool copiedTable=false;if(File.Exists(previous)&&(!File.Exists(update)||File.ReadAllText(update).IndexOf("NokiUnifiedTables[",StringComparison.Ordinal)<0)){string data=File.ReadAllText(previous);if(data.IndexOf("NokiBetaTables[",StringComparison.Ordinal)>=0||data.IndexOf("NokiUnifiedTables[",StringComparison.Ordinal)>=0){data=data.Replace("NokiBetaTables","NokiUnifiedTables");File.WriteAllText(update,data,new UTF8Encoding(false));copiedTable=true;}}
  return "Migrated " + copied + " account(s). " + skipped + " account(s) already had unified data and were left unchanged." + (copiedTable ? " Market data was also copied." : "") + " Original beta files remain in place.";
 }
 const string CommitUrl="https://api.github.com/repos/PyNoki/nokiForever/commits/main";
 const string TocUrl="https://raw.githubusercontent.com/PyNoki/nokiForever/{0}/NokiTrading/NokiTrading.toc";
 const string ArchiveUrl="https://raw.githubusercontent.com/PyNoki/nokiForever/{0}/NokiTradingVersions/NokiTrading-{1}.zip";
 const string DownloadPage="https://github.com/PyNoki/nokiForever";
 static void OpenDownloadPage(){try{Process.Start(new ProcessStartInfo(DownloadPage){UseShellExecute=true});}catch{MessageBox.Show("Open this address in your browser:\n"+DownloadPage,"Download Noki Market");}}
 static string TocVersion(string text){var m=Regex.Match(text,@"(?m)^##\s*Version:\s*([^\r\n]+)");return m.Success?m.Groups[1].Value.Trim():null;}
 static int CompareVersion(string left,string right){
  var a=Regex.Match(left??"",@"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$");var b=Regex.Match(right??"",@"^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$");
  if(!a.Success||!b.Success)throw new Exception("Unsupported addon version format");
  for(int i=1;i<=3;i++){long x=long.Parse(a.Groups[i].Value),y=long.Parse(b.Groups[i].Value);if(x!=y)return x>y?1:-1;}
  string xPre=a.Groups[4].Value,yPre=b.Groups[4].Value;if(xPre==yPre)return 0;if(xPre=="")return 1;if(yPre=="")return -1;
  string[] xParts=xPre.Split('.'),yParts=yPre.Split('.');for(int i=0;i<Math.Max(xParts.Length,yParts.Length);i++){if(i>=xParts.Length)return -1;if(i>=yParts.Length)return 1;long x,y;bool xn=long.TryParse(xParts[i],out x),yn=long.TryParse(yParts[i],out y);int c=xn&&yn?x.CompareTo(y):xn?-1:yn?1:string.CompareOrdinal(xParts[i],yParts[i]);if(c!=0)return c>0?1:-1;}return 0;
 }
 static string DownloadText(string url){ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;using(var c=new WebClient()){c.Headers.Add(HttpRequestHeader.UserAgent,"NokiTradingUpdater/1.0");c.Headers.Add(HttpRequestHeader.CacheControl,"no-cache");return c.DownloadString(url);}}
 static string PublishedCommit(){string json=DownloadText(CommitUrl+"?check="+Guid.NewGuid().ToString("N"));var match=Regex.Match(json,"\\\"sha\\\"\\s*:\\s*\\\"([0-9a-fA-F]{40})\\\"");if(!match.Success)throw new Exception("No published commit was found");return match.Groups[1].Value.ToLowerInvariant();}
 async Task CheckAddon(){
  installAddon.Enabled=false;availableVersion=null;availableCommit=null;versionStatus.Text="Checking for addon updates...";string dir=folder.Text.Trim();
  try{string localPath=Path.Combine(dir,"NokiTrading.toc");if(!File.Exists(localPath))throw new Exception("Select the NokiTrading addon folder");string local=TocVersion(File.ReadAllText(localPath));var published=await Task.Run(()=>{string commit=PublishedCommit();return new[]{commit,TocVersion(DownloadText(string.Format(TocUrl,commit)))};});string remote=published[1];if(remote==null)throw new Exception("No published addon version was found");
   int cmp=CompareVersion(remote,local);if(cmp>0){availableVersion=remote;availableCommit=published[0];installAddon.Enabled=true;versionStatus.Text="New addon update detected: "+local+" to "+remote;if(notify.Checked&&lastNotifiedVersion!=remote){lastNotifiedVersion=remote;MessageBox.Show("A new addon update ("+remote+") is available. Click Install addon update to install it.","Noki Trading update");}}else versionStatus.Text="Addon is up to date ("+local+").";
  }catch(WebException e){var response=e.Response as HttpWebResponse;if(response!=null&&response.StatusCode==HttpStatusCode.NotFound)versionStatus.Text="No published addon update found (404). Market-data updates still work.";else versionStatus.Text="Could not check addon updates: "+e.Message+". Check the GitHub repository.";}
  catch(Exception e){versionStatus.Text="Could not check addon updates: "+e.Message+". Check the GitHub repository.";}
 }
 async Task InstallAddon(){
  if(availableVersion==null||availableCommit==null)return;string wanted=availableVersion,commit=availableCommit;string dir=folder.Text.Trim();installAddon.Enabled=false;versionStatus.Text="Downloading addon update...";
  try{await Task.Run(()=>{ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;byte[] archive;using(var c=new WebClient()){c.Headers.Add(HttpRequestHeader.UserAgent,"NokiTradingUpdater/1.0");archive=c.DownloadData(string.Format(ArchiveUrl,commit,Uri.EscapeDataString(wanted)));}InstallArchive(archive,dir,wanted);});versionStatus.Text="Addon updated to "+wanted+". Type /reload in game.";availableVersion=null;availableCommit=null;}
  catch(Exception e){versionStatus.Text="Addon update failed: "+e.Message+". Use the download link.";installAddon.Enabled=true;}
 }
 static void InstallArchive(byte[] archive,string dir,string wanted){
  if(archive==null||archive.Length>50000000)throw new Exception("Invalid or oversized archive");string target=Path.GetFullPath(dir);if(!File.Exists(Path.Combine(target,"NokiTrading.toc")))throw new Exception("Select the NokiTrading addon folder");
  string temp=Path.Combine(Path.GetTempPath(),"noki-addon-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);
  var entries=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);long bytes=0;
  try{using(var mem=new MemoryStream(archive))using(var zip=new ZipArchive(mem,ZipArchiveMode.Read)){
    string prefix=null;foreach(var entry in zip.Entries){var m=Regex.Match(entry.FullName,@"^(?:[^/]+/)?NokiTrading/NokiTrading\.toc$");if(m.Success){if(prefix!=null)throw new Exception("Duplicate addon folders");prefix=entry.FullName.Substring(0,entry.FullName.Length-"NokiTrading.toc".Length);}}
    if(prefix==null)throw new Exception("The download does not contain NokiTrading");
    foreach(var entry in zip.Entries){if(!entry.FullName.StartsWith(prefix,StringComparison.Ordinal)||entry.FullName.EndsWith("/"))continue;string relative=entry.FullName.Substring(prefix.Length).Replace('/',Path.DirectorySeparatorChar);if(relative.Equals("UpdaterData.lua",StringComparison.OrdinalIgnoreCase))continue;
     if(relative.Length==0||relative.IndexOf(':')>=0)throw new Exception("Unsafe archive path");string destination=Path.GetFullPath(Path.Combine(target,relative));string staged=Path.GetFullPath(Path.Combine(temp,relative));
     if(!destination.StartsWith(target+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)||!staged.StartsWith(temp+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new Exception("Unsafe archive path");
     bytes+=entry.Length;if(entry.Length>15000000||bytes>30000000)throw new Exception("Addon archive is too large");if(entries.ContainsKey(relative))throw new Exception("Duplicate archive path");Directory.CreateDirectory(Path.GetDirectoryName(staged));using(var input=entry.Open())using(var output=new FileStream(staged,FileMode.CreateNew)){input.CopyTo(output);}entries.Add(relative,staged);
    }
   }
   string stagedToc;if(!entries.TryGetValue("NokiTrading.toc",out stagedToc)||TocVersion(File.ReadAllText(stagedToc))!=wanted)throw new Exception("The published version changed; check again");
   string backup=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NokiTradingUpdater","Older versions",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N"));
   var written=new List<string>();try{foreach(var pair in entries){string path=Path.Combine(target,pair.Key);Directory.CreateDirectory(Path.GetDirectoryName(path));if(File.Exists(path)){string save=Path.Combine(backup,pair.Key);Directory.CreateDirectory(Path.GetDirectoryName(save));File.Copy(path,save,false);}written.Add(pair.Key);File.Copy(pair.Value,path,true);}}
   catch{foreach(string rel in written){string path=Path.Combine(target,rel),save=Path.Combine(backup,rel);try{if(File.Exists(save))File.Copy(save,path,true);else if(File.Exists(path))File.Delete(path);}catch{}}throw;}
  }finally{try{Directory.Delete(temp,true);}catch{}}
 }

}

