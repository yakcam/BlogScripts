<#
MIT License
Copyright (c) 2018 Calum Mackay
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
#>

$ErrorActionPreference = 'Stop';
$name = $OctopusParameters["Process.MachineName"];
$switchName = $OctopusParameters["Process.SwitchName"];
$sourceTemplateVhd = $OctopusParameters["Process.SourceTemplateVhdPath"];
$destFolder = $OctopusParameters["Process.DestinationVmFolder"] + $name + '\';
$destPath = $destFolder + $name + '.vhdx';

<# ------------------------------------------------------------------------------ #>

function BlockUntilGuestRunning($name) {
    Write-Host "Checking status of '$name'...";
    $VM = Get-VMIntegrationService -VMName $name -Name Heartbeat;
    while ($VM.PrimaryStatusDescription -ne "OK") 
    { 
        $VM = Get-VMIntegrationService -VMName $name -Name Heartbeat;
        write-host "The VM is not on";
        Start-Sleep 5;
    }
    Write-Host "The VM is running.";
}

function BlockUntilHasIpAddress($name) {
    $ip = (Get-VM -Name $name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0];
    while (!$ip) {
        $ip = (Get-VM -Name $name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0];
    }
    while ($ip -eq "" -or ($ip.StartsWith("169.")) -or ($ip.StartsWith("fe80"))) {
        $ip = (Get-VM -Name $name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0];
        Write-Host "'$ip' is not a valid ipv4 address...";
        Start-Sleep 5;
    }
    Write-Host "The VM has the ipv4 address '$ip'.";
}

<# ------------------------------------------------------------------------------ #>


if (-Not (Test-Path $destFolder))
{
    mkdir $destFolder -Force > $null;
}

Write-Host 'Copying base vhd...';
Copy-Item `
    -Path "$sourceTemplateVhd" `
    -Destination $destPath > $null;

Write-Host 'Creating VM...';
New-VM `
    -Name $name `
    -MemoryStartupBytes 1GB `
    -BootDevice VHD `
    -VHDPath $destPath `
    -Path $destFolder `
    -Generation 2 `
    -Switch "$switchName" > $null;

Write-Host 'Starting VM...';
Start-VM -Name $name;

Write-Host 'Waiting for VM to start...';
BlockUntilGuestRunning $name;

BlockUntilHasIpAddress $name;
$ip = (Get-VM -Name $name | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0];
Write-Host "VM up and has IP: $ip";

Write-Host 'Adding IP to list of allowed RM clients...';
Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ip -Force;

$password = ConvertTo-SecureString $OctopusParameters["Process.TemplateLocalAdminPass"] -AsPlainText -Force;
$cred= New-Object System.Management.Automation.PSCredential ("Administrator", $password );

Write-Host 'Connecting to remote machine...';
$s = New-PSSession -ComputerName $ip -Credential $cred;

Write-Host "Changing local admin password...";
$newAdminPassword = ConvertTo-SecureString $OctopusParameters["Process.NewLocalAdminPass"]  -AsPlainText -Force;
Invoke-Command -Session $s -ScriptBlock { param($newAdminPassword) Set-LocalUser -Name "Administrator" -Password $newAdminPassword; } -ArgumentList $newAdminPassword;

Write-Host 'Renaming remote machine...';
Invoke-Command -Session $s -Script { param($newName) Rename-Computer -NewName $newName -Restart; } -Args $name;
Disconnect-PSSession -Session $s > $null;
Remove-PSSession -Session $s > $null;
Start-Sleep 5;

Write-Host 'Waiting for VM to restart...';
BlockUntilGuestRunning $name;
BlockUntilHasIpAddress $name;

Write-Host "Creating Octopus (D) drive...";
$diskPath = $destFolder + $name + "_D_Octopus.vhdx";
Stop-Service -Name ShellHWDetection > $null;
New-VHD -Path "$diskPath" -SizeBytes 20GB `
    | Mount-VHD -Passthru `
    | Initialize-Disk -Passthru `
    | New-Partition -AssignDriveLetter -UseMaximumSize `
    | Format-Volume -FileSystem NTFS -NewFileSystemLabel "Octopus" -Confirm:$false -Force > $null;
Dismount-VHD -Path "$diskPath" > $null;
Start-Service -Name ShellHWDetection > $null;

Write-Host "Adding drive to VM...";
Add-VMHardDiskDrive -VMName "$name" -Path "$diskPath" > $null;

Write-Host 'Connecting to remote machine...';
$s2 = New-PSSession -ComputerName $ip -Credential $cred;

Write-Host "Bringing drive online...";
Invoke-Command -Session $s2 -ScriptBlock { Set-Disk -Number 1 -IsOffline $false; Set-Disk -Number 1 -IsReadOnly $false; Set-Volume -DriveLetter "D" -NewFileSystemLabel "Octopus"; };

Write-Host 'Complete.';
