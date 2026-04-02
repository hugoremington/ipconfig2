# Script metadata
$author = "Hugo Remington"
$version = "0.5.0.5"
$date = "03-Apr-2026. 04:39"
$timestamp = (Get-Date -Format "dd/MMM/yyyy, HH:mm:ss.fff")
# Splash screen
Write-Host ""
Write-Host "Windows IP Configuration 2.0" -ForegroundColor Yellow
Write-Host ""
# Splash screen end.


<# === FUNCTIONS === #>
function Get-Version
{
    Write-Host "Author: $author | Version: $version | Release date: $date" -ForegroundColor Yellow
    Write-Host ""
}

# Helper function to convert prefix length to subnet mask
function Convert-PrefixToSubnetMask
{
    param([int]$PrefixLength)
    
    # Create a 32-bit integer with the prefix number of 1s
    $mask = ([Math]::Pow(2, $PrefixLength) - 1) -shl (32 - $PrefixLength)
    
    # Convert to dotted decimal format
    $octets = @()
    for ($i = 0; $i -lt 4; $i++) {
        $octets += ($mask -shr ((3 - $i) * 8)) -band 0xFF
    }
    return ($octets -join ".")
}

# v0.5.0.4 FlushDNS Function.
function Invoke-FlushDNS
{
    <#
    .SYNOPSIS
        Flushes the DNS resolver cache using Clear-DnsClientCache.
    
    .DESCRIPTION
        This function flushes the DNS resolver cache using the built-in
        Clear-DnsClientCache PowerShell cmdlet, which is available on Windows 8/Server 2012 and later.
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Check if Clear-DnsClientCache is available
        if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
            # Get total DNS cache entry count.
            $DNSCacheCount = (Get-DnsClientCache).Count
            # Clear DNS Cace.
            Clear-DnsClientCache
            Write-Host "$DNSCacheCount DNS cache entries flushed. Timestamp: $timestamp.`n" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Unable to flush DNS cache: $($_.Exception.Message) `n"
        #throw
    }
    if ($showAll -eq $True -or $args -contains "/renew" -or $args -contains "/release")
    {
        # Do nothing.
    }
    else {
        exit
    }
    
}

function Invoke-ResetWinsock {
    <#
    .SYNOPSIS
        Resets the Winsock catalog to a clean state, removing any custom LSPs to resolve network problems caused by corrupted Winsock settings. It doesn't affect Winsock Name Space Provider entries.
    
    .DESCRIPTION
        This function reset Winsock using netsh. Requires elevation and restart.
    #>  
    try {
        # Check if running as administrator
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "This operation requires administrator privileges. Please run as administrator.`n" -ForegroundColor Yellow
        }
        else
        {
            # Execute netsh and suppress its output
            $null = netsh winsock reset
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Sucessfully reset the Winsock Catalog. Timestamp: $timestamp." -ForegroundColor Yellow
                Write-Host "You must restart the computer in order to complete the reset.`n" -ForegroundColor Yellow
            } else {
                Write-Host "Winsock reset failed with exit code: $LASTEXITCODE `n" -ForegroundColor Red
            }
        }
        
    }
    catch {
        Write-Host "Unable to reset Winsock." -ForegroundColor Red
        #throw
    }
        exit
}

<# v0.4.1.2 NEW FUNCTIONS START     #>
## New Functions for IP Configuration Management

