param(
	[string]$Hostname = "hostname",
	[Parameter(Mandatory=$true)][System.Management.Automation.PSCredential]$cr,
	[Parameter(Mandatory=$false)][string[]]$SN,
	[string]$VerbosePreference = "SilentlyContinue"
)

Disconnect-OVMgmt -ErrorAction SilentlyContinue
try {
$conn = Connect-OVMgmt -Hostname $Hostname -Credential $cr -ErrorAction SilentlyContinue
}
catch{
Write-Host "Error"
}

$hws = Get-OVServer
#Write-host $hw.Count
if ($hws -eq $null) {
	Write-Error "Found no servers"
	Exit
	}

	
Write-Host "Found "$hws.Count" servers"

$report= @()
foreach ($hw in $hws) {

$rec = New-Object PSObject
$rec | Add-Member -Name ServerName -MemberType NoteProperty -value ($hw.ServerName.Split("."))[0]
$rec | Add-Member -Name Serial -MemberType NoteProperty -value $hw.SerialNumber 
$rec | Add-Member -Name Model -MemberType NoteProperty -value $hw.Model
$rec | Add-Member -Name PN -MemberType NoteProperty -value $hw.partNumber
$rec | Add-Member -Name CPUcount -MemberType NoteProperty -value $hw.processorCount
$rec | Add-Member -Name CPUModel -MemberType NoteProperty -value $hw.processorType
$rec | Add-Member -Name Platform -MemberType NoteProperty -value $hw.Platform

$ram = @()
foreach ($RamModule in ($hw.subresources.Memory.data | ? {$_.CapacityMiB })){
	$subrec = New-Object PSObject
	$subrec | Add-Member -Name BaseModuleType -MemberType NoteProperty -value $RamModule.BaseModuleType
	$subrec | Add-Member -Name CapacityGiB -MemberType NoteProperty -value ($RamModule.CapacityMiB/1024)
	$subrec | Add-Member -Name RankCount -MemberType NoteProperty -value $RamModule.RankCount
	$subrec | Add-Member -Name OperatingSpeedMhz -MemberType NoteProperty -value $RamModule.OperatingSpeedMhz
	$subrec | Add-Member -Name PartNumber -MemberType NoteProperty -value $RamModule.PartNumber

	$ram+= $subrec
}
#
$ramrep = @()
$ramrep = ($ram.PartNumber | Group | %{(($_.Count).ToString() + "*"+ $_.Name)}) -join "`n"
$rec | Add-Member -Name Memory -MemberType NoteProperty -value $ramrep

#
#$rec | Add-Member -Name Memory -MemberType NoteProperty -value $ram

$rec | Add-Member -Name RAIDModel -MemberType NoteProperty -value $hw.subresources.LocalStorage.data.Model
$rec | Add-Member -Name RAIDCacheModuleSize -MemberType NoteProperty -value $hw.subresources.LocalStorage.data.CacheMemorySizeMiB

$devices = @()
foreach ($device in ($hw.subresources.Devices.data | ? {$_.PartNumber})){
	$subrec = New-Object PSObject
	$subrec | Add-Member -Name Name -MemberType NoteProperty -value $device.Name
	$subrec | Add-Member -Name PartNumber -MemberType NoteProperty -value $device.PartNumber
	$devices+= $subrec
}

$devicesrep = @()

foreach ($dev in $devices){
	if ($dev.Name -like "*batt*") {
		$rec | Add-Member -Name Battery -MemberType NoteProperty -value $dev.Name
		$rec | Add-Member -Name BatteryPN -MemberType NoteProperty -value $dev.PartNumber
		}
	elseif ($dev.Name -like "*Smart Array*") {
		}
	elseif ($dev.Name -like "*FC*"){
		$rec | Add-Member -Name FC -MemberType NoteProperty -value $dev.Name
		$rec | Add-Member -Name FCPN -MemberType NoteProperty -value $dev.PartNumber		
		}
	else {
		$devicesrep += $dev.Name + " `t" + $dev.PartNumber
		}
}

$devicesrep = $devicesrep -join "`n"

$rec | Add-Member -Name Devices -MemberType NoteProperty -value $devicesrep



$drives = @()
foreach ($drive in ($hw.subresources.LocalStorage.data.PhysicalDrives | ? {$_.CapacityMiB })){
	$subrec = New-Object PSObject
	$subrec | Add-Member -Name Model -MemberType NoteProperty -value $Drive.Model
	$subrec | Add-Member -Name CapacityGiB -MemberType NoteProperty -value ($drive.CapacityMiB/1024)
	$subrec | Add-Member -Name MediaType -MemberType NoteProperty -value $drive.MediaType
	$subrec | Add-Member -Name InterfaceType -MemberType NoteProperty -value $drive.InterfaceType
	$drives+= $subrec
}
#$rec | Add-Member -Name Drives -MemberType NoteProperty -value $drives

$drivesrep = @()
$drivesrep = ($drives.Model | Group | %{(($_.Count).ToString() + "*"+ $_.Name)}) -join "`n"
$rec | Add-Member -Name Drives -MemberType NoteProperty -value $drivesrep

$report+= $rec
}

$report

$mypath = $MyInvocation.MyCommand.Path
$mypath = Split-Path $mypath -Parent
$report | Export-Clixml $mypath\report.xml