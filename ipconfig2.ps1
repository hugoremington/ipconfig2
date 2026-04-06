# Script metadata
$author = "Hugo Remington"
$version = "1.0.1.0"
$date = "06-Apr-2026. 12:47"
$timestamp = (Get-Date -Format "dd-MMM-yyyy, HH.mm.ss.fff")
# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)


<# === FUNCTIONS START === #>
# v1.0.0.0 MAIN Detect CIM / WMI. CIM Query for Win32_NetworkAdapterConfiguration. Use this in memory using return/param, rather than calling it over again.
function Get-SystemType
{
    $CIMWin32_NetworkAdapterConfiguration = Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue
    if ($CIMWin32_NetworkAdapterConfiguration.Count -gt 0)
    {
        $NetworkAdapterConfiguration = $CIMWin32_NetworkAdapterConfiguration
        $queryType = "CIM"
    }
    else
    {
        # If CIM is not available on the system, then fallback to WMIObject. Provides legacy OS compatibility.
        $NetworkAdapterConfiguration = Get-WmiObject Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue
        $queryType = "WMI"
    }
    return [PSCustomObject]@{
        NetworkAdapterConfiguration = $NetworkAdapterConfiguration
        QueryType                   = $queryType
    }
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
    param($flushDnsOutput)
    try {
        # Check if Clear-DnsClientCache is available
        if (Get-Command Clear-DnsClientCache -ErrorAction SilentlyContinue) {
            # Get total DNS cache entry count.
            $DNSCacheCount = (Get-DnsClientCache).Count
            # Clear DNS Cace.
            Clear-DnsClientCache
            $flushDnsOutput += "$DNSCacheCount DNS cache entries flushed. Timestamp: $timestamp.`n"
        }
    }
    catch {
        $flushDnsOutput += "Unable to flush DNS cache: $($_.Exception.Message)"
        #throw
    }
$flushDnsOutput += "`n`n"
return @{
        FlushDnsOutput = $flushDnsOutput
    }
}

function Invoke-ResetWinsock {
    <#
    .SYNOPSIS
        Resets the Winsock catalog to a clean state, removing any custom LSPs to resolve network problems caused by corrupted Winsock settings. It doesn't affect Winsock Name Space Provider entries.
    
    .DESCRIPTION
        This function reset Winsock using netsh. Requires elevation and restart.
    #>
    [CmdletBinding()]
    param($resetWinsockOutput)
    try {       
        if (-not $isAdmin) {
            $resetWinsockOutput += "Reset Winsock operation requires administrator privileges. Please run as administrator.`n"
        }
        else
        {
            # Execute netsh and suppress its output
            $null = netsh winsock reset
            if ($LASTEXITCODE -eq 0) {
                $resetWinsockOutput += "Successfully reset the Winsock Catalog. Timestamp: $timestamp.`n"
                $resetWinsockOutput += "You must restart the computer in order to complete the reset.`n"
            } else {
                $resetWinsockOutput += "Winsock reset failed with exit code: $LASTEXITCODE `n"
            }
        }
        
    }
    catch {
        $resetWinsockOutput += "Unable to reset Winsock.`n"
        #throw
    }
$resetWinsockOutput += "`n`n"
return @{
        ResetWinsockOutput = $resetWinsockOutput
    }
}

