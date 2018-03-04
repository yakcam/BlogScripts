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

# Enter your VM name here
$vmName = "W2k16Template"; 

# Enter the local admin password for the VM below
$localAdminPassword = "Your_Local_Admin_Password_Here";

# Get the IP address of the machine
$ip = (Get-VM -Name $vmName | Select-Object -ExpandProperty NetworkAdapters).IPAddresses[0]; # Not great, but it seems to do the trick
Write-Host "VM IP: $ip";

# Add the IP of the VM to those that we're allowed to remotely manage
# NB. This will clear out any existing entries
Write-Host 'Adding IP to list of allowed RM clients...';
Get-Service winrm | Start-Service; # Start the WinRM service
Set-Item WSMan:\localhost\Client\TrustedHosts -Value $ip -Force;

# Create the credentials for the session
$password = ConvertTo-SecureString "$localAdminPassword" -AsPlainText -Force;
$cred= New-Object System.Management.Automation.PSCredential ("Administrator", $password );

# Create a new remote session
Write-Host 'Connecting to remote machine...';
$s = New-PSSession -ComputerName $ip -Credential $cred;

# Connect to the machine and run a command to prove it's working
Invoke-Command -Session $s -ScriptBlock { whoami };

<# ------------------------------------------------ #>

# Copy our installers
Invoke-Command -Session $s -ScriptBlock { mkdir C:\InstallFiles };
Copy-Item -ToSession $s -Path "C:\installfiles\Octopus.Tentacle.3.16.3-x64.msi" -Destination "C:\installfiles\OctopusTentacleInstaller.msi"
Copy-Item -ToSession $s -Path "C:\installfiles\SQLServer2017-SSEI-Dev.exe"      -Destination "C:\installfiles\SQLServerInstaller.exe"
Copy-Item -ToSession $s -Path "C:\installfiles\DLMAutomation.exe"               -Destination "C:\installfiles\DLMAutomation.exe"
Copy-Item -ToSession $s -Path "C:\installfiles\octocert.txt"                    -Destination "C:\installfiles\octocert.txt"

<# ------------------------------------------------ #>

# Copy the unattend.xml file
Invoke-Command -Session $s -ScriptBlock { mkdir C:\unattend };
Copy-Item -ToSession $s -Path "C:\unattend\unattend.xml" -Destination "C:\unattend\unattend.xml";

<# ------------------------------------------------ #>
<#

# Example sysprep command
c:\Windows\System32\Sysprep\sysprep.exe /generalize /shutdown /oobe /unattend:c:\unattend\unattend.xml

#>
<# ------------------------------------------------ #>

# Export the VM
Export-VM -Name "$vmName" -Path "C:\ExportedVirtualMachines";
