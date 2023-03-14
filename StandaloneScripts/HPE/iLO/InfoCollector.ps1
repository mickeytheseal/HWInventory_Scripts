####################################################################
#Getting Server information
####################################################################

<#
.Synopsis
    This Script allows user to get server information for HPE ProLiant servers.

.DESCRIPTION
    This Script allows user to get server information.
	
	The cmdlets used from HPEiLOCmdlets module in the script are as stated below:
	Enable-HPEiLOLog, Find-HPEiLO, Connect-HPEiLO, Get-HPEiLOServerInfo, Get-HPEiLOSmartArrayStorageController,
    Get-HPEiLOSmartStorageBattery, Get-HPEiLOFirmwareInventory, Get-HPEiLODeviceInventory, Disconnect-HPEiLO
    
.INPUTS
	iLOInput.csv file in the script folder location having iLO IPv4 address, iLO Username and iLO Password.

.OUTPUTS
    srvdata_timestamp.json file contatinig servers configuration

.NOTES
	Always run the PowerShell in administrator mode to execute the script.
	
    Company : Hewlett Packard Enterprise
    Version : 2.2.0.0
    Date    : 03/15/2019
    
    Modded  : Mikhail Untura
    Version : 1.3
    Date    : 12.01.2022
    
    Features: Collecting ServerInfo, SmartArray, Battery, Firmware and PCI Devices.
              Saving as JSON array, each object describes each server. 

.LINK
    http://www.hpe.com/servers/powershell
    https://github.com/HewlettPackard/PowerShell-ProLiant-SDK/tree/master/HPEiLO

    Mikhail Untura - t.me/sillyseal
#>


#Чтение csv-файла с данными iLO
try
{
    $path = Split-Path -Parent $PSCommandPath
    $path = join-Path $path "\iLOInput.csv"
    $inputcsv = Import-Csv $path -Delimiter ';'
	if($inputcsv.IP.count -eq $inputcsv.Username.count -eq $inputcsv.Password.count -eq 0)
	{
		Write-Host "Provide values for IP, Username and Password columns in the iLOInput.csv file and try again."
        exit
	}

    $notNullIP = $inputcsv.IP | Where-Object {-Not [string]::IsNullOrWhiteSpace($_)}
    $notNullUsername = $inputcsv.Username | Where-Object {-Not [string]::IsNullOrWhiteSpace($_)}
    $notNullPassword = $inputcsv.Password | Where-Object {-Not [string]::IsNullOrWhiteSpace($_)}
	if(-Not($notNullIP.Count -eq $notNullUsername.Count -eq $notNullPassword.Count))
	{
        Write-Host "Provide equal number of values for IP, Username and Password columns in the iLOInput.csv file and try again."
        exit
	}
}
catch
{
    Write-Host "iLOInput.csv file import failed. Please check the file path of the iLOInput.csv file and try again."
    Write-Host "iLOInput.csv file path: $path"
    exit
}

Clear-Host

#Подключение подуля HPEiLOCmdlets 
$InstalledModule = Get-Module
$ModuleNames = $InstalledModule.Name

if(-not($ModuleNames -like "HPEiLOCmdlets"))
{
    Write-Host "Loading module :  HPEiLOCmdlets"
    Import-Module HPEiLOCmdlets
    if(($null -eq $(Get-Module -Name "HPEiLOCmdlets")))
    {
        Write-Host ""
        Write-Host "HPEiLOCmdlets module cannot be loaded. Please fix the problem and try again"
        Write-Host ""
        Write-Host "Exit..."
        exit
    }
}
else
{
    $InstallediLOModule  =  Get-Module -Name "HPEiLOCmdlets"
    Write-Host "HPEiLOCmdlets Module Version : $($InstallediLOModule.Version) is installed on your machine."
    Write-host ""
}

$Error.Clear()

#Включение логгирования
Write-Host "Enabling logging feature" -ForegroundColor Yellow
$log = Enable-HPEiLOLog
$log | Format-List

if($Error.Count -ne 0)
{ 
	Write-Host "`nPlease launch the PowerShell in administrator mode and run the script again." -ForegroundColor Yellow 
	Write-Host "`n****** Script execution terminated ******" -ForegroundColor Red 
	exit 
}	



