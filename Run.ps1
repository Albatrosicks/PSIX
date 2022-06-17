param($groups=$null,$hosts=$null,$templates=$null)

import-module ($PSScriptRoot +  ".\CoreLibrary.psm1")

# LOADING PLUGINS
$plugins = new-object System.Collections.Generic.List[object];
if ((Test-Path ("$PSScriptRoot\Plugins\")) -eq $true) {
    Get-ChildItem -Path "$PSScriptRoot\Plugins\" | %{ $plugins.Add($_.BaseName); }
}
for ($i = 0; $i -lt $plugins.Count; ++$i) {
    $pluginName = $plugins[$i].Trim();
    if ($pluginName -eq [string]::Empty -or $pluginName[0] -eq '#') { continue; }
    $plugins[$i] = (Get-Content -Path $PSScriptRoot\Plugins\$pluginName.psm1 -Raw);
}

# CHECK FILTERS
write ("Groups: $groups")
write ("Hosts: $hosts")
write ("Templates: $templates")

if ($groups -ne $null) { $groups = $groups.Split(","); }
if ($hosts -ne $null) { $hosts = $hosts.Split(","); }
if ($templates -ne $null) { $templates = $templates.Split(","); }


if ($hosts -ne $null) {
    $hostsFiles = Get-ChildItem -Path ("$PSScriptRoot\RuntimeHosts") | where { $_.BaseName -in $hosts }
} else {
    $hostsFiles = Get-ChildItem -Path ("$PSScriptRoot\RuntimeHosts")
}

if ($hosts -eq $null -and $groups -ne $null) {
    $hostsInGroups = New-Object 'System.Collections.Generic.List[string]';
    foreach ($group in $groups) {
        $hostsInGroup = Get-Content ("$PSScriptRoot\HostGroups\$group\hosts.txt");
        foreach ($hostInGroup in $hostsInGroup) {
            if ($hostsInGroups.Contains($hostInGroup) -eq $false) { 
                $hostsInGroups.Add($_); 
            }
        }
    }
        
    #$hostsInGroups = New-Object 'System.Collections.Generic.List[string]' (,(New-Object System.Collections.Generic.HashSet[string] (,$hostsInGroups)))
}

$RunspacePool = [runspacefactory]::CreateRunspacePool(1,1000)
$RunspacePool.Open()

$Runspaces = @();

$mainScript = {
	param(
        [string]$hostName,
        [string]$usingPath,
        [System.Collections.Generic.List[object]]$pluginsList,
        [string]$rootPath, #for plugins
        [string[]]$tFilter #template filter
    )

    $runScript =@"
using module $usingPath        
        
`$instance = new-object $hostName        
`$instance.InitializeData(`$args[0]);        
`$instance.Update();            
`$instance.Check();            
"@;

    for ($it=0; $it -lt $pluginsList.Count; ++$it) { 
        $runScript += $pluginsList[$it].ToString() + [System.Environment]::NewLine; 
    }

    [scriptblock]::Create($runScript).InvokeReturnAsIs((,$tFilter));
};

for ($i = 0; $i -lt $hostsFiles.Count; ++$i) {

    $PSInstance = [powershell]::Create();
    [void]$PSInstance.AddScript($mainScript);
    [void]$PSInstance.Addparameter('hostName',($hostsFiles[$i].BaseName))
    [void]$PSInstance.AddParameter('usingPath',$hostsFiles[$i].FullName)
    [void]$PSInstance.AddParameter('pluginsList',$plugins)
    [void]$PSInstance.AddParameter('rootPath',$PSScriptRoot);
    [void]$PSInstance.AddParameter('tFilter',$templates);

    $PSInstance.RunspacePool = $RunspacePool

    $Runspaces += New-Object psobject -Property @{
	    HostName = $hostsFiles[$i].BaseName
        Instance = $PSInstance
        IAResult = $null
    }
}


write ('[' + (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff") + '] ' + "������������ ��������.");

for ($i = 0; $i -lt $Runspaces.Count; ++$i) { 
	$iaResult = $Runspaces[$i].Instance.BeginInvoke(); 
	$Runspaces[$i].IAResult = $iaResult; 
}

# Wait for the the runspace jobs to complete      
$completed = $true;
while ($true) {
    $completed = $true;
    for ($i = 0; $i -lt $Runspaces.Count; ++$i) {
        if ($Runspaces[$i].IAResult.IsCompleted -eq $false) {
            $completed = $false;
            break;
        }
    }
    if ($completed -eq $true) { break; } 
    else { sleep -Milliseconds 100; }
}
    

for ($i = 0; $i -lt $Runspaces.Count; ++$i) {
    $data = $Runspaces[$i].Instance.EndInvoke($Runspaces[$i].IAResult);
	if ($data -ne $null) { 
        Write-Host($Runspaces[$i].HostName) -ForegroundColor Red; 
        Write-Output $data; 
    }
}
    
[System.GC]::Collect();  
[System.GC]::GetTotalMemory($true) | out-null

write ('[' + (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffffff") + '] ' + "���������." );

$RunspacePool.Close();
$RunspacePool.Dispose();