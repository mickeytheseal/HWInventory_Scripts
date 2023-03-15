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
# SIG # Begin signature block
# MIIbpwYJKoZIhvcNAQcCoIIbmDCCG5QCAQExCzAJBgUrDgMCGgUAMGkGCisGAQQB
# gjcCAQSgWzBZMDQGCisGAQQBgjcCAR4wJgIDAQAABBAfzDtgWUsITrck0sYpfvNR
# AgEAAgEAAgEAAgEAAgEAMCEwCQYFKw4DAhoFAAQU5ikjz4YB2IfhoECHeWZ11f/p
# xIWgghYZMIIDDjCCAfagAwIBAgIQRrrtSqwnVblADCai2b2rGTANBgkqhkiG9w0B
# AQsFADAfMR0wGwYDVQQDDBRNVW50dXJhIEF1dGhlbnRpY29kZTAeFw0yMjExMTQx
# MjA4MDNaFw0yMzExMTQxMjI4MDNaMB8xHTAbBgNVBAMMFE1VbnR1cmEgQXV0aGVu
# dGljb2RlMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAw7ykG1Q5GRdV
# UBBlVZnHI3NR7aXjF840l5NdB+lbBYVzPx6HVv5RvUVXPfcpCEY7I6yBOM9WO+5d
# OmeuFq1dZ5CUxz7SWTr0Ex+NKKpUWvvRcJLwV+MKlXWYx1V6wx19VQ6TgbQrntyh
# Z3pszdpAc/6fkr9975Rl9i/f75nRDNr56iWE0fL9S3AYIOw58cp4s+rmGt0wsunp
# 2+NpuZ2fIP4b4GT8MIPpp7RTEMnZij1qAWkhqU3Mi5yv9CorEXOylZIpQi0yYmAg
# 9xbPn9VNQw+6ly1MwEa4E+08eAlei+Ly/8iSSfUAPjBzetfA3ipomXDJWg2K4Nw8
# Kg0G5v+pCQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYB
# BQUHAwMwHQYDVR0OBBYEFMsrPMT/3vGqMvjQkxn75si4rb/IMA0GCSqGSIb3DQEB
# CwUAA4IBAQCJKImuj5a0lZmboMbzqZo2oYBNh0dYzXhTgVjInyBepKkKHyh+YPO3
# i+CrLQos0X6hP32bPrSlfnKQ9gGIohTaj2pHEqW8CIBQ4bD3R3/KxIb/O3EFu7Ts
# 2cwrQEnkYNpq4hgEBI/RjOykVZK2hGV3Zm67AyS13sSBBhRqsmJ2vxiaO2lsF3bK
# n/tKklvDW17EOepWaydFNKZwnLw1C8yCkdMh6CQheCfXSoCWOO3HUQUZbLBAbNYZ
# imm3brhYAbijEzdnJat8ahZOqmxNxXZDYs9hIpNxANBgtWIRdD5iuV4OOkg/yhsG
# EdhqVtRPCsJDOFK+SdPUfupVnW6mw5ypMIIFjTCCBHWgAwIBAgIQDpsYjvnQLefv
# 21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJVUzEVMBMGA1UEChMM
# RGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSQwIgYDVQQD
# ExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIwODAxMDAwMDAwWhcN
# MzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQg
# SW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2Vy
# dCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Yq3aaza57G4QNxDAf
# 8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lXFllVcq9ok3DCsrp1
# mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxeTsiT+CFhmzTrBcZe
# 7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbuyntd463JT17lNecx
# y9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I9YI+EJFwq1WCQTLX
# 2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmgZ92kJ7yhTzm1EVgX
# 9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse5w5jrubU75KSOp49
# 3ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKyEbe7f/LVjHAsQWCq
# sWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwhHbJUKSWJbOUOUlFH
# dL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/Y+whX8QgUWtvsauG
# i0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwIDAQABo4IBOjCCATYw
# DwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM3y5nP+e6mK4cD08w
# HwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYDVR0PAQH/BAQDAgGG
# MHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDovL29jc3AuZGlnaWNl
# cnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5kaWdpY2VydC5jb20v
# RGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+MDwwOqA4oDaGNGh0
# dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3VyZWRJRFJvb3RDQS5j
# cmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUAA4IBAQBwoL9DXFXn
# OF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSId229GhT0E0p6Ly23
# OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7Uz9FDRJtDIeuWcqFI
# tJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxAGTVGamlUsLihVo7s
# pNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAIDyyCwrFigDkBjxZgi
# wbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW/VvRXKwYw02fc7cB
# qZ9Xql4o4rmUMIIGrjCCBJagAwIBAgIQBzY3tyRUfNhHrP0oZipeWzANBgkqhkiG
# 9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkw
# FwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhEaWdpQ2VydCBUcnVz
# dGVkIFJvb3QgRzQwHhcNMjIwMzIzMDAwMDAwWhcNMzcwMzIyMjM1OTU5WjBjMQsw
# CQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4xOzA5BgNVBAMTMkRp
# Z2lDZXJ0IFRydXN0ZWQgRzQgUlNBNDA5NiBTSEEyNTYgVGltZVN0YW1waW5nIENB
# MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAxoY1BkmzwT1ySVFVxyUD
# xPKRN6mXUaHW0oPRnkyibaCwzIP5WvYRoUQVQl+kiPNo+n3znIkLf50fng8zH1AT
# CyZzlm34V6gCff1DtITaEfFzsbPuK4CEiiIY3+vaPcQXf6sZKz5C3GeO6lE98NZW
# 1OcoLevTsbV15x8GZY2UKdPZ7Gnf2ZCHRgB720RBidx8ald68Dd5n12sy+iEZLRS
# 8nZH92GDGd1ftFQLIWhuNyG7QKxfst5Kfc71ORJn7w6lY2zkpsUdzTYNXNXmG6jB
# ZHRAp8ByxbpOH7G1WE15/tePc5OsLDnipUjW8LAxE6lXKZYnLvWHpo9OdhVVJnCY
# Jn+gGkcgQ+NDY4B7dW4nJZCYOjgRs/b2nuY7W+yB3iIU2YIqx5K/oN7jPqJz+ucf
# WmyU8lKVEStYdEAoq3NDzt9KoRxrOMUp88qqlnNCaJ+2RrOdOqPVA+C/8KI8ykLc
# GEh/FDTP0kyr75s9/g64ZCr6dSgkQe1CvwWcZklSUPRR8zZJTYsg0ixXNXkrqPNF
# YLwjjVj33GHek/45wPmyMKVM1+mYSlg+0wOI/rOP015LdhJRk8mMDDtbiiKowSYI
# +RQQEgN9XyO7ZONj4KbhPvbCdLI/Hgl27KtdRnXiYKNYCQEoAA6EVO7O6V3IXjAS
# vUaetdN2udIOa5kM0jO0zbECAwEAAaOCAV0wggFZMBIGA1UdEwEB/wQIMAYBAf8C
# AQAwHQYDVR0OBBYEFLoW2W1NhS9zKXaaL3WMaiCPnshvMB8GA1UdIwQYMBaAFOzX
# 44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQEAwIBhjATBgNVHSUEDDAKBggr
# BgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3Nw
# LmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0cDovL2NhY2VydHMuZGlnaWNl
# cnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcnQwQwYDVR0fBDwwOjA4oDag
# NIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RH
# NC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJYIZIAYb9bAcBMA0GCSqGSIb3
# DQEBCwUAA4ICAQB9WY7Ak7ZvmKlEIgF+ZtbYIULhsBguEE0TzzBTzr8Y+8dQXeJL
# Kftwig2qKWn8acHPHQfpPmDI2AvlXFvXbYf6hCAlNDFnzbYSlm/EUExiHQwIgqgW
# valWzxVzjQEiJc6VaT9Hd/tydBTX/6tPiix6q4XNQ1/tYLaqT5Fmniye4Iqs5f2M
# vGQmh2ySvZ180HAKfO+ovHVPulr3qRCyXen/KFSJ8NWKcXZl2szwcqMj+sAngkSu
# mScbqyQeJsG33irr9p6xeZmBo1aGqwpFyd/EjaDnmPv7pp1yr8THwcFqcdnGE4AJ
# xLafzYeHJLtPo0m5d2aR8XKc6UsCUqc3fpNTrDsdCEkPlM05et3/JWOZJyw9P2un
# 8WbDQc1PtkCbISFA0LcTJM3cHXg65J6t5TRxktcma+Q4c6umAU+9Pzt4rUyt+8SV
# e+0KXzM5h0F4ejjpnOHdI/0dKNPH+ejxmF/7K9h+8kaddSweJywm228Vex4Ziza4
# k9Tm8heZWcpw8De/mADfIBZPJ/tgZxahZrrdVcA6KYawmKAr7ZVBtzrVFZgxtGIJ
# Dwq9gdkT/r+k0fNX2bwE+oLeMt8EifAAzV3C+dAjfwAL5HYCJtnwZXZCpimHCUcr
# 5n8apIUP/JiW9lVUKx+A+sDyDivl1vupL0QVSucTDh3bNzgaoSv27dZ8/DCCBsAw
# ggSooAMCAQICEAxNaXJLlPo8Kko9KQeAPVowDQYJKoZIhvcNAQELBQAwYzELMAkG
# A1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdp
# Q2VydCBUcnVzdGVkIEc0IFJTQTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQTAe
# Fw0yMjA5MjEwMDAwMDBaFw0zMzExMjEyMzU5NTlaMEYxCzAJBgNVBAYTAlVTMREw
# DwYDVQQKEwhEaWdpQ2VydDEkMCIGA1UEAxMbRGlnaUNlcnQgVGltZXN0YW1wIDIw
# MjIgLSAyMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAz+ylJjrGqfJr
# u43BDZrboegUhXQzGias0BxVHh42bbySVQxh9J0Jdz0Vlggva2Sk/QaDFteRkjgc
# MQKW+3KxlzpVrzPsYYrppijbkGNcvYlT4DotjIdCriak5Lt4eLl6FuFWxsC6ZFO7
# KhbnUEi7iGkMiMbxvuAvfTuxylONQIMe58tySSgeTIAehVbnhe3yYbyqOgd99qtu
# 5Wbd4lz1L+2N1E2VhGjjgMtqedHSEJFGKes+JvK0jM1MuWbIu6pQOA3ljJRdGVq/
# 9XtAbm8WqJqclUeGhXk+DF5mjBoKJL6cqtKctvdPbnjEKD+jHA9QBje6CNk1prUe
# 2nhYHTno+EyREJZ+TeHdwq2lfvgtGx/sK0YYoxn2Off1wU9xLokDEaJLu5i/+k/k
# ezbvBkTkVf826uV8MefzwlLE5hZ7Wn6lJXPbwGqZIS1j5Vn1TS+QHye30qsU5Thm
# h1EIa/tTQznQZPpWz+D0CuYUbWR4u5j9lMNzIfMvwi4g14Gs0/EH1OG92V1LbjGU
# KYvmQaRllMBY5eUuKZCmt2Fk+tkgbBhRYLqmgQ8JJVPxvzvpqwcOagc5YhnJ1oV/
# E9mNec9ixezhe7nMZxMHmsF47caIyLBuMnnHC1mDjcbu9Sx8e47LZInxscS451Ne
# X1XSfRkpWQNO+l3qRXMchH7XzuLUOncCAwEAAaOCAYswggGHMA4GA1UdDwEB/wQE
# AwIHgDAMBgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMCAGA1Ud
# IAQZMBcwCAYGZ4EMAQQCMAsGCWCGSAGG/WwHATAfBgNVHSMEGDAWgBS6FtltTYUv
# cyl2mi91jGogj57IbzAdBgNVHQ4EFgQUYore0GH8jzEU7ZcLzT0qlBTfUpwwWgYD
# VR0fBFMwUTBPoE2gS4ZJaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0
# VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNybDCBkAYIKwYB
# BQUHAQEEgYMwgYAwJAYIKwYBBQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNv
# bTBYBggrBgEFBQcwAoZMaHR0cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lD
# ZXJ0VHJ1c3RlZEc0UlNBNDA5NlNIQTI1NlRpbWVTdGFtcGluZ0NBLmNydDANBgkq
# hkiG9w0BAQsFAAOCAgEAVaoqGvNG83hXNzD8deNP1oUj8fz5lTmbJeb3coqYw3fU
# ZPwV+zbCSVEseIhjVQlGOQD8adTKmyn7oz/AyQCbEx2wmIncePLNfIXNU52vYuJh
# ZqMUKkWHSphCK1D8G7WeCDAJ+uQt1wmJefkJ5ojOfRu4aqKbwVNgCeijuJ3XrR8c
# uOyYQfD2DoD75P/fnRCn6wC6X0qPGjpStOq/CUkVNTZZmg9U0rIbf35eCa12VIp0
# bcrSBWcrduv/mLImlTgZiEQU5QpZomvnIj5EIdI/HMCb7XxIstiSDJFPPGaUr10C
# U+ue4p7k0x+GAWScAMLpWnR1DT3heYi/HAGXyRkjgNc2Wl+WFrFjDMZGQDvOXTXU
# WT5Dmhiuw8nLw/ubE19qtcfg8wXDWd8nYiveQclTuf80EGf2JjKYe/5cQpSBlIKd
# rAqLxksVStOYkEVgM4DgI974A6T2RUflzrgDQkfoQTZxd639ouiXdE4u2h4djFrI
# HprVwvDGIqhPm73YHJpRxC+a9l+nJ5e6li6FV8Bg53hWf2rvwpWaSxECyIKcyRoF
# fLpxtU56mWz06J7UWpjIn7+NuxhcQ/XQKujiYu54BNu90ftbCqhwfvCXhHjjCANd
# RyxjqCU4lwHSPzra5eX25pvcfizM/xdMTQCi2NYBDriL7ubgclWJLCcZYfZ3AYwx
# ggT4MIIE9AIBATAzMB8xHTAbBgNVBAMMFE1VbnR1cmEgQXV0aGVudGljb2RlAhBG
# uu1KrCdVuUAMJqLZvasZMAkGBSsOAwIaBQCgeDAYBgorBgEEAYI3AgEMMQowCKAC
# gAChAoAAMBkGCSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsx
# DjAMBgorBgEEAYI3AgEVMCMGCSqGSIb3DQEJBDEWBBS0yjx8AQ8G/AxgdMpW0lso
# TN9XhTANBgkqhkiG9w0BAQEFAASCAQBDWPaD52LevLUQh3zMpLrSFhcHAAsZzqHX
# ynOppow3B995GqoFr+kfjNZBUCY8YV5TET6rGzi1WgeZdxWPqtiLsFNQHCP9qWkZ
# zZO+DKDLwfK+Ig0RT11Av3f/qXbyO/NQ8Uwn3HXLKh/E48SjfPqRcgKNABgNq8xG
# 5zRuvhY4slC1PDkOl9FUUG9vJZxUZS+RxtnD3XuEQQHeo6sbGND8VOh1qgC7bUfY
# 3xU9N+5HXgXpQmv3uYLtnPsbamdBkXDLNQ2FnAEZvMBMdQzfFYVl1XvfGhW3Brdj
# Gc7j5XCoYhmE2c8q8qfE5IG4va9wLpQeBmLubwbTBnoams+bsmsUoYIDIDCCAxwG
# CSqGSIb3DQEJBjGCAw0wggMJAgEBMHcwYzELMAkGA1UEBhMCVVMxFzAVBgNVBAoT
# DkRpZ2lDZXJ0LCBJbmMuMTswOQYDVQQDEzJEaWdpQ2VydCBUcnVzdGVkIEc0IFJT
# QTQwOTYgU0hBMjU2IFRpbWVTdGFtcGluZyBDQQIQDE1pckuU+jwqSj0pB4A9WjAN
# BglghkgBZQMEAgEFAKBpMBgGCSqGSIb3DQEJAzELBgkqhkiG9w0BBwEwHAYJKoZI
# hvcNAQkFMQ8XDTIzMDExMzAxNDEyNFowLwYJKoZIhvcNAQkEMSIEIKMFSRPmG+hg
# ePCw7VWTISCfsfch/Jy2ScSaL03utbWPMA0GCSqGSIb3DQEBAQUABIICAJy0HBAx
# lWtx81V/DQlO1XWVD1P+QLzae0NEGvBJU0jvIat6Baw6gWbsl8AdjgwfjmGqHRO2
# 0uX+2d1of20E+RByl+vkpwno2nLVXqOeyfz2Ky7VoOBLILACdV+extIKhxv2sAjH
# +NZahAZae7mFcUPRklx+QWp02XXsEo2Bubo71d+sal2Y0FbRJcK0nYToY1Eyvc4P
# PGmBx8x+bPtzDllMiMjbaoF0pGR5c0h83vD+pRJ9CO9aUFxyJZLyvSLVcTOLR0CP
# 5hwOIPcziyu5rF5G6Jk8g7o1y4fcB3Meg1VJBwQApiUbQvcbeA2kvhaWNZjmYAlw
# I++gW6FinrwVYsC4AUeQMcv7KBD3jGxOQoykQY0hoQYA63Nq5EoxtMGxlDa+ZaeM
# jXhGg0ctRq6qkG+dHBBLESA5NZl15dINo3UJ67rrELcDOoCB6fix9BBtWK0uJVb5
# cDidoZmvDhPzLRFImREU7YV+cpAxWzaaHJ+arwjGSYPzu5Rm3AZwwyVOIh3lZYgG
# H56rv6brfjaVfao57LNidskVWIzdSAhBAX1tmHhujz0BBqcG4ptt+3hmB5tBM4hG
# V1L633K+eNEAlIMaqruEsMAJHBtPxiuMSsGYUhavbu2vIAJWF5YL8DLUf4oJK0mT
# Clnpfuyq40voxzlD0ais7g9RWP8w4G02ETbX
# SIG # End signature block