function Invoke-IPConfigRelease {  
    try {
        # Try CimInstance method first (native PowerShell)
        Write-Host "Releasing DHCP IP addresses...`n" -ForegroundColor Yellow
        $adapters = Get-NetIPInterface | Where-Object { $_.Dhcp -eq "Enabled" -and $_.InterfaceAlias -notlike "*Loopback*" } | Sort-Object -Property InterfaceMetric
            foreach ($adapter in $adapters)
            {
                # Update timestamp in the loop for correct progress.
                $timestamp = (Get-Date -Format "dd/MMM/yyyy, HH:mm:ss.fff")
                try {                  
                    # Using modern CimInstance for rlease.
                    $result = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $($adapter.IfIndex) -and $_.DHCPEnabled -eq $True } | Invoke-CimMethod -MethodName "ReleaseDHCPLease"
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "Successfully released IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily). Timestamp: $timestamp." -ForegroundColor Yellow
                    }
                    else {
                        #Write-Host "Failed to release IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) using CIM." -ForegroundColor Yellow
                        # Using classing WmiObject for release.
                        $result = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $($adapter.IfIndex) -and $_.DHCPEnabled -eq $True } | ForEach-Object { $_.ReleaseDHCPLease() }
                        if ($result.ReturnValue -eq 0) {
                            Write-Host "Successfully released IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) using WMI. Timestamp: $timestamp." -ForegroundColor Yellow
                        }
                        else {
                            Write-Host "Failed to release IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily). Timestamp: $timestamp." -ForegroundColor Yellow
                        }
                    }
                }
                catch {
                    Write-Host "Failed to release IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) : $($_.Exception.Message)" -ForegroundColor Yellow
                }
                # Start sleep to prevent NIC failover.
                #Start-Sleep 3
            }
            # Start sleep to prevent IPv6 redundant output loop, wait for IPv4 169.254 assignment. Loop now resolved in v0.5.0.2.
            Start-Sleep 6
    }
    catch {
        Write-Host "Failed to release IP configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Invoke-IPConfigRenew {
    try {
        # Try CimInstance method first (native PowerShell)
        Write-Host "Renewing DHCP IP addresses...`n" -ForegroundColor Yellow
        $adapters = Get-NetIPInterface | Where-Object { $_.Dhcp -eq "Enabled" -and $_.InterfaceAlias -notlike "*Loopback*" } | Sort-Object -Property InterfaceMetric
        foreach ($adapter in $adapters) {
            # Update timestamp in the loop for correct progress.
            $timestamp = (Get-Date -Format "dd/MMM/yyyy, HH:mm:ss.fff")

            try {
                # Using modern CimInstance for renew.
                $result = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $($adapter.IfIndex) -and $_.DHCPEnabled -eq $True } | Invoke-CimMethod -MethodName "RenewDHCPLease"
                if ($result.ReturnValue -eq 0) {
                    Write-Host "Successfully renewed IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily). Timestamp: $timestamp." -ForegroundColor Yellow
                }
                else {
                    #Write-Host "Failed to renew IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) using CIM." -ForegroundColor Yellow
                    # Using classing WmiObject for renew.
                    $result = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.InterfaceIndex -eq $($adapter.IfIndex) -and $_.DHCPEnabled -eq $True } | ForEach-Object { $_.RenewDHCPLease() }
                    if ($result.ReturnValue -eq 0) {
                        Write-Host "Successfully renewed IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) using WMI. Timestamp: $timestamp." -ForegroundColor Yellow
                    }
                    else {
                        Write-Host "Failed to renew IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily). Timestamp: $timestamp." -ForegroundColor Yellow
                    }
                }
            }
            catch {
                Write-Host "Failed to renew IP on $($adapter.InterfaceAlias) $($adapter.AddressFamily) : $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Host "Failed to renew IP configuration: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

function Get-AllSystemInfo {
        function Get-Metadata {
            $netProfileName = $null
            $netProfileCategory = $null
            $netIPv4Connectivity = $null
            $netIPv6Connectivity = $null
            $primaryDnsSuffix = $null
            $dnsSuffixSearchList = $null
            $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

            # Query Win32_NetworkAdapterConfiguration.
            $getWin32_NetworkAdapterConfiguration = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration

            # Fast local value
            $hostname = [System.Environment]::MachineName

            # Read registry once
            $tcpipParams = $null
            try {
                $tcpipParams = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
            } catch {}

            # Net profile metadata
            try {
                $NetConnectionQuery = Get-NetConnectionProfile
                $netProfileName = $NetConnectionQuery.Name
                $netProfileCategory = $NetConnectionQuery.NetworkCategory
                $netIPv4Connectivity = $NetConnectionQuery.IPv4Connectivity
                $netIPv6Connectivity = $NetConnectionQuery.IPv6Connectivity
            }
            catch {
                $netProfileName = $null
                $netProfileCategory = $null
                $netIPv4Connectivity = $null
                $netIPv6Connectivity = $null
            }

            # Registry-backed values
            $ipRoutingEnabled = "No"
            if ($tcpipParams -and $tcpipParams.PSObject.Properties.Name -contains 'IPEnableRouter') {
                if ($tcpipParams.IPEnableRouter -eq 1) {
                    $ipRoutingEnabled = "Yes"
                }
            }

            $winsProxyEnabled = "No"
            if ($tcpipParams -and $tcpipParams.PSObject.Properties.Name -contains 'EnableProxy') {
                if ($tcpipParams.EnableProxy -eq 1) {
                    $winsProxyEnabled = "Yes"
                }
            }
            # Get primary dns suffix.
            $primaryDnsSuffix = $($getWin32_NetworkAdapterConfiguration.DNSDomain) | Where-Object { $_ }
            
            # Get dns suffix search list.
            $searchList = $getWin32_NetworkAdapterConfiguration.DNSDomainSuffixSearchOrder | Where-Object { $_ }
            if ($searchList -is [array]) {
                $dnsSuffixSearchList = $searchList
            }
            elseif ($searchList) {
                $dnsSuffixSearchList = $searchList
            }

            return [PSCustomObject]@{
                Hostname            = $hostname
                primaryDnsSuffix    = $primaryDnsSuffix | Select-Object -Unique
                NetProfileName      = $netProfileName | Select-Object -Unique
                NetProfileCategory  = $netProfileCategory | Select-Object -Unique
                NetIPv4Connectivity = $netIPv4Connectivity | Select-Object -Unique
                NetIPv6Connectivity = $netIPv6Connectivity | Select-Object -Unique
                IPRoutingEnabled    = $ipRoutingEnabled
                WINSProxyEnabled    = $winsProxyEnabled
                DNSSuffixSearchList = $dnsSuffixSearchList | Select-Object -Unique
            }
        }

    # Only parallelise the expensive external call path
    $ispJob = Start-Job -ScriptBlock {
        function Get-Isp {
            $ispJob1 = Start-Job -ScriptBlock {
                try {
                    Invoke-RestMethod "http://ip-api.com/json/" -ErrorAction SilentlyContinue
                }
                catch {
                    $null
                }
            }

            $dnsJob1 = Start-Job -ScriptBlock {
                try {
                    Resolve-DnsName whoami.akamai.net -ErrorAction SilentlyContinue
                    
                }
                catch {
                    $null
                }
            }

            Wait-Job -Job $ispJob1, $dnsJob1 -Timeout 10 -ErrorAction SilentlyContinue | Out-Null

            $ispApi1 = $null
            $dnsApi1 = $null

            try { $ispApi1 = Receive-Job -Job $ispJob1 -ErrorAction SilentlyContinue } catch {}
            try { $dnsApi1 = Receive-Job -Job $dnsJob1 -ErrorAction SilentlyContinue } catch {}

            Remove-Job -Job $ispJob1, $dnsJob1 -Force -ErrorAction SilentlyContinue

            if (-not $ispApi1 -and -not $dnsApi1) {
                return $null
            }

            return [PSCustomObject]@{
                # ISP variables (primarily from ip-api)
                IspIP       =   if ($ispApi1.query)                   { $ispApi1.query }                    else { $null }
                IspName     =   if ($ispApi1.isp)                     { $ispApi1.isp }                      else { $null }
                IspOrg      =   if ($ispApi1.org)                     { $ispApi1.org }                      else { $null }
                IspAs       =   if ($ispApi1.as)                      { $ispApi1.as }                       else { $null }
                IspCity     =   if ($ispApi1.city)                    { $ispApi1.city }                     else { $null }
                IspRegion   =   if ($ispApi1.regionName)              { $ispApi1.regionName }               else { $null }
                IspCountry  =   if ($ispApi1.country)                 { $ispApi1.country }                  else { $null }
                IspZip      =   if ($ispApi1.zip)                     { $ispApi1.zip }                      else { $null }
                IspTimezone =   if ($ispApi1.timezone)                { $ispApi1.Timezone }                 else { $null }
                IspLat      =   if ($ispApi1.lat)                     { $ispApi1.lat }                      else { $null }
                IspLon      =   if ($ispApi1.lon)                     { $ispApi1.lon }                      else { $null }
                IspLoc      =   if ($ispApi1.lat -and $ispApi1.lon)   {"$($ispApi1.lat),$($ispApi1.lon)"}   else { $null }
                DnsIP       =   if ($dnsApi1.IPAddress)               { $dnsApi1.IPAddress }                else { $null }
            }
        }
        Get-Isp
    }

    # Run metadata synchronously
    $metadata = Get-Metadata

    # Collect Job threads result
    Wait-Job -Job $ispJob -Timeout 10 | Out-Null

    $IspInfo        =   $null
    # $MetadataInfo   =   $null
    try {
        $IspInfo =      Receive-Job -Job $ispJob -ErrorAction SilentlyContinue
        #$MetadataInfo = Receive-Job -Job $MetadataJob -ErrorAction SilentlyContinue
    } catch {}

    Remove-Job -Job $ispJob -Force -ErrorAction SilentlyContinue

    return @{
        Metadata = $metadata
        IspInfo  = $IspInfo
    }
}

<# ===START GET LOCAL NIC IP DATA FUNCTION=== #>
function Get-LocalNicIpData {
    try { # v0.3.0.0 try/catch block for exception handling.
        # Get net profile name from previous function Get-AllSystemInfo.
        $netProfileName = (Get-AllSystemInfo).Metadata.NetProfileName

        # Create local NIC array.
        $localInfo = @()
        
        <# Get Network Adapters Query v0.4.0.5 #>
        $networkAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceDescription -notmatch "Loopback"}

        if ($networkAdapters) {
            # Build queries for performance v0.4.0.5.
            $dnsClients = Get-DnsClient -ErrorAction SilentlyContinue
            # Start default gateway lookup table for performance v0.4.0.5.
            $gatewayTable = @{}
            <# START default gateway loop v0.4.0.5#>
            Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric |
                ForEach-Object {
                    if (-not $gatewayTable.ContainsKey($_.InterfaceIndex)) {
                        $gatewayTable[$_.InterfaceIndex] = $_.NextHop
                    }
                }
            <# END default gateway loop. #>
            
            <# START DNS server lookup table for efficiency v0.4.0.5#>
            $dnsServerTable = @{}
            Get-DnsClientServerAddress -ErrorAction SilentlyContinue | ForEach-Object {
                $ifIndex = [int]$_.InterfaceIndex

                if (-not $dnsServerTable.ContainsKey($ifIndex)) {
                    $dnsServerTable[$ifIndex] = @()
                }

                if ($_.ServerAddresses) {
                    $dnsServerTable[$ifIndex] += $_.ServerAddresses
                }
            }
            <# END DNS server lookup table #>

            # QUERIES outside of foreach loop for efficiency.
            $netbiosQuery = (Get-CimInstance Win32_NetworkAdapterConfiguration)
            $GetAllStatsQuery = (Get-NetAdapterStatistics -ErrorAction SilentlyContinue)
            $getAllIpAddressesQuery = Get-NetIPAddress -ErrorAction SilentlyContinue

            foreach ($adapter in $networkAdapters) {
                # Get Connection-specific DNS suffix
                $dnsSuffix = $null
                try {
                    # Match DNS client by InterfaceIndex
                    $dnsClient = $dnsClients | Where-Object { $_.InterfaceIndex -eq $adapter.InterfaceIndex }
                    if ($dnsClient) {
                        $dnsSuffix = $dnsClient.ConnectionSpecificSuffix
                    }
                } catch {
                    # If we can't get DNS suffix, leave it null
                }
                
                # Get Default Gateway for this specific interface
                $gateway = $null
                try {
                    if ($gatewayTable.ContainsKey($adapter.InterfaceIndex)) {
                        $gateway = $gatewayTable[$adapter.InterfaceIndex]
                    }
                } catch {
                    # If we can't get gateway, leave it null
                }
                
                # Get DNS Servers for this specific interface
                $dnsServers = $null
                $dnsServerAddresses = $null

                if ($dnsServerTable.ContainsKey([int]$adapter.InterfaceIndex)) {
                    $dnsServerAddresses = $dnsServerTable[[int]$adapter.InterfaceIndex]
                }

                if ($dnsServerAddresses) {
                    $dnsServers = ($dnsServerAddresses | Select-Object -Unique) -join ', '
                }
                
                # Get Wifi magic.
                $PhysicalMediaType = $adapter.PhysicalMediaType

                If ($PhysicalMediaType -like "*802.11*")
                {
                    try {
                        # 0.4.0.5 netshQuery performance optimisation.
                        $netshQuery1 = netsh wlan show profiles
                        # Get all profiles
                        $allProfiles = $netshQuery1 | Select-String "All User Profile" | ForEach-Object { ($_ -split ":")[1].Trim() }
                        
                        if ($allProfiles) {
                            # Find the profile that contains your partial name
                            $matchingProfile = $allProfiles | Where-Object { $_ -like "*$netProfileName*" } | Select-Object -First 1
                            
                            # If no match found, try searching the other way around
                            if (-not $matchingProfile) {
                                $matchingProfile = $allProfiles | Where-Object { $netProfileName -like "*$_*" } | Select-Object -First 1
                            }
                            
                            if ($matchingProfile) {
                                $actualProfileName = $matchingProfile
                                
                                # 0.4.0.5 netshQuery performance optimisation.
                                $netshQuery2 = netsh wlan show profiles name="$actualProfileName" key=clear
                                # Get SSID
                                $ssidInfo = $netshQuery2 | Select-String "SSID name"
                                if ($ssidInfo) {
                                    $wifiSsid = ($ssidInfo -split ":")[1].Trim()
                                    $wifiSsid = ($wifiSsid).Trim('"')
                                }
                                $wifiKeyInfo = $netshQuery2 | Select-String "Key Content"
                                if ($wifiKeyInfo) {
                                    $wifiKey = ($wifiKeyInfo -split ":")[1].Trim()
                                }
                            }
                        }
                    } catch {
                        # Write-Host "Error: $_"
                    }
                }

                # Garbage clean up.
                $dhcpEnabledV4 = $false
                $dhcpEnabledV6 = $false
                $dhcpServerV4 = $null
                $dhcpServerV6 = $null
                $StartdateTimeV4 = $null
                $EndDateTimeV4 = $null
                $StartdateTimeV6 = $null
                $EndDateTimeV6 = $null
                $dhcpv6Iaid = $null
                $dhcpv6Duid = $null
                $autoconfigurationEnabled = $null
                $netbiosEnabled = $null
                $netbiosBinding = $null
                $GetAllStats = $null
                $ReceivedBytes = $null
                $SentBytes = $null
                
                
                <# START DHCP TABLE #>
                try {
                    # Get DHCP server from registry using interface GUID
                    $interfaceGuid = $adapter.InterfaceGuid
                    $registryPathDhcpV4 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$interfaceGuid"
                    $registryItemV4 = Get-ItemProperty -Path $registryPathDhcpV4 -ErrorAction SilentlyContinue
                    $registryPathDhcpV6 = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$interfaceGuid"
                    $registryItemV6 = Get-ItemProperty -Path $registryPathDhcpV6 -ErrorAction SilentlyContinue
                    $registryPathDhcpV6DUID = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
                    $registryItemV6DUID = Get-ItemProperty -Path $registryPathDhcpV6DUID -ErrorAction SilentlyContinue
                    
                    if ($registryItemV4) {
                        if ($registryItemV4.EnableDHCP -eq 1) {
                            $dhcpEnabledV4 = "Yes"
                        } else{ $dhcpEnabledV4 = "No" }
                        if ($registryItemV4.DhcpServer) {
                            $dhcpServerV4 = $registryItemV4.DhcpServer
                        }
                        if ($registryItemV4.LeaseObtainedTime) {
                            $dhcpLeaseObtainedTimeV4 = $registryItemV4.LeaseObtainedTime
                            $StartdateTimeV4 = [DateTimeOffset]::FromUnixTimeSeconds($dhcpLeaseObtainedTimeV4).DateTime
                            $dhcpLeaseObtainedTimeV4 = $StartdateTimeV4.ToString("HH:mm:ss, dd/MMM/yyyy")
                        }
                        if ($registryItemV4.LeaseTerminatesTime) {
                            $dhcpLeaseTerminatesTimev4 = $registryItemV4.LeaseTerminatesTime
                            $EndDateTimeV4 = [DateTimeOffset]::FromUnixTimeSeconds($dhcpLeaseTerminatesTimev4).DateTime
                            $dhcpLeaseTerminatesTimev4 = $EndDateTimeV4.ToString("HH:mm:ss, dd/MMM/yyyy")
                        }
                        if ($registryItemV6.LeaseObtainedTime) {
                            $dhcpLeaseObtainedTimeV6 = $registryItemV6.LeaseObtainedTime
                            $StartdateTimeV6 = [DateTimeOffset]::FromUnixTimeSeconds($dhcpLeaseObtainedTimeV6).DateTime
                            $dhcpLeaseObtainedTimeV6 = $StartdateTimeV6.ToString("HH:mm:ss, dd/MMM/yyyy")
                        }
                        if ($registryItemV6.LeaseTerminatesTime) {
                            $dhcpLeaseTerminatesTimev6 = $registryItemV6.LeaseTerminatesTime
                            $EndDateTimeV6 = [DateTimeOffset]::FromUnixTimeSeconds($dhcpLeaseTerminatesTimev6).DateTime
                            $dhcpLeaseTerminatesTimev6 = $EndDateTimeV6.ToString("HH:mm:ss, dd/MMM/yyyy")
                        }
                        if ($registryItemV6.Dhcpv6State) {
                            $dhcpv6State = $registryItemV6.Dhcpv6State
                        }
                        if ($registryItemV6.EnableDHCP -eq 1) {
                            $dhcpEnabledV6 = "Yes"
                        } else { $dhcpEnabledV6 = "No" }
                        if ($registryItemV6.Dhcpv6Server) {
                            $dhcpServerV6 = $registryItemV6.Dhcpv6Server
                        }
                        if ($registryItemV6.Dhcpv6Iaid) {
                            $dhcpv6Iaid = $registryItemV6.Dhcpv6Iaid
                        }
                        if ($registryItemV6DUID.Dhcpv6DUID) {
                            $duidBytes = $registryItemV6DUID.Dhcpv6DUID
                            # Convert to byte array and then to hex
                            $hexArray = @()
                            foreach ($byte in $duidBytes) {
                                $hexArray += "{0:X2}" -f $byte
                            }
                            $dhcpv6Duid = $hexArray -join "-"
                        }
                    }
                } catch {
                    # If we can't get registry info, keep defaults
                }
                <# END DHCP TABLE #>

                <# START Get Autoconfiguration APIPA #>
                try {
                    $autoConfigurationBinding = netsh interface ipv4 show interface $adapter.InterfaceIndex | Select-String "DAD Transmits" | ForEach-Object { ($_ -split ":")[1].Trim() }
                    If ($autoConfigurationBinding -eq 0) {
                        $autoConfigurationEnabled = "No"
                    }
                    else { 
                        $autoConfigurationEnabled = "Yes" 
                    }
                } catch {
                }
                <# END Get Autoconfiguration APIPA #>

                <# START NetBIOS over TCP/IP settings #>
                try {
                    $netbiosBinding = $netbiosQuery | Where-Object { $_.InterfaceIndex -eq $adapter.InterfaceIndex }
                    $netbiosBinding = $netbiosBinding.TcpipNetbiosOptions
                    # Check if NetBIOS is enabled for this interface
                    $netbiosEnabled = if ($netbiosBinding -eq 0) { "Enabled" } elseif ($netbiosBinding -eq 1) { "Enabled" } elseif ($netbiosBinding -eq 2) { "Disabled"} else { "Unknown" }
                } catch {
                }
                <# END NetBIOS over TCP/IP settings #>

                # NIC Stats including ReceivedBytes and SentBytes
                try {
                    $GetAllStats = $GetAllStatsQuery | Where-Object {$_.Name -eq $adapter.Name } -ErrorAction SilentlyContinue
                    $ReceivedBytes = ($GetAllStats).ReceivedBytes
                    $ReceivedBytes = [math]::Round($ReceivedBytes / 1MB, 2)
                    $SentBytes = ($GetAllStats).SentBytes
                    $SentBytes = [math]::Round($SentBytes / 1MB, 2)
                }
                catch {
                }
                
                
                # v0.3.0.2 Get All IPs.
                $getAllIpAddresses = $getAllIpAddressesQuery | Where-Object {$_.InterfaceIndex -eq $adapter.InterfaceIndex } -ErrorAction SilentlyContinue
                # Get IPv4 addresses
                $ipv4Addresses = $getAllIpAddresses | Where-Object {$_.AddressFamily -eq "IPv4"}
                foreach ($ipV4 in $ipv4Addresses) {
                    # Convert prefix length to subnet mask using a simpler approach
                    $subnetMask = Convert-PrefixToSubnetMask -PrefixLength $ipV4.PrefixLength
                    
                    $localInfo += [PSCustomObject]@{
                        MediaConnectionState = $adapter.MediaConnectionState
                        InterfaceDescription = $adapter.InterfaceDescription
                        PhysicalMediaType = $PhysicalMediaType
                        LinkSpeed = $adapter.LinkSpeed
                        InterfaceName = $adapter.Name
                        IPAddress = $ipV4.IPAddress
                        AddressFamily = "IPv4"
                        AddressState = $ipV4.AddressState
                        SubnetMask = $subnetMask
                        PrefixLength = $ipV4.PrefixLength
                        DnsSuffix = $dnsSuffix
                        MacAddress = $adapter.MacAddress
                        DefaultGateway = $gateway
                        DnsServers = $dnsServers
                        DhcpEnabledV4 = $dhcpEnabledV4
                        DhcpServerV4 = $dhcpServerV4
                        DhcpEnabledV6 = $dhcpEnabledV6
                        DhcpServerV6 = $dhcpServerV6
                        dhcpLeaseObtainedTimeV4 = $dhcpLeaseObtainedTimeV4
                        dhcpLeaseTerminatesTimeV4 = $dhcpLeaseTerminatesTimeV4
                        dhcpLeaseObtainedTimeV6 = $dhcpLeaseObtainedTimeV6
                        dhcpLeaseTerminatesTimeV6 = $dhcpLeaseTerminatesTimeV6
                        Dhcpv6Iaid = $dhcpv6Iaid
                        Dhcpv6Duid = $dhcpv6Duid
                        AutoconfigurationEnabled = $autoconfigurationEnabled
                        NetbiosEnabled = $netbiosEnabled
                        WifiSsid = $wifiSsid
                        WifiKey = $wifiKey
                        ReceivedBytes = $ReceivedBytes
                        SentBytes = $SentBytes
                    }
                }
                # Get IPv6 addresses
                $ipv6Addresses = $getAllIpAddresses | Where-Object {$_.AddressFamily -eq "IPv6"}
                foreach ($ipV6 in $ipv6Addresses) {
                    $localInfo += [PSCustomObject]@{
                        MediaConnectionState = $adapter.MediaConnectionState
                        InterfaceDescription = $adapter.InterfaceDescription
                        PhysicalMediaType = $adapter.PhysicalMediaType
                        LinkSpeed = $adapter.LinkSpeed
                        InterfaceName = $adapter.Name
                        IPV6Address = $ipV6.IPAddress
                        AddressFamily = "IPv6"
                        AddressState = $ipV6.AddressState
                        ipv6Type = $ipv6Type
                        SubnetMask = ""
                        PrefixLength = $ipV6.PrefixLength
                        DnsSuffix = $dnsSuffix
                        DefaultGateway = $gateway
                        DnsServers = $dnsServers
                        DhcpEnabledV4 = $dhcpEnabledV4
                        DhcpServerV4 = $dhcpServerV4
                        DhcpEnabledV6 = $dhcpEnabledV6
                        DhcpServerV6 = $dhcpServerV6
                        dhcpLeaseObtainedTimeV4 = $dhcpLeaseObtainedTimeV4
                        dhcpLeaseTerminatesTimeV4 = $dhcpLeaseTerminatesTimeV4
                        dhcpLeaseObtainedTimeV6 = $dhcpLeaseObtainedTimeV6
                        dhcpLeaseTerminatesTimeV6 = $dhcpLeaseTerminatesTimeV6
                        Dhcpv6Iaid = $dhcpv6Iaid
                        Dhcpv6Duid = $dhcpv6Duid
                        AutoconfigurationEnabled = $autoconfigurationEnabled
                        NetbiosEnabled = $netbiosEnabled
                        wifiSsid = $wifiSsid
                        wifiKey = $wifiKey
                        ReceivedBytes = $ReceivedBytes
                        SentBytes = $SentBytes
                    }
                }
            }
        }
    }
    catch {
        # Debug switches
        # Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        # Write-Host "Error: $($_.Exception)" -ForegroundColor Red
        # Write-Host "Error: $($_.Exception.GetType().FullName)" -ForegroundColor Red
    }
    return $localInfo
}
<# ===END GET LOCAL NIC IP DATA FUNCTION=== #>


<# DISPLAY OUTPUT START FUNCTION #>
function Display-Output
{
    # v0.5.0.5 GET ALL DISPLAY VARIABLES.
    # v0.5.0.5 Run Local Nic function.
    $localInfo = Get-LocalNicIpData
    # v0.4.0.2 Master function
    $allInfo = Get-AllSystemInfo
    # v0.4.0.1 new Get-Metadata function.
    $metadata = $allInfo.Metadata
    # v0.4.0.1 new Get-ISP Function
    $IspInfo = $allInfo.IspInfo
    # Group by interface name and display consolidated information
    $groupedInfo = $localInfo | Group-Object InterfaceName

    Write-Host "   Host Name . . . . . . . . . . . . . : $($metadata.Hostname -join "`n                                         ")" -ForegroundColor Yellow
    Write-Host "   Primary Dns Suffix  . . . . . . . . : $($metadata.primaryDnsSuffix -join "`n                                         ")" -ForegroundColor Yellow
    Write-Host "   Network Profile Name. . . . . . . . : $($metadata.NetProfileName -join "`n                                         ")" -ForegroundColor Yellow
    Write-Host "   Network Profile Type. . . . . . . . : $($metadata.NetProfileCategory -join "`n                                         ")" -ForegroundColor Yellow
    if ($showAll -eq $True)
    {
        Write-Host "   IP Routing Enabled. . . . . . . . . : $($metadata.IPRoutingEnabled)" -ForegroundColor Yellow
        Write-Host "   WINS Proxy Enabled. . . . . . . . . : $($metadata.WINSProxyEnabled)" -ForegroundColor Yellow
        Write-Host "   DNS Suffix Search List. . . . . . . : $($metadata.DNSSuffixSearchList -join "`n                                         ")" -ForegroundColor Yellow
    }
    Write-Host "   IPv4 Connectivity . . . . . . . . . : $($metadata.NetIPv4Connectivity -join "`n                                         ")" -ForegroundColor Yellow
    Write-Host "   IPv6 Connectivity . . . . . . . . . : $($metadata.NetIPv6Connectivity -join "`n                                         ")" -ForegroundColor Yellow
    Write-Host ""


    # v0.3.0.0 logic checks
    if ($IspInfo)
    {
        # Display information
        Write-Host "Public IP Address" -ForegroundColor Green
        Write-Host ""
        Write-Host "   Public IPv4 Address . . . . . . . . : $($ispInfo.IspIP -join "`n                                         ")" -ForegroundColor Yellow
        Write-Host "   Public DNS Server . . . . . . . . . : $($ispInfo.DnsIP -join "`n                                         ")" -ForegroundColor Yellow
        Write-Host "   ISP Name. . . . . . . . . . . . . . : $($ispInfo.IspName -join "`n                                         ")" -ForegroundColor Yellow
        if ($showAll -eq $True)
        {
            Write-Host "   ISP Organisation. . . . . . . . . . : $($ispInfo.IspOrg -join "`n                                         ")" -ForegroundColor Yellow
            Write-Host "   ISP ASN . . . . . . . . . . . . . . : $($ispInfo.IspAs -join "`n                                         ")" -ForegroundColor Yellow
        }
        Write-Host "   ISP City. . . . . . . . . . . . . . : $($ispInfo.IspCity -join "`n                                         ")" -ForegroundColor Yellow
        Write-Host "   ISP Region. . . . . . . . . . . . . : $($ispInfo.IspRegion -join "`n                                         ")" -ForegroundColor Yellow
        Write-Host "   ISP Country . . . . . . . . . . . . : $($ispInfo.IspCountry -join "`n                                         ")" -ForegroundColor Yellow
        if ($showAll -eq $True)
        {
            Write-Host "   ISP ZIP Code. . . . . . . . . . . . : $($ispInfo.IspZip -join "`n                                         ")" -ForegroundColor Yellow
            Write-Host "   ISP Location. . . . . . . . . . . . : $($ispInfo.IspLoc -join "`n                                         ")" -ForegroundColor Yellow
            Write-Host "   ISP Timezone. . . . . . . . . . . . : $($ispInfo.IspTimezone -join "`n                                         ")" -ForegroundColor Yellow
        }
        Write-Host ""
    }

    # Display Ethernet Adapter section
    Write-Host "Network Interface Card" -ForegroundColor Green
    Write-Host ""

    <# START $group foreach loop #>
    foreach ($group in $groupedInfo) {
        # Get all IPv4 and IPv6 addresses for this interface
        $ipv4Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv4" }# | Sort-Object Name -Unique
        $ipv6Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv6" }# | Sort-Object Name -Unique
        
        $firstIPv4 = $ipv4Addresses | Select-Object -First 1
        If ($($firstIPv4.MediaConnectionState) -eq "Disconnected" -and $showAll -eq $null)
        {
            continue
        }
        
        Write-Host "Interface. . . . . . . . . . . . . . . : $($group.Name)" -ForegroundColor Cyan
        Write-Host ""
        
        # Display information for the first IPv4 entry (which has the DNS suffix and other common info)
        <# START display for ipv4 output #>
        if ($ipv4Addresses)
        {
            # OUTSIDE OF LOOP
            Write-Host "   Description . . . . . . . . . . . . : $($firstIPv4.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . . : $($firstIPv4.MediaConnectionState)" -ForegroundColor Yellow
            Write-Host "   Media Type. . . . . . . . . . . . . : $($firstIPv4.PhysicalMediaType)" -ForegroundColor Yellow
            Write-Host "   Connection-specific DNS Suffix  . . : $($firstIPv4.DnsSuffix -join "`n                                         ")" -ForegroundColor Yellow
            
            # OUTPUT IP INFO
            foreach ($info in $ipv4Addresses) {
                # Display Link-local IPv6 Address if exists
                if ($ipv6Addresses) {
                    foreach ($subInfo in $ipv6Addresses)
                    {              
                        if ($null -ne $subInfo.IPV6Address -and $subInfo.IPV6Address -notlike "fe80::*") {
                            $ipv6Address = $subInfo.IPV6Address
                            Write-Host "   IPv6 Address. . . . . . . . . . . . : $($ipv6Address)" -ForegroundColor Yellow
                            Write-Host "   IPv6 Prefix Length. . . . . . . . . : $($subInfo.PrefixLength)" -ForegroundColor Yellow
                        }
                        if ($subInfo.IPV6Address -like "fe80::*") {
                            $localLinkAddress = $subInfo.IPV6Address
                            Write-Host "   Link-local IPv6 Address . . . . . . : $($localLinkAddress)" -ForegroundColor Yellow
                            Write-Host "   Link-local IPv6 Prefix Length . . . : $($subInfo.PrefixLength)" -ForegroundColor Yellow
                        }
                    }
                }
                Write-Host "   IPv4 Address. . . . . . . . . . . . : $($info.IPAddress)" -ForegroundColor Yellow
                Write-Host "   Subnet Mask . . . . . . . . . . . . : $($info.SubnetMask)" -ForegroundColor Yellow
                Write-Host "   IPv4 Prefix Length. . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
            }
            # If wi-fi nic.
            If ($firstIPv4.PhysicalMediaType -like "*802.11*")
            {
                Write-Host "   WiFi SSID . . . . . . . . . . . . . : $($firstIPv4.wifiSSID)" -ForegroundColor Yellow
                Write-Host "   WiFi Key. . . . . . . . . . . . . . : $($firstIPv4.wifiKey)" -ForegroundColor Yellow
            }
            Write-Host "   Default Gateway . . . . . . . . . . : $($firstIPv4.DefaultGateway)" -ForegroundColor Yellow
            Write-Host "   DNS Servers . . . . . . . . . . . . : $($firstIPv4.DnsServers -split ', ' -join "`n                                         ")" -ForegroundColor Yellow
            Write-Host "   Link Speed. . . . . . . . . . . . . : $($firstIPv4.LinkSpeed)" -ForegroundColor Yellow
            # If connected show telemetry.
            If ($($firstIPv4.ReceivedBytes) -gt 0 -or $($firstIPv4.SentBytes -gt 0))
            {
                Write-Host "   Received Bytes. . . . . . . . . . . : $($firstIPv4.ReceivedBytes) MB" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . . : $($firstIPv4.SentBytes) MB" -ForegroundColor Yellow
            }
            # v0.5.0.5 Show all flag.
            If ($showAll -eq $True)
            {
                Write-Host "   Physical Address. . . . . . . . . . : $($firstIPv4.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . . : $($firstIPv4.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCPv4 variables only if DHCP is enabled
                if ($firstIPv4.DhcpEnabledV4 -eq "Yes")
                {
                    Write-Host "   DHCPv4 Server . . . . . . . . . . . : $($firstIPv4.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . . : $($firstIPv4.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . . : $($firstIPv4.dhcpLeaseTerminatesTimeV4)" -ForegroundColor Yellow
                }
                Write-Host "   DHCPv6 Enabled. . . . . . . . . . . : $($firstIPv4.DhcpEnabledV6)" -ForegroundColor Yellow
                # Display DHCPv6 variables only if DHCP is enabled
                if ($firstIPv4.DhcpEnabledV6 -eq "Yes")
                {
                    Write-Host "   DHCPv6 IAID . . . . . . . . . . . . : $($firstIPv4.Dhcpv6Iaid)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 Client DUID. . . . . . . . . : $($firstIPv4.Dhcpv6Duid)" -ForegroundColor Yellow
                    if ($firstIPv4.dhcpLeaseObtainedTimeV6)
                    {
                        Write-Host "   Leasev6 Obtained. . . . . . . . . . : $($firstIPv4.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                        Write-Host "   Leasev6 Expires . . . . . . . . . . : $($firstIPv4.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                    }
                }
                
                Write-Host "   Autoconfiguration Enabled . . . . . : $($firstIPv4.AutoconfigurationEnabled)" -ForegroundColor Yellow
                Write-Host "   NetBIOS over Tcpip. . . . . . . . . : $($firstIPv4.NetbiosEnabled)" -ForegroundColor Yellow
            }
            # Line space.
            Write-Host ""
        }
        <# END display for ipv4 output #>
        
        <# START Display IPv6 addresses that do not have an IPv4 shared adapter (if any) #>
        if ($ipv6Addresses -and !$ipv4Addresses)
        {
            $firstIPv6 = $ipv6Addresses | Select-Object -First 1
            If ($($firstIPv6.MediaConnectionState) -eq "Disconnected" -and $showAll -eq $null)
            {
                continue
            }
            Write-Host "Interface. . . . . . . . . . . . . . . : $($group.Name)" -ForegroundColor Cyan
            Write-Host ""
            # OUTSIDE THE LOOP.
            Write-Host "   Description . . . . . . . . . . . . : $($firstIPv6.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . . : $($firstIPv6.MediaConnectionState)" -ForegroundColor Yellow
            Write-Host "   Media Type. . . . . . . . . . . . . : $($firstIPv6.PhysicalMediaType)" -ForegroundColor Yellow
            Write-Host "   Connection-specific DNS Suffix  . . : $($firstIPv6.DnsSuffix -join "`n                                         ")" -ForegroundColor Yellow

            # GET IPv6 loop.
            foreach ($info in $ipv6Addresses) 
            {
                if ($null -ne $info.IPV6Address -and $info.IPV6Address -notlike "fe80::*")
                    {
                        $ipv6Address = $info.IPV6Address
                        Write-Host "   IPv6 Address. . . . . . . . . . . . : $($ipv6Address)" -ForegroundColor Yellow
                        Write-Host "   IPv6 Prefix Length. . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                    }
                    if ($info.IPV6Address -like "fe80::*")
                    {
                        $localLinkAddress = $info.IPV6Address
                        Write-Host "   Link-local IPv6 Address . . . . . . : $($localLinkAddress)" -ForegroundColor Yellow
                        Write-Host "   Link-local IPv6 Prefix Length . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                    }
            }
            Write-Host "   Autoconfiguration Enabled . . . . . : $($firstIPv6.AutoconfigurationEnabled)" -ForegroundColor Yellow
            Write-Host "   NetBIOS over Tcpip. . . . . . . . . : $($firstIPv6.NetbiosEnabled)" -ForegroundColor Yellow
            # If wifi show info.      
            If ($firstIPv6.PhysicalMediaType -like "*802.11*")
            {
                Write-Host "   WiFi SSID . . . . . . . . . . . . . : $($firstIPv6.wifiSSID)" -ForegroundColor Yellow
                Write-Host "   WiFi Key. . . . . . . . . . . . . . : $($firstIPv6.wifiKey)" -ForegroundColor Yellow
            }
            Write-Host "   Default Gateway . . . . . . . . . . : $($firstIPv6.DefaultGateway)" -ForegroundColor Yellow
            Write-Host "   DNS Servers . . . . . . . . . . . . : $($firstIPv6.DnsServers -split ', ' -join "`n                                         ")" -ForegroundColor Yellow
            Write-Host "   Link Speed. . . . . . . . . . . . . : $($firstIPv6.LinkSpeed)" -ForegroundColor Yellow
            # If NIC connected show telemetry.
            If ($($firstIPv6.ReceivedBytes) -gt 0 -or $($firstIPv6.SentBytes -gt 0))
            {
                Write-Host "   Received Bytes. . . . . . . . . . . : $($firstIPv6.ReceivedBytes)" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . . : $($firstIPv6.SentBytes)" -ForegroundColor Yellow
            }
            # v0.5.0.5 Show all switch.
            If ($showAll -eq $True)
            {
                Write-Host "   Physical Address. . . . . . . . . . : $($firstIPv6.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . . : $($firstIPv6.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCPv4 variables only if DHCP is enabled
                if ($firstIPv6.DhcpEnabledV4 -eq "Yes") {
                    Write-Host "   DHCPv4 Server . . . . . . . . . . . : $($firstIPv6.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . . : $($firstIPv6.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . . : $($firstIPv6.dhcpLeaseTerminatesTimev4)" -ForegroundColor Yellow
                }
                Write-Host "   DHCPv6 Enabled. . . . . . . . . . . : $($firstIPv6.DhcpEnabledV6)" -ForegroundColor Yellow
                # Display DHCPv6 variables only if DHCP is enabled
                if ($firstIPv6.DhcpEnabledV6 -eq "Yes") {
                    Write-Host "   DHCPv6 IAID . . . . . . . . . . . . : $($firstIPv6.Dhcpv6Iaid)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 Client DUID. . . . . . . . . : $($firstIPv6.Dhcpv6Duid)" -ForegroundColor Yellow
                    if ($firstIPv6.dhcpLeaseObtainedTimeV6)
                    {
                        Write-Host "   Leasev6 Obtained. . . . . . . . . . : $($firstIPv6.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                        Write-Host "   Leasev6 Expires . . . . . . . . . . : $($firstIPv6.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                    }
                }
            }
            # Line space.
            Write-Host ""
        } 
        <# END display for ipv6 output #>
    } <# END $group foreach loop #>
    # Line space.
    Write-Host ""
}
<# DISPLAY OUTPUT FUNCTION END #>
<# === END FUNCTIONS ===#>

<# Args switches for all #>
if ($args -contains "/all")
{
    $showAll = $True
}
if ($args -contains "/version")
{
    Get-Version
}
if ($args -contains "/release")
{
    Invoke-IPConfigRelease
}
if ($args -contains "/renew")
{
    Invoke-IPConfigRenew
}
if ($args -contains "/flushdns")
{
    Invoke-FlushDNS
}
if ($args -contains "/resetwinsock")
{
    Invoke-ResetWinsock
}
Display-Output