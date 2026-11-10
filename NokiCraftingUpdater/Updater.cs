using System;
using System.IO;
using System.Net;
using System.Text;
using System.Text.RegularExpressions;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using System.Threading.Tasks;

static class Program {
 [STAThread] static void Main(){Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);Application.Run(new Updater());}
}
sealed class Updater : Form {
 ComboBox region=new ComboBox(),ruleset=new ComboBox(),faction=new ComboBox();
 TextBox folder=new TextBox(); Label status=new Label(); Button update=new Button(); CheckBox auto=new CheckBox(); Timer timer=new Timer();
 bool loading=true;
 string cacheDir=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NokiCraftingUpdater");
 string settings { get { return Path.Combine(cacheDir,"settings.txt"); } }
 public Updater(){
  Text="Noki Crafting Updater";ClientSize=new Size(590,315);FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;StartPosition=FormStartPosition.CenterScreen;
  Controls.Add(new Label{Text="AHledger market data for Noki Crafting",Left=20,Top=15,Width=540,Height=24,Font=new Font(Font,FontStyle.Bold)});
  AddLabel("Region",20,53);AddLabel("Ruleset",175,53);AddLabel("Faction",365,53);
  Setup(region,20,75,140,new[]{"US","EU","CN"});Setup(ruleset,175,75,175,new[]{"Normal","PvP","RP","RP PvP"});Setup(faction,365,75,200,new[]{"Alliance","Horde"});
  AddLabel("NokiCrafting addon folder",20,118);folder.SetBounds(20,141,445,25);folder.Text=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),@"World of Warcraft\_forever_\Interface\AddOns\NokiCrafting");Controls.Add(folder);
  Button browse=new Button{Text="Browse",Left=475,Top=139,Width=90,Height=27};browse.Click+=(s,e)=>{using(var dialog=new FolderBrowserDialog()){dialog.Description="Select your NokiCrafting addon folder";if(dialog.ShowDialog()==DialogResult.OK)folder.Text=dialog.SelectedPath;}};Controls.Add(browse);
  update.Text="Update now";update.SetBounds(20,183,145,32);update.Click+=async(s,e)=>await RunUpdate();Controls.Add(update);
  auto.Text="Update every 30 minutes while open";auto.SetBounds(185,188,300,24);auto.CheckedChanged+=(s,e)=>{timer.Enabled=auto.Checked;SaveSettings();};Controls.Add(auto);
  status.SetBounds(20,227,550,72);status.Text="Choose your market, then click Update now. Reload the game after an update.";Controls.Add(status);
  timer.Interval=30*60*1000;timer.Tick+=async(s,e)=>await RunUpdate(); LoadSettings(); loading=false;
 }
 void AddLabel(string text,int x,int y){Controls.Add(new Label{Text=text,Left=x,Top=y,Width=180,Height=20});}
 void Setup(ComboBox box,int x,int y,int w,string[] items){box.SetBounds(x,y,w,25);box.DropDownStyle=ComboBoxStyle.DropDownList;box.Items.AddRange(items);box.SelectedIndex=0;box.SelectedIndexChanged+=(s,e)=>SaveSettings();Controls.Add(box);}
 string MarketRegion(){return region.SelectedItem.ToString().ToLowerInvariant();}
 string Ruleset(){return ruleset.SelectedItem.ToString().ToLowerInvariant().Replace(" ","");}
 string Faction(){return faction.SelectedItem.ToString().ToLowerInvariant();}
 void SaveSettings(){try{if(loading)return;if(region.SelectedItem==null||ruleset.SelectedItem==null||faction.SelectedItem==null)return;Directory.CreateDirectory(cacheDir);File.WriteAllLines(settings,new[]{region.SelectedIndex.ToString(),ruleset.SelectedIndex.ToString(),faction.SelectedIndex.ToString(),folder.Text,auto.Checked.ToString()});}catch{}}
 void LoadSettings(){try{if(!File.Exists(settings))return;string[] a=File.ReadAllLines(settings);if(a.Length<5)return;int n;if(int.TryParse(a[0],out n)&&n>=0&&n<region.Items.Count)region.SelectedIndex=n;if(int.TryParse(a[1],out n)&&n>=0&&n<ruleset.Items.Count)ruleset.SelectedIndex=n;if(int.TryParse(a[2],out n)&&n>=0&&n<faction.Items.Count)faction.SelectedIndex=n;if(a[3].Length>0)folder.Text=a[3];bool v;if(bool.TryParse(a[4],out v))auto.Checked=v;}catch{}}
 async Task RunUpdate(){
  update.Enabled=false;timer.Stop();status.Text="Downloading market data...";
  string reg=MarketRegion(),rule=Ruleset(),fact=Faction(),dir=folder.Text.Trim();SaveSettings();
  try{int count=await Task.Run(()=>FetchAndWrite(reg,rule,fact,dir));status.Text="Updated "+count+" items for "+rule+" / "+fact+" / "+reg+". Type /reload in game to load the update. Prices from AHledger (ahledger.com).";}
  catch(Exception e){status.Text="Update failed: "+e.Message+". Previous data was kept.";}
  finally{update.Enabled=true;if(auto.Checked)timer.Start();}
 }
 int FetchAndWrite(string reg,string rule,string fact,string dir){
  if(!File.Exists(Path.Combine(dir,"NokiCrafting.toc")))throw new Exception("Select the NokiCrafting addon folder");
  string toc=File.ReadAllText(Path.Combine(dir,"NokiCrafting.toc"));if(!toc.Contains("UpdaterData.lua"))throw new Exception("Update Noki Crafting to a version that supports the updater");
  string url="https://devvy.xyz/noki-crafting/market-data.php?region="+reg+"&ruleset="+rule+"&faction="+fact;
  ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
  string text;using(var client=new WebClient()){client.Headers.Add(HttpRequestHeader.UserAgent,"NokiCraftingUpdater/1.0");text=client.DownloadString(url);}
  string market="forever/"+rule+"/"+fact+"/"+reg; Validate(text,market);
  Directory.CreateDirectory(cacheDir);string key=rule+"_"+fact+"_"+reg;File.WriteAllText(Path.Combine(cacheDir,key+".txt"),text,new UTF8Encoding(false));
  var result=new StringBuilder("-- Data from AHledger (ahledger.com), fetched by Noki Crafting Updater.\nAHledgerData = AHledgerData or {}\n");int count=0;
  foreach(string file in Directory.GetFiles(cacheDir,"*.txt")){
   string name=Path.GetFileNameWithoutExtension(file);if(!Regex.IsMatch(name,@"^(normal|pvp|rp|rppvp)_(alliance|horde)_(us|eu|cn)$"))continue;
   string[] parts=name.Split('_');string m="forever/"+parts[0]+"/"+parts[1]+"/"+parts[2];string item=File.ReadAllText(file);string[] parsed=Validate(item,m);if(m==market)count=int.Parse(parsed[2]);
   result.Append("if not AHledgerData[\"").Append(m).Append("\"] or (AHledgerData[\"").Append(m).Append("\"].updated or 0) < ").Append(parsed[1]).Append(" then\nAHledgerData[\"").Append(m).Append("\"]={updated=").Append(parsed[1]).Append(",count=").Append(parsed[2]).Append(",text=[==[\n").Append(parsed[3]).Append("\n]==]}\nend\n");
  }
  string target=Path.Combine(dir,"UpdaterData.lua"),tmp=Path.Combine(dir,"UpdaterData.lua.tmp");try{File.WriteAllText(tmp,result.ToString(),new UTF8Encoding(false));if(File.Exists(target))File.Replace(tmp,target,null);else File.Move(tmp,target);}finally{if(File.Exists(tmp))File.Delete(tmp);}return count;
 }
 static string[] Validate(string text,string market){
  if(text.Length>2000000)throw new Exception("Data is too large");text=text.Replace("\r","");int i=text.IndexOf('\n');if(i<0)throw new Exception("Invalid AHledger table");string[] h=text.Substring(0,i).Split('|');long ts;int count;
  if(h.Length!=4||h[0]!="AHL1"||h[1]!=market||!long.TryParse(h[2],out ts)||ts<=0||ts>DateTimeOffset.UtcNow.ToUnixTimeSeconds()+300||!int.TryParse(h[3],out count)||count<1||count>100000)throw new Exception("Invalid market or table header");
  string body=text.Substring(i+1).Trim();string[] lines=body.Split('\n');if(lines.Length!=count)throw new Exception("Incomplete market table");foreach(string row in lines)if(!Regex.IsMatch(row,@"^\d+(?::\d*){8}$"))throw new Exception("Invalid market row");return new[]{market,h[2],h[3],body};
 }
}