## New Functions for IP Configuration Management
# v1.0.0.0 refactored Invoke-IPConfigRelease function, now more efficient, faster and no more nested loops.
function Invoke-IPConfigRelease {  
    [CmdletBinding()]
    param (
        $IpReleaseOutput
        #$NetworkAdapterConfiguration,
        #$QueryType
    )

    try {
        # Try CimInstance method first (native PowerShell)
        $IpReleaseOutput += "Releasing DHCP IP addresses...`n`n"
        if ($queryType -eq "CIM")
        {
            $getCimQuery = $NetworkAdapterConfiguration | Where-Object { $_.DHCPEnabled -eq $True} -ErrorAction SilentlyContinue
            $adapters = $getCimQuery
        }
        elseif ($queryType -eq "WMI")
        {
            # Else fallback on WMI.
            $getWmiQuery = $NetworkAdapterConfiguration | Where-Object { $_.DHCPEnabled -eq $True} -ErrorAction SilentlyContinue
            $adapters = $getWmiQuery
        }
        else
        {
            $IpRenewOutput += "System does not support either CIM or WMI. IP renew will not function."
        }

        foreach ($adapter in $adapters) {
            # Update timestamp in the loop for correct progress.
            $timestamp = (Get-Date -Format "dd/MMM/yyyy, HH:mm:ss.fff")

            if ($queryType -eq "CIM")
            {
                # Using modern CimInstance for renew.
                $result = $adapter | Invoke-CimMethod -MethodName "ReleaseDHCPLease"
                if ($result.ReturnValue -eq 0) {
                    $IpReleaseOutput += "Successfully released IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
                else {
                    $IpReleaseOutput += "Failed to release IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
            }
            elseif ($queryType -eq "WMI")
            {
                # Using classic WMIObject for release.
                $result = $adapter | ForEach-Object { $_.ReleaseDHCPLease() }
                if ($result.ReturnValue -eq 0) {
                    $IpReleaseOutput += "Successfully released IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
                else {
                    $IpReleaseOutput += "Failed to release IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
            }
            else
            {
                $IpReleaseOutput += "Failed to release IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
            }
        }
    }
    #Start-Sleep 5
    catch {
        $IpReleaseOutput += "Failed to release IP configuration: $($_.Exception.Message)"
    }
    $IpReleaseOutput += "`n`n"
    return @{
        IpReleaseOutput = $IpReleaseOutput
    }
}

# v1.0.0.0 refactored Invoke-IPConfigRenew function, now more efficient, faster and no more nested loops.
function Invoke-IPConfigRenew {
    [CmdletBinding()]
    param (
        $IpRenewOutput
    )
    try {
        # Try CimInstance method first (native PowerShell)
        $IpRenewOutput += "Renewing DHCP IP addresses...`n`n"
        if ($queryType -eq "CIM")
        {
            $getCimQuery = $NetworkAdapterConfiguration | Where-Object { $_.DHCPEnabled -eq $True -and $_.IPEnabled -eq $True } -ErrorAction SilentlyContinue
            $adapters = $getCimQuery
        }
        elseif ($queryType -eq "WMI")
        {
            # Else fallback on WMI.
            $getWmiQuery = $NetworkAdapterConfiguration | Where-Object { $_.DHCPEnabled -eq $True -and $_.IPEnabled -eq $True } -ErrorAction SilentlyContinue
            $adapters = $getWmiQuery
        }
        else
        {
            $IpRenewOutput += "System does not support either CIM or WMI. IP renew will not function."
        }
        foreach ($adapter in $adapters) {
            # Update timestamp in the loop for correct progress.
            $timestamp = (Get-Date -Format "dd/MMM/yyyy, HH:mm:ss.fff")

            if ($queryType -eq "CIM")
            {
                # Using modern CimInstance for renew.
                $result = $adapter | Invoke-CimMethod -MethodName "RenewDHCPLease"
                if ($result.ReturnValue -eq 0) {
                    $IpRenewOutput += "Successfully renewed IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
                else {
                    $IpRenewOutput += "Failed to renew IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
            }
            elseif ($queryType -eq "WMI")
            {
                # Using classic WMIObject for renew.
                $result = $adapter | ForEach-Object { $_.RenewDHCPLease() }
                if ($result.ReturnValue -eq 0) {
                    $IpRenewOutput += "Successfully renewed IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
                else {
                    $IpRenewOutput += "Failed to renew IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
                }
            }
            else
            {
                $IpRenewOutput += "Failed to renew IP on $($adapter.Description) $($adapter.ServiceName). Timestamp: $timestamp.`n"
            }
        }
    }
    #Start-Sleep 5
    catch {
        $IpRenewOutput += "Failed to renew IP configuration: $($_.Exception.Message)"
    }
    $IpRenewOutput += "`n`n"
    return @{
        IpRenewOutput = $IpRenewOutput
    }
}

function Get-AllSystemInfo {
    param (
        )
        
    function Get-Metadata {
        param (
        )
        $hostname = [System.Environment]::MachineName
        $netProfileName = $null
        $netProfileCategory = $null
        $netIPv4Connectivity = $null
        $netIPv6Connectivity = $null
        $primaryDnsSuffix = $null
        $dnsSuffixSearchList = $null
        $netNodeType = $null
        $netNodeTypeQuery = $null
        $tcpipParams = $null
        # $wifiProfileName = $null
        $tcpipParams = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" -ErrorAction SilentlyContinue
        $registryPathNetBT = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters" -ErrorAction SilentlyContinue
        $NetConnectionQuery = Get-NetConnectionProfile
        # Get Net Node Type in v0.5.0.6.
        $netNodeTypeQuery = $registryPathNetBT.NodeType
        if (!$netNodeTypeQuery) {$netNodeType = "Hybrid"} elseif ($netNodeTypeQuery -eq 0) {$netNodeType = "Unknown"} elseif ($netNodeTypeQuery -eq 1) {$netNodeType = "Broadcast"} elseif ($netNodeTypeQuery -eq 2) {$netNodeType = "Peer-Peer"} elseif ($netNodeTypeQuery -eq 4) {$netNodeType = "Mixed"} elseif ($netNodeTypeQuery -eq 8) {$netNodeType = "Hybrid"} else {$netNodeType = "Unknown"}

        # Net profile metadata
        if ($NetConnectionQuery) {
            $netProfileName = $NetConnectionQuery.Name
            $netProfileType = $NetConnectionQuery.InterfaceAlias
            <# # v1.0.0.0 Check WiFi
            if ($netProfileType -eq "WiFi")
            {
                $wifiProfileName = $netProfileName
            }
            else
            {
                $wifiProfileName = $null
            }#> 
            $netProfileCategory = $NetConnectionQuery.NetworkCategory
            $netIPv4Connectivity = $NetConnectionQuery.IPv4Connectivity
            $netIPv6Connectivity = $NetConnectionQuery.IPv6Connectivity
        }
        else {
            $netProfileName = $null
            $netProfileType = $null
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
        $primaryDnsSuffix = $($NetworkAdapterConfiguration.DNSDomain) | Where-Object { $_ }
        
        # Get dns suffix search list.
        $searchList = $NetworkAdapterConfiguration.DNSDomainSuffixSearchOrder | Where-Object { $_ }
        if ($searchList -is [array]) {
            $dnsSuffixSearchList = $searchList
        }
        elseif ($searchList) {
            $dnsSuffixSearchList = $searchList
        }

        return [PSCustomObject]@{
            Hostname                                = $hostname
            primaryDnsSuffix                        = $primaryDnsSuffix | Select-Object -Unique
            NetProfileName                          = $netProfileName | Select-Object -Unique
            # netProfileType                          = $netProfileType | Select-Object -Unique
            # WifiProfileName                         = $wifiProfileName | Select-Object -Unique
            NetProfileCategory                      = $netProfileCategory | Select-Object -Unique
            NetIPv4Connectivity                     = $netIPv4Connectivity | Select-Object -Unique
            NetIPv6Connectivity                     = $netIPv6Connectivity | Select-Object -Unique
            IPRoutingEnabled                        = $ipRoutingEnabled
            WINSProxyEnabled                        = $winsProxyEnabled
            DNSSuffixSearchList                     = $dnsSuffixSearchList | Select-Object -Unique
            NetNodeType                             = $netNodeType
            QueryType                               = $queryType
        }
    } # End Get Metadata.



    # Start ISP Job.
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

    # Run metadata function synchronously with Start-Job threads. Need this prior Get-LocalNicIpData variables.
    $metadata = Get-Metadata

    # Get NIC JOB.
    $nicJob = Start-Job -ScriptBlock {
        param (
            $NetworkAdapterConfiguration
        )
        <# ===START GET LOCAL NIC IP DATA FUNCTION=== #>
        function Get-LocalNicIpData {
            param (
                $NetworkAdapterConfiguration
            )
            $NetConnectionQuery = Get-NetConnectionProfile # For WiFi.
            
            # Net profile metadata
            if ($NetConnectionQuery) {
                $netProfileName = $NetConnectionQuery.Name
                $netProfileType = $NetConnectionQuery.InterfaceAlias
                # v1.0.0.0 Check WiFi
                if ($netProfileType -eq "WiFi")
                {
                    $wifiProfileName = $netProfileName
                }
                else
                {
                    $wifiProfileName = $null
                }
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

            try { # v0.3.0.0 try/catch block for exception handling.

                # Create local NIC array.
                $nicInfo= @()

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
                    $netbiosQuery = $NetworkAdapterConfiguration # Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration -ErrorAction SilentlyContinue # Have to call it again, as entire array does not get parsed into it properly using Argumentlist/Param.
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
                                    $matchingProfile = $allProfiles | Where-Object { $_ -like "*$wifiProfileName*" } | Select-Object -First 1
                                    
                                    # If no match found, try searching the other way around
                                    if (-not $matchingProfile) {
                                        $matchingProfile = $allProfiles | Where-Object { $wifiProfileName -like "*$_*" } | Select-Object -First 1
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
                                # $output += "Error: $_"
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
                            $registryItemV4 = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$interfaceGuid" -ErrorAction SilentlyContinue
                            $registryItemV6 = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$interfaceGuid" -ErrorAction SilentlyContinue
                            $registryItemV6DUID = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters" -ErrorAction SilentlyContinue
                            
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
                            $nicInfo+= [PSCustomObject]@{
                                MediaConnectionState = [String]$adapter.MediaConnectionState
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
                                NetbiosEnabled = [String]$netbiosEnabled
                                WifiSsid = $wifiSsid
                                WifiKey = $wifiKey
                                ReceivedBytes = $ReceivedBytes
                                SentBytes = $SentBytes
                            }
                        }
                        
                        # Get IPv6 addresses
                        $ipv6Addresses = $getAllIpAddresses | Where-Object {$_.AddressFamily -eq "IPv6"}
                        
                        foreach ($ipV6 in $ipv6Addresses) {
                            $nicInfo+= [PSCustomObject]@{
                                MediaConnectionState = [String]$adapter.MediaConnectionState
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
                                NetbiosEnabled = [String]$netbiosEnabled
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
            }
            return $nicInfo
        } <# ===END GET LOCAL NIC IP DATA FUNCTION=== #>
        Get-LocalNicIpData -NetworkAdapterConfiguration $NetworkAdapterConfiguration
    } -ArgumentList (,$NetworkAdapterConfiguration) # Using comma prefix to parse array, instead of first value only.



    # Collect Job threads result
    Wait-Job -Job $ispJob, $nicJob -Timeout 10 | Out-Null

    $IspInfo        =   $null
    try {
        $IspInfo =      Receive-Job -Job $ispJob -ErrorAction SilentlyContinue
    } catch {}

    $nicInfo       =   $null
    try {
        $nicInfo=      Receive-Job -Job $nicJob -ErrorAction SilentlyContinue
    } catch {}

    Remove-Job -Job $ispJob, $nicJob -Force -ErrorAction SilentlyContinue

    return @{
        Metadata = $metadata
        IspInfo  = $IspInfo
        NicInfo  = $NicInfo
    }
}




<# DISPLAY OUTPUT START FUNCTION #>
function Display-Output {
    # Capture output in a memory variable instead of writing directly to console
    $output = ""

    # Get-Version function inside Display-Output function.
    function Get-Version
    {
        $output += "Author: $author | Version: $version | Release date: $date `n`n`n"
        return $output
    }
    
    # Splash screen
    $output += "`n`n"
    $output += "Windows IP Configuration 2.0"
    $output += "`n`n`n"
    # Splash screen end.
    
    # Version screen
    if ($getVersion -eq $True)
    {
        $output += Get-Version
    }
    # Version screen end.


    # v1.0.0.0 System type CIM/WMI variables, required for other functions.
    $NetworkAdapterConfiguration = (Get-SystemType).NetworkAdapterConfiguration
    $QueryType = (Get-SystemType).QueryType
    
    if ($IpReleaseSwitch -eq $True)
    {
        $output += (Invoke-IPConfigRelease).IpReleaseOutput
    }
    if ($IpRenewSwitch -eq $True)
    {
        $output += (Invoke-IPConfigRenew).IpRenewOutput
    }
    if ($FlushDnsSwitch -eq $True)
    {
        $output += (Invoke-FlushDNS).FlushDnsOutput
    }
    if ($ResetWinSockSwitch -eq $True)
    {
        $output += (Invoke-ResetWinsock).ResetWinsockOutput
    }

    # v0.5.0.5 GET ALL DISPLAY VARIABLES.
    # v0.4.0.2 Master function
    $allInfo = Get-AllSystemInfo
    $metadata = $allInfo.Metadata
    # v1.0.0.0 Must get Local NIC IP AFTER release/renew functions. Not BEFORE.
    # v0.5.0.5 Run Local Nic function.
    $nicInfo= $allInfo.NicInfo
    # v0.4.0.1 new Get-ISP Function
    $IspInfo = $allInfo.IspInfo
    # Group by interface name and display consolidated information
    $groupedInfo = $nicInfo | Group-Object InterfaceName
    # v1.0.0.0 Call args functions first.
 


    
    $output += "   Host Name . . . . . . . . . . . . . : $($metadata.Hostname -join "`n                                         ")" + "`n"
    $output += "   Primary Dns Suffix  . . . . . . . . : $($metadata.primaryDnsSuffix -join "`n                                         ")" + "`n"
    $output += "   Node Type . . . . . . . . . . . . . : $($metadata.NetNodeType -join "`n                                         ")" + "`n"
    $output += "   Network Profile Name. . . . . . . . : $($metadata.NetProfileName -join "`n                                         ")" + "`n"
    $output += "   Network Profile Type. . . . . . . . : $($metadata.NetProfileCategory -join "`n                                         ")" + "`n"
    if ($showAll -eq $True)
    {
        $output += "   IP Routing Enabled. . . . . . . . . : $($metadata.IPRoutingEnabled)" + "`n"
        $output += "   WINS Proxy Enabled. . . . . . . . . : $($metadata.WINSProxyEnabled)" + "`n"
        $output += "   DNS Suffix Search List. . . . . . . : $($metadata.DNSSuffixSearchList -join "`n                                         ")" + "`n"
    }
    $output += "   IPv4 Connectivity . . . . . . . . . : $($metadata.NetIPv4Connectivity -join "`n                                         ")" + "`n"
    $output += "   IPv6 Connectivity . . . . . . . . . : $($metadata.NetIPv6Connectivity -join "`n                                         ")" + "`n"
    $output += "`n"

    # v0.3.0.0 logic checks
    if ($IspInfo)
    {
        # Display information
        $output += "Public IP Address" + "`n"
        $output += "`n"
        $output += "   Public IPv4 Address . . . . . . . . : $($ispInfo.IspIP -join "`n                                         ")" + "`n"
        $output += "   Public DNS Server . . . . . . . . . : $($ispInfo.DnsIP -join "`n                                         ")" + "`n"
        $output += "   ISP Name. . . . . . . . . . . . . . : $($ispInfo.IspName -join "`n                                         ")" + "`n"
        if ($showAll -eq $True)
        {
            $output += "   ISP Organisation. . . . . . . . . . : $($ispInfo.IspOrg -join "`n                                         ")" + "`n"
            $output += "   ISP ASN . . . . . . . . . . . . . . : $($ispInfo.IspAs -join "`n                                         ")" + "`n"
        }
        $output += "   ISP City. . . . . . . . . . . . . . : $($ispInfo.IspCity -join "`n                                         ")" + "`n"
        $output += "   ISP Region. . . . . . . . . . . . . : $($ispInfo.IspRegion -join "`n                                         ")" + "`n"
        $output += "   ISP Country . . . . . . . . . . . . : $($ispInfo.IspCountry -join "`n                                         ")" + "`n"
        if ($showAll -eq $True)
        {
            $output += "   ISP ZIP Code. . . . . . . . . . . . : $($ispInfo.IspZip -join "`n                                         ")" + "`n"
            $output += "   ISP Location. . . . . . . . . . . . : $($ispInfo.IspLoc -join "`n                                         ")" + "`n"
            $output += "   ISP Timezone. . . . . . . . . . . . : $($ispInfo.IspTimezone -join "`n                                         ")" + "`n"
        }
        $output += "`n"
    }

    # Display Ethernet Adapter section
    $output += "Network Interface Card" + "`n"
    $output += "`n"

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
        
        # Display information for the first IPv4 entry (which has the DNS suffix and other common info)
        <# START display for ipv4 output #>
        if ($ipv4Addresses)
        {
            $output += "Interface. . . . . . . . . . . . . . . : $($group.Name)" + "`n"
            $output += "`n"
            # OUTSIDE OF LOOP
            $output += "   Description . . . . . . . . . . . . : $($firstIPv4.InterfaceDescription)" + "`n"
            $output += "   Media State . . . . . . . . . . . . : $($firstIPv4.MediaConnectionState)" + "`n"
            $output += "   Media Type. . . . . . . . . . . . . : $($firstIPv4.PhysicalMediaType)" + "`n"
            $output += "   Connection-specific DNS Suffix  . . : $($firstIPv4.DnsSuffix -join "`n                                         ")" + "`n"
            
            # OUTPUT IP INFO
            foreach ($info in $ipv4Addresses) {
                # Display Link-local IPv6 Address if exists
                if ($ipv6Addresses) {
                    foreach ($subInfo in $ipv6Addresses)
                    {              
                        if ($null -ne $subInfo.IPV6Address -and $subInfo.IPV6Address -notlike "fe80::*") {
                            $ipv6Address = $subInfo.IPV6Address
                            $output += "   IPv6 Address. . . . . . . . . . . . : $($ipv6Address)" + "`n"
                            $output += "   IPv6 Prefix Length. . . . . . . . . : $($subInfo.PrefixLength)" + "`n"
                        }
                        if ($subInfo.IPV6Address -like "fe80::*") {
                            $localLinkAddress = $subInfo.IPV6Address
                            $output += "   Link-local IPv6 Address . . . . . . : $($localLinkAddress)" + "`n"
                            $output += "   Link-local IPv6 Prefix Length . . . : $($subInfo.PrefixLength)" + "`n"
                        }
                    }
                }
                $output += "   IPv4 Address. . . . . . . . . . . . : $($info.IPAddress)" + "`n"
                $output += "   Subnet Mask . . . . . . . . . . . . : $($info.SubnetMask)" + "`n"
                $output += "   IPv4 Prefix Length. . . . . . . . . : $($info.PrefixLength)" + "`n"
            }
            # If wi-fi nic.
            If ($firstIPv4.PhysicalMediaType -like "*802.11*" -and $($firstIPv4.MediaConnectionState) -eq "Connected")
            {
                $output += "   WiFi SSID . . . . . . . . . . . . . : $($firstIPv4.wifiSsid)" + "`n"
                $output += "   WiFi Key. . . . . . . . . . . . . . : $($firstIPv4.wifiKey)" + "`n"
            }
            elseif ($firstIPv4.PhysicalMediaType -like "*802.11*" -and $($firstIPv4.MediaConnectionState) -eq "Disconnected")
            {
                $output += "   WiFi SSID (Last Known). . . . . . . : $($firstIPv4.wifiSsid)" + "`n"
                $output += "   WiFi Key (Last Known) . . . . . . . : $($firstIPv4.wifiKey)" + "`n"
            }
            $output += "   Default Gateway . . . . . . . . . . : $($firstIPv4.DefaultGateway)" + "`n"
            $output += "   DNS Servers . . . . . . . . . . . . : $($firstIPv4.DnsServers -split ', ' -join "`n                                         ")" + "`n"
            $output += "   Link Speed. . . . . . . . . . . . . : $($firstIPv4.LinkSpeed)" + "`n"
            # If connected show telemetry.
            If ($($firstIPv4.ReceivedBytes) -gt 0 -or $($firstIPv4.SentBytes -gt 0))
            {
                $output += "   Received Bytes. . . . . . . . . . . : $($firstIPv4.ReceivedBytes) MB" + "`n"
                $output += "   Sent Bytes. . . . . . . . . . . . . : $($firstIPv4.SentBytes) MB" + "`n"
            }
            # v0.5.0.5 Show all flag.
            If ($showAll -eq $True)
            {
                $output += "   Physical Address. . . . . . . . . . : $($firstIPv4.MacAddress)" + "`n"
                $output += "   DHCPv4 Enabled. . . . . . . . . . . : $($firstIPv4.DhcpEnabledV4)" + "`n"
                # Display DHCPv4 variables only if DHCP is enabled
                if ($firstIPv4.DhcpEnabledV4 -eq "Yes")
                {
                    $output += "   DHCPv4 Server . . . . . . . . . . . : $($firstIPv4.DhcpServerV4)" + "`n"
                    $output += "   Lease Obtained. . . . . . . . . . . : $($firstIPv4.dhcpLeaseObtainedTimeV4)" + "`n"
                    $output += "   Lease Expires . . . . . . . . . . . : $($firstIPv4.dhcpLeaseTerminatesTimeV4)" + "`n"
                }
                $output += "   DHCPv6 Enabled. . . . . . . . . . . : $($firstIPv4.DhcpEnabledV6)" + "`n"
                # Display DHCPv6 variables only if DHCP is enabled
                if ($firstIPv4.DhcpEnabledV6 -eq "Yes")
                {
                    $output += "   DHCPv6 IAID . . . . . . . . . . . . : $($firstIPv4.Dhcpv6Iaid)" + "`n"
                    $output += "   DHCPv6 Client DUID. . . . . . . . . : $($firstIPv4.Dhcpv6Duid)" + "`n"
                    if ($firstIPv4.dhcpLeaseObtainedTimeV6)
                    {
                        $output += "   Leasev6 Obtained. . . . . . . . . . : $($firstIPv4.dhcpLeaseObtainedTimeV6)" + "`n"
                        $output += "   Leasev6 Expires . . . . . . . . . . : $($firstIPv4.dhcpLeaseTerminatesTimeV6)" + "`n"
                    }
                }
                
                $output += "   Autoconfiguration Enabled . . . . . : $($firstIPv4.AutoconfigurationEnabled)" + "`n"
                $output += "   NetBIOS over Tcpip. . . . . . . . . : $($firstIPv4.NetbiosEnabled)" + "`n"
            }
            # Line space.
            $output += "`n"
        }
        <# END display for ipv4 output #>
        
        
        <# START Display IPv6 addresses that do not have an IPv4 shared adapter (if any) #>
        $firstIPv6 = $ipv6Addresses | Select-Object -First 1
        If ($($firstIPv6.MediaConnectionState) -eq "Disconnected" -and $showAll -eq $null)
        {
            continue
        }

        if ($ipv6Addresses -and !$ipv4Addresses)
        {
            $output += "Interface. . . . . . . . . . . . . . . : $($group.Name)" + "`n"
            $output += "`n"
            # OUTSIDE THE LOOP.
            $output += "   Description . . . . . . . . . . . . : $($firstIPv6.InterfaceDescription)" + "`n"
            $output += "   Media State . . . . . . . . . . . . : $($firstIPv6.MediaConnectionState)" + "`n"
            $output += "   Media Type. . . . . . . . . . . . . : $($firstIPv6.PhysicalMediaType)" + "`n"
            $output += "   Connection-specific DNS Suffix  . . : $($firstIPv6.DnsSuffix -join "`n                                         ")" + "`n"

            # GET IPv6 loop.
            foreach ($info in $ipv6Addresses) 
            {
                if ($null -ne $info.IPV6Address -and $info.IPV6Address -notlike "fe80::*")
                    {
                        $ipv6Address = $info.IPV6Address
                        $output += "   IPv6 Address. . . . . . . . . . . . : $($ipv6Address)" + "`n"
                        $output += "   IPv6 Prefix Length. . . . . . . . . : $($info.PrefixLength)" + "`n"
                    }
                    if ($info.IPV6Address -like "fe80::*")
                    {
                        $localLinkAddress = $info.IPV6Address
                        $output += "   Link-local IPv6 Address . . . . . . : $($localLinkAddress)" + "`n"
                        $output += "   Link-local IPv6 Prefix Length . . . : $($info.PrefixLength)" + "`n"
                    }
            }
            # If wifi show info.      
            If ($firstIPv6.PhysicalMediaType -like "*802.11*" -and $($firstIPv4.MediaConnectionState) -eq "Connected")
            {
                $output += "   WiFi SSID . . . . . . . . . . . . . : $($firstIPv6.wifiSsid)" + "`n"
                $output += "   WiFi Key. . . . . . . . . . . . . . : $($firstIPv6.wifiKey)" + "`n"
            }
            elseif ($firstIPv6.PhysicalMediaType -like "*802.11*" -and $($firstIPv4.MediaConnectionState) -eq "Disconnected")
            {
                $output += "   WiFi SSID (Last Known). . . . . . . : $($firstIPv6.wifiSsid)" + "`n"
                $output += "   WiFi Key (Last Known) . . . . . . . : $($firstIPv6.wifiKey)" + "`n"
            }
            $output += "   Default Gateway . . . . . . . . . . : $($firstIPv6.DefaultGateway)" + "`n"
            $output += "   DNS Servers . . . . . . . . . . . . : $($firstIPv6.DnsServers -split ', ' -join "`n                                         ")" + "`n"
            $output += "   Link Speed. . . . . . . . . . . . . : $($firstIPv6.LinkSpeed)" + "`n"
            # If NIC connected show telemetry.
            If ($($firstIPv6.ReceivedBytes) -gt 0 -or $($firstIPv6.SentBytes -gt 0))
            {
                $output += "   Received Bytes. . . . . . . . . . . : $($firstIPv6.ReceivedBytes)" + "`n"
                $output += "   Sent Bytes. . . . . . . . . . . . . : $($firstIPv6.SentBytes)" + "`n"
            }
            # v0.5.0.5 Show all switch.
            If ($showAll -eq $True)
            {
                $output += "   Physical Address. . . . . . . . . . : $($firstIPv6.MacAddress)" + "`n"
                $output += "   DHCPv4 Enabled. . . . . . . . . . . : $($firstIPv6.DhcpEnabledV4)" + "`n"
                # Display DHCPv4 variables only if DHCP is enabled
                if ($firstIPv6.DhcpEnabledV4 -eq "Yes") {
                    $output += "   DHCPv4 Server . . . . . . . . . . . : $($firstIPv6.DhcpServerV4)" + "`n"
                    $output += "   Lease Obtained. . . . . . . . . . . : $($firstIPv6.dhcpLeaseObtainedTimeV4)" + "`n"
                    $output += "   Lease Expires . . . . . . . . . . . : $($firstIPv6.dhcpLeaseTerminatesTimev4)" + "`n"
                }
                $output += "   DHCPv6 Enabled. . . . . . . . . . . : $($firstIPv6.DhcpEnabledV6)" + "`n"
                # Display DHCPv6 variables only if DHCP is enabled
                if ($firstIPv6.DhcpEnabledV6 -eq "Yes") {
                    $output += "   DHCPv6 IAID . . . . . . . . . . . . : $($firstIPv6.Dhcpv6Iaid)" + "`n"
                    $output += "   DHCPv6 Client DUID. . . . . . . . . : $($firstIPv6.Dhcpv6Duid)" + "`n"
                    if ($firstIPv6.dhcpLeaseObtainedTimeV6)
                    {
                        $output += "   Leasev6 Obtained. . . . . . . . . . : $($firstIPv6.dhcpLeaseObtainedTimeV6)" + "`n"
                        $output += "   Leasev6 Expires . . . . . . . . . . : $($firstIPv6.dhcpLeaseTerminatesTimeV6)" + "`n"
                    }
                }
                $output += "   Autoconfiguration Enabled . . . . . : $($firstIPv6.AutoconfigurationEnabled)" + "`n"
                $output += "   NetBIOS over Tcpip. . . . . . . . . : $($firstIPv6.NetbiosEnabled)" + "`n"
            }
            # Line space.
            $output += "`n"
        } 
        <# END display for ipv6 output #>
    } <# END $group foreach loop #>
    # Line space.
    $output += "`n"
    $output += "   Timestamp . . . . . . . . . . . . . : $timestamp `n`n"
    
    return @{
        Output   = $output
        Metadata = $metadata
    }
}
<# DISPLAY OUTPUT FUNCTION END #>

# Save to file function START.
function Invoke-SaveFile
{
    param (
        [String]$filePath,
        [String]$output,
        [String]$hostname
    )
    try
    {       
        # Check if /outfile is followed by a path
        $outFileArg = $filePath | Where-Object { $_ -like "/outfile:*" } | Select-Object -First 1
        if ($outFileArg)
        {
            $filePath = $outFileArg -replace "/outfile:", ""
            try {
                $directory = Split-Path $filePath -Parent
                if(!(Test-Path $directory))
                {
                    try {
                    New-Item -ItemType Directory -Path $directory -Force | Out-Null
                    $output += "Created directory: $directory `n"
                    }
                    catch {
                        $output += "Failed to create directory $directory. `n`n"
                        return $output
                    }
                }
                # Append to output.
                $output += "   File Save . . . . . . . . . . . . . : $filePath `n`n"
                # Save the file.
                Out-File -FilePath $filePath -InputObject $output -Encoding UTF8
            } catch {
                $output += "There was an error saving the file. Please check the path is valid and try again. `n`n"
                return $output
            }
        }
        # Check if /outfile is specified without a path
        elseif ($filePath -contains "/outfile")
        {
            $filePath = $null
        }
        # If no path was specified (just /outfile), use default Windows logs directory
        if ([string]::IsNullOrWhiteSpace($filePath))
        {
            # Check if Admin for folder creation in $env:windir\Logs directory.
            if (-not $isAdmin)
            {
                $output += "File save operation requires administrator privileges. Please run as administrator or specify a path with access. `n`n"
                #return $output
            }
            else
            {
                $defaultPath = "$env:windir\Logs\ipconfig2"
                if (!(Test-Path $defaultPath))
                {
                        New-Item -ItemType Directory -Path $defaultPath -Force | Out-Null
                }
                #$hostname = (Get-AllSystemInfo).Metadata.Hostname
                $filePath = "$defaultPath\ipconfig2 $hostname on $timestamp.txt"
                
                # Append to output.
                $output += "   File Save . . . . . . . . . . . . . : $filePath `n`n"
                # Save the file.
                Out-File -FilePath $filePath -InputObject $output -Encoding UTF8
            }
        }
    }
    catch {
    }
    # Display output.
    return @{
        Output  = $output
    }
} # Save to file function END.
<# === FUNCTIONS END === #>


<# Args switches for all #>
if ($args -contains "/all")
{
    $showAll = $True
}
if ($args -contains "/version")
{
    $getVersion = $True
}
if ($args -contains "/release")
{
    #Invoke-IPConfigRelease | Out-Null
    $IpReleaseSwitch = $True
}
if ($args -contains "/renew")
{
    #Invoke-IPConfigRenew | Out-Null
    $IpRenewSwitch = $True
}
if ($args -contains "/flushdns")
{
    #Invoke-FlushDNS | Out-Null
    $FlushDnsSwitch = $True
}
if ($args -contains "/resetwinsock" -or $args -contains "/winsockreset")
{
    #Invoke-ResetWinsock | Out-Null
    $ResetWinSockSwitch = $True
}

# Display to screen.
$displayOutput = Display-Output

if ($args -contains "/outfile" -or $args -like "/outfile:*")
{
    $outFileVars = $args | Where-Object { $_ -contains "/outfile" -or $_ -like "/outfile:*" } | Select-Object -First 1
    # Sending both $outFileVars as cleaned file path, and $displayOutput.Output from memory rather than repeatedly calling the function again inside Invoke-SaveFile function. More efficient.
    $invokeOutput = Invoke-SaveFile -filePath $outFileVars -output $displayOutput.Output -hostname $display.Metadata.Hostname # v1.0.0.0 parsed vars using params for memory optimisation.
    $outfileSwitch = $True
    $invokeOutput.Output
}
else
{
    $displayOutput.Output
}