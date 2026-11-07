[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ProjectPath,
 [string]$CloneRoot='H:\DDM_Final_Project_Gate13R36H\v2',
 [Parameter(Mandatory=$true)][string]$VerificationOutputRoot,
 [switch]$BindingSmokeOnly
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$ProjectPath=[IO.Path]::GetFullPath($ProjectPath);$CloneRoot=[IO.Path]::GetFullPath($CloneRoot);$VerificationOutputRoot=[IO.Path]::GetFullPath($VerificationOutputRoot);$expected=[IO.Path]::GetFullPath('H:\DDM_Final_Project_Gate13R36H\v2')
if($CloneRoot-ne$expected){throw 'Clone root differs from the frozen v1 path.'};if($BindingSmokeOnly){Write-Output("BINDING-SMOKE-PASSED|Initialize-Gate13R36hLaneCopiesV2|$CloneRoot");exit 0}
if(Test-Path $CloneRoot){throw "Create-new clone root already exists: $CloneRoot"};if(@(Get-Process -Name Unity -ErrorAction SilentlyContinue).Count){throw 'Unity must be closed before lane copy creation.'};if(Test-Path (Join-Path $ProjectPath 'Temp\UnityLockfile')){throw 'Source Unity lock exists before lane copy creation.'}
foreach($formal in @('Research\FormalRuns\Gate13R_ProcessReuse_5pct\v1','Research\FormalRuns\Gate13R_36h_10pct_4Lane\v1')){if(Test-Path (Join-Path $ProjectPath $formal)){throw "Forbidden formal root exists: $formal"}}
$requiredResearchFiles=@(
 'Four_Algorithm_Fairness_and_Unified_Campaign_Specification.md','Scenario_IO_and_Planning_Workload_Specification.md','AStar_Repeated_Specification.md','DStar_Lite_Specification.md','Corrected_Full_Recompute_Flow_Field_Specification.md','Incremental_Dynamic_Flow_Field_Specification.md',
 'Gate13R_36h_Redesign_Pilot_Authorization.v1.json','Gate13R_36h_10pct_4Lane_Redesign_Specification.v1.md','Gate13R_36h_10pct_4Lane_Test_Design.v1.md','Gate13R_36h_10pct_4Lane_Readiness_Amendment.v1.json','Gate13R_36h_10pct_4Lane_PrePilot_Defect_Repair_Amendment.v2.json','Gate13R_36h_10pct_4Lane_Pilot_Plan.v2.json','Gate13R_36h_10pct_4Lane_Provenance.v2.json'
)
foreach($name in $requiredResearchFiles){if(-not(Test-Path (Join-Path $ProjectPath ('Research\'+$name)) -PathType Leaf)){throw "Required Research file missing: $name"}}
if(Test-Path $VerificationOutputRoot){throw 'Create-new clone verification output exists.'};New-Item -ItemType Directory -Path $VerificationOutputRoot -Force|Out-Null;New-Item -ItemType Directory -Path $CloneRoot -Force|Out-Null
if(-not('Gate13R36HardLinkNative' -as [type])){Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class Gate13R36HardLinkNative {
    [StructLayout(LayoutKind.Sequential)] public struct BY_HANDLE_FILE_INFORMATION {
        public uint FileAttributes; public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime; public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
        public uint VolumeSerialNumber; public uint FileSizeHigh; public uint FileSizeLow; public uint NumberOfLinks;
        public uint FileIndexHigh; public uint FileIndexLow;
    }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    public static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetFileInformationByHandle(SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION info);
}
'@}
function Get-HardLinkCount([string]$Path){$handle=[Gate13R36HardLinkNative]::CreateFile($Path,0,7,[IntPtr]::Zero,3,0,[IntPtr]::Zero);if($handle.IsInvalid){throw "Cannot open file for hard-link audit: $Path (Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"};try{$info=New-Object Gate13R36HardLinkNative+BY_HANDLE_FILE_INFORMATION;if(-not[Gate13R36HardLinkNative]::GetFileInformationByHandle($handle,[ref]$info)){throw "Cannot query hard-link count: $Path (Win32 $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"};return [uint32]$info.NumberOfLinks}finally{$handle.Dispose()}}
function Invoke-Robo([string]$Source,[string]$Destination){New-Item -ItemType Directory -Path $Destination -Force|Out-Null;&robocopy.exe $Source $Destination /E /COPY:DAT /DCOPY:DAT /R:2 /W:1 /XJ /NFL /NDL /NP /NJH /NJS|Out-Null;$code=$LASTEXITCODE;if($code-gt7){throw "Robocopy failed ($code): $Source -> $Destination"}}
foreach($lane in 1..4){
 $laneRoot=Join-Path $CloneRoot ('lane-{0:D2}'-f$lane);New-Item -ItemType Directory -Path $laneRoot -Force|Out-Null
 foreach($folder in @('Assets','Packages','ProjectSettings','Library')){Invoke-Robo (Join-Path $ProjectPath $folder) (Join-Path $laneRoot $folder)}
 Invoke-Robo (Join-Path $ProjectPath 'Research\FormalScenarios\Gate11R_5pct\v1') (Join-Path $laneRoot 'Research\FormalScenarios\Gate11R_5pct\v1')
 Invoke-Robo (Join-Path $ProjectPath 'Research\PlayableExperiments\Gate11R_5pct\v1') (Join-Path $laneRoot 'Research\PlayableExperiments\Gate11R_5pct\v1')
 New-Item -ItemType Directory -Path (Join-Path $laneRoot 'Research') -Force|Out-Null
 foreach($name in $requiredResearchFiles){Copy-Item -LiteralPath (Join-Path $ProjectPath ('Research\'+$name)) -Destination (Join-Path $laneRoot ('Research\'+$name))}
}
$scientificRoots=@('Assets','Packages','ProjectSettings','Research\FormalScenarios\Gate11R_5pct\v1','Research\PlayableExperiments\Gate11R_5pct\v1');$sourceFiles=New-Object Collections.Generic.List[object]
foreach($relativeRoot in $scientificRoots){$full=Join-Path $ProjectPath $relativeRoot;foreach($file in Get-ChildItem -LiteralPath $full -Recurse -File -Force){$relative=$file.FullName.Substring($ProjectPath.TrimEnd('\').Length+1).Replace('\','/');$sourceFiles.Add([pscustomobject][ordered]@{relativePath=$relative;bytes=[long]$file.Length;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()})}}
foreach($name in $requiredResearchFiles){$path=Join-Path $ProjectPath ('Research\'+$name);$sourceFiles.Add([pscustomobject][ordered]@{relativePath=('Research/'+$name);bytes=[long](Get-Item $path).Length;sha256=(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()})}
$sourceFiles=@($sourceFiles|Sort-Object relativePath -Unique);$laneManifests=New-Object Collections.Generic.List[object]
foreach($lane in 1..4){$laneRoot=Join-Path $CloneRoot ('lane-{0:D2}'-f$lane);$errors=New-Object Collections.Generic.List[string];$hardLinkedFiles=New-Object Collections.Generic.List[string];foreach($entry in $sourceFiles){$path=Join-Path $laneRoot ([string]$entry.relativePath).Replace('/','\');if(-not(Test-Path $path -PathType Leaf)){$errors.Add("Missing: $($entry.relativePath)");continue};if([long](Get-Item $path).Length-ne[long]$entry.bytes-or(Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()-ne[string]$entry.sha256){$errors.Add("Hash/length mismatch: $($entry.relativePath)")};if((Get-HardLinkCount $path)-ne1){$hardLinkedFiles.Add([string]$entry.relativePath)}}
 $reparse=@();foreach($relativeRoot in $scientificRoots){$reparse+=@(Get-ChildItem -LiteralPath (Join-Path $laneRoot $relativeRoot) -Recurse -Force|Where-Object{($_.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0}|Select-Object -ExpandProperty FullName)};if($reparse.Count){$errors.Add("Scientific tree contains $($reparse.Count) reparse points.")}
 if($hardLinkedFiles.Count){$errors.Add("Scientific tree contains $($hardLinkedFiles.Count) files with hard-link count other than one.")}
 $manifest=[ordered]@{schemaVersion=1;manifestKind='gate13r-36h-isolated-lane-copy-manifest-v2';createdAtUtc=[DateTime]::UtcNow.ToString('o');lane=$lane;sourceProjectPath=$ProjectPath;laneProjectPath=$laneRoot;scientificFileCount=$sourceFiles.Count;scientificBytes=[long](($sourceFiles|Measure-Object bytes -Sum).Sum);libraryBytes=[long](Get-ChildItem (Join-Path $laneRoot 'Library') -Recurse -File -Force|Measure-Object Length -Sum).Sum;reparsePointCount=$reparse.Count;hardLinkedScientificFileCount=$hardLinkedFiles.Count;hardLinkedScientificFiles=$hardLinkedFiles.ToArray();errors=$errors.ToArray();passed=$errors.Count-eq0};$manifestPath=Join-Path $VerificationOutputRoot ('lane-{0:D2}-copy-manifest.json'-f$lane);$json=($manifest|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText($manifestPath,$json,(New-Object Text.UTF8Encoding($false,$true)));$laneManifests.Add([pscustomobject]@{lane=$lane;path=$manifestPath;sha256=(Get-FileHash $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant();passed=$manifest.passed});if(-not$manifest.passed){throw "Lane $lane scientific-copy audit failed: $($errors-join'; ')"}}
$summary=[ordered]@{schemaVersion=1;summaryKind='gate13r-36h-four-isolated-project-copies-v2';completedAtUtc=[DateTime]::UtcNow.ToString('o');cloneRoot=$CloneRoot;laneCount=4;scientificFileCount=$sourceFiles.Count;scientificBytes=[long](($sourceFiles|Measure-Object bytes -Sum).Sum);laneManifests=$laneManifests.ToArray();formalCampaign=$false;passed=$true};$json=($summary|ConvertTo-Json -Depth 20).Replace("`r`n","`n").Replace("`r","`n")+"`n";[IO.File]::WriteAllText((Join-Path $VerificationOutputRoot 'summary.json'),$json,(New-Object Text.UTF8Encoding($false,$true)));$summary|ConvertTo-Json -Depth 20