try
{
	$ErrorActionPreference = "SilentlyContinue"
	$WarningPreference ="SilentlyContinue"

    Write-Host "Collecting reachable IP's. This operation may take a while.`n"
    $reachableIPList = Find-HPEiLO $inputcsv.IP -WarningAction SilentlyContinue
    Write-Host "The below list of IP's are reachable."
    $reachableIPList.IP

    #Проверка подключения к iLO
    $reachableData = @()
    foreach($ip in $reachableIPList.IP)
    {
        $complete = $reachableIPList.IP.IndexOf($ip)/$reachableIPList.IP.Count * 100
        Write-Progress -Activity "Connecting to targets" -Status "$complete% Complete:" -PercentComplete $complete
        $index = $inputcsv.IP.IndexOf($ip)
        $inputObject = New-Object System.Object

        $inputObject | Add-Member -type NoteProperty -name IP -Value $ip
        $inputObject | Add-Member -type NoteProperty -name Username -Value $inputcsv[$index].Username
        $inputObject | Add-Member -type NoteProperty -name Password -Value $inputcsv[$index].Password

        $reachableData += $inputObject
    }
    
    Write-Host "`nConnecting using Connect-HPEiLO`n" -ForegroundColor Yellow
    $Connection = Connect-HPEiLO -IP $reachableData.IP -Username $reachableData.Username -Password $reachableData.Password -DisableCertificateAuthentication -WarningAction SilentlyContinue
	
	$Error.Clear()
	
	if($null -eq $Connection)
    {
        Write-Host "`nConnection could not be established to any target iLO.`n" -ForegroundColor Red
        $inputcsv.IP | Format-List
        exit;
    }
	else
	{
		Write-Host "Connection established.`n"
	}
	
	#Список недоступных адресов
	if($Connection.count -ne $reachableIPList.IP.count)
    {
        Write-Host "`nConnection failed for below set of targets" -ForegroundColor Red
        foreach($item in $reachableIPList.IP)
        {
            if($Connection.IP -notcontains $item)
            {
                $item | Format-List
            }
        }
    }
	Disconnect-HPEiLO $Connection
    
    Write-Host "`nRetrieving server information`n" -ForegroundColor Yellow

    $srvList = New-Object Collections.Generic.List[PSCustomObject]
    $mypath = $MyInvocation.MyCommand.Path
    $mypath = Split-Path $mypath -Parent

    #Обход доступных подключений и сбор информации
    foreach($rd in $reachableData)
    {
        $connect = Connect-HPEiLO -IP $rd.IP -Username $rd.Username -Password $rd.Password -DisableCertificateAuthentication -WarningAction SilentlyContinue
        $complete = $inputcsv.IP.IndexOf($connect.IP)/$inputcsv.IP.Count * 100
        Write-Progress -Activity "Data collection in progress" -Status "$complete% Complete:" -PercentComplete $complete

        $srvData = [PSCustomObject]@{
            iLOData = $null
            iLOVersion = $null
            ServerInfo = $null
            SmartArray = $null
            SmartStorageBatt = $null
            Firmware = $null
            DeviceInventory = $null
            PCIDevices = $null
        }
        
        Write-Progress -Activity "Collecting iLOData from $($connect.IP)" -Status "0% Complete:" -PercentComplete 0 -Id 1
        $srvData.iLOData = Find-HPEiLO $connect.IP
        Write-Progress -Activity "Collecting iLOVersion from $($connect.IP)" -Status "12.5% Complete:" -PercentComplete 12.5 -Id 1
        $srvData.iLOVersion = $connect.iLOGeneration -replace '\w+\D+',''
        Write-Progress -Activity "Collecting ServerInfo from $($connect.IP)" -Status "25% Complete:" -PercentComplete 25 -Id 1
        $srvData.ServerInfo = Get-HPEiLOServerInfo -Connection $connect
        Write-Progress -Activity "Collecting SmartArray from $($connect.IP)" -Status "37.5% Complete:" -PercentComplete 37.5 -Id 1
        $srvData.SmartArray = Get-HPEiLOSmartArrayStorageController -Connection $connect
        Write-Progress -Activity "Collecting SmartStorageBatt from $($connect.IP)" -Status "50% Complete:" -PercentComplete 50 -Id 1
        $srvData.SmartStorageBatt = Get-HPEiLOSmartStorageBattery -Connection $connect
        Write-Progress -Activity "Collecting Firmware from $($connect.IP)" -Status "62.% Complete:" -PercentComplete 62.5 -Id 1
        $srvData.Firmware = Get-HPEiLOFirmwareInventory -Connection $connect
        Write-Progress -Activity "Collecting DeviceInventory from $($connect.IP)" -Status "75% Complete:" -PercentComplete 75 -Id 1
        $srvData.DeviceInventory = Get-HPEiLODeviceInventory -Connection $connect
        Write-Progress -Activity "Collecting PCIDevices from $($connect.IP)" -Status "87.5% Complete:" -PercentComplete 87.5 -Id 1
        $srvData.PCIDevices = Get-HPEiLOPCIDeviceInventory -Connection $connect

        $srvList.Add($srvData)
        Write-Progress -Activity "All data collected from $($connect.IP)." -Status "100% Complete:" -PercentComplete 100 -Id 1
        
        Disconnect-HPEiLO $connect
    }

    $timestamp = Get-Date -UFormat %s
    
    Write-Host "Generating JSON file at $mypath. Current timestamp: $timestamp`n"

    #Сохранение JSON-файла
    $srvList | ConvertTo-Json -Depth 100 | Out-File -FilePath $mypath\srvdata_$timestamp.json

}
catch
{
}    
finally
{
	
	#Отключение логгирования
	Write-Host "Disabling logging feature`n" -ForegroundColor Yellow
	$log = Disable-HPEiLOLog
	$log | Format-List
	
	if($Error.Count -ne 0 )
    {
        Write-Host "`nScript executed with few errors. Check the log files for more information.`n" -ForegroundColor Red
    }
	
    Write-Host "`n****** Script execution completed ******" -ForegroundColor Yellow
}