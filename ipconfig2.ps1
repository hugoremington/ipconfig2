# Script metadata
$author = "Hugo Remington"
$version = "0.4.0.9"
$date = "30-Mar-2026"

# Splash screen
Write-Host ""
Write-Host "Windows IP Configuration 2.0" -ForegroundColor Yellow
# Check for /author switch
if ($args -contains "/version") {
    Write-Host "Author: $author | Version: $version | Release date: $date" -ForegroundColor Yellow
}

<# === FUNCTIONS === #>
# Helper function to convert prefix length to subnet mask
function Convert-PrefixToSubnetMask {
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

# v0.4.0.6 Optimised MAIN removed nested jobs/threads. Using return arrays for performance.
function Get-AllSystemInfo {
    # $metadataJob = Start-Job -ScriptBlock {
        function Get-Metadata {
            $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

            # Fast local value
            $hostname = [System.Environment]::MachineName

            # Read registry once
            $tcpipParams = $null
            try {
                $tcpipParams = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
            } catch {}

            # Net profile name
            $netProfileName = $null
            try {
                foreach ($cfg in Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
                    if ($cfg.NetProfile -and $cfg.NetProfile.Name) {
                        $netProfileName = $cfg.NetProfile.Name
                    }
                }
            } catch {}

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

            $primaryDnsSuffix = $null
            if ($tcpipParams -and $tcpipParams.PSObject.Properties.Name -contains 'Domain') {
                $primaryDnsSuffix = $tcpipParams.Domain
            }

            $dnsSuffixSearchList = $null
            if ($tcpipParams -and $tcpipParams.PSObject.Properties.Name -contains 'SearchList') {
                $searchList = $tcpipParams.SearchList

                if ($searchList -is [array]) {
                    $dnsSuffixSearchList = $searchList -join ", "
                }
                elseif ($searchList) {
                    $dnsSuffixSearchList = $searchList
                }
            }

            return [PSCustomObject]@{
                Hostname            = $hostname
                primaryDnsSuffix    = $primaryDnsSuffix
                NetProfileName      = $netProfileName
                IPRoutingEnabled    = $ipRoutingEnabled
                WINSProxyEnabled    = $winsProxyEnabled
                DNSSuffixSearchList = $dnsSuffixSearchList
            }
        }
        # Get-Metadata
    # } # Metadata job finish

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

                # DNS / public resolver / geolocation style data (primarily from ipinfo)
                DnsIP       = if ($dnsApi1.IPAddress)       { $dnsApi1.IPAddress }       else { $null }
            }
        }

        Get-Isp
    }

    # Run metadata synchronously
    $metadata = Get-Metadata

    # Collect Job threads result
    Wait-Job -Job $ispJob -Timeout 10 | Out-Null

    $IspInfo        =   $null
    $MetadataInfo   =   $null
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

<# === END FUNCTIONS ===#>


<# ===START GET LOCAL NIC IP DATA=== #>
try { # v0.3.0.0 try/catch block for exception handling.
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
        
        <# START DNS server lookup table for performance v0.4.0.5#>
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

        <# START main adapter foreach loop#>
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
            $GetAllStats = $null
            $ReceivedBytes = $null
            $SentBytes = $null
            $netbiosBinding = $null
            
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
                    $autoConfigurationEnabled = "Disabled"
                }
                else { 
                    $autoConfigurationEnabled = "Enabled" 
                }
            } catch {
            }
            <# END Get Autoconfiguration APIPA #>

            <# START NetBIOS over TCP/IP settings #>
            try {
                # Get NetBIOS over TCP/IP setting using Get-NetAdapterBinding
                $netbiosBinding = Get-NetAdapterBinding -Name $adapter.Name -ComponentID "ms_tcpip" -ErrorAction SilentlyContinue
                if ($netbiosBinding) {
                    # Check if NetBIOS is enabled for this interface
                    $netbiosEnabled = ($netbiosBinding).Enabled
                    $netbiosEnabled = if ($netbiosEnabled -eq $True) { "Enabled" } else { "Disabled" }
                }
            } catch {
                # If we can't get NetBIOS info, keep default
            }
            <# END NetBIOS over TCP/IP settings #>

            # NIC Stats including ReceivedBytes and SentBytes
            try {
                $GetAllStats = Get-NetAdapterStatistics -Name $adapter.Name -ErrorAction SilentlyContinue
                $ReceivedBytes = ($GetAllStats).ReceivedBytes
                $ReceivedBytes = [math]::Round($ReceivedBytes / 1MB, 2)
                $SentBytes = ($GetAllStats).SentBytes
                $SentBytes = [math]::Round($SentBytes / 1MB, 2)
            }
            catch {
            }
            
            # Get DHCP Lease information (using current time as approximation)
            $leaseObtained = Get-Date
            $leaseExpires = $leaseObtained.AddHours(24)  # Typical DHCP lease time
            
            # v0.3.1.2 Get All IPs performance fix
            $getAllIpAddresses = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
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
                $localLinkAddress = $null
                $ipv6Address = $null

                if ($ipV6.IPAddress -like "fe80::*") {
                    $localLinkAddress = $ipV6.IPAddress
                }
                elseif ($null -ne $ipV6.IPAddress -and $ipV6.IPAddress -notlike "fe80::*") {
                    $ipv6Address = $ipV6.IPAddress
                    <#if ($ipV6.IPAddress) {
                        $ipv6Address = ($ipv6Address).Trim()
                    }#>
                }
                $localInfo += [PSCustomObject]@{
                    MediaConnectionState = $adapter.MediaConnectionState
                    InterfaceDescription = $adapter.InterfaceDescription
                    PhysicalMediaType = $adapter.PhysicalMediaType
                    LinkSpeed = $adapter.LinkSpeed
                    InterfaceName = $adapter.Name
                    IPV6Address = $ipv6Address
                    LocalLinkAddress = $localLinkAddress
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
<# ===END GET LOCAL NIC IP DATA=== #>



# v0.4.0.2 Master function
$allInfo = Get-AllSystemInfo

# v0.4.0.1 new Get-Metadata function.
$metadata = $allInfo.Metadata

<# DISPLAY OUTPUT START #>
# Line space
Write-Host ""
Write-Host "   Host Name . . . . . . . . . . . . . : $($metadata.Hostname)" -ForegroundColor Yellow
Write-Host "   Primary Dns Suffix  . . . . . . . . : $($metadata.primaryDnsSuffix)" -ForegroundColor Yellow
Write-Host "   Net Profile Name. . . . . . . . . . : $($metadata.NetProfileName)" -ForegroundColor Yellow
Write-Host "   IP Routing Enabled. . . . . . . . . : $($metadata.IPRoutingEnabled)" -ForegroundColor Yellow
Write-Host "   WINS Proxy Enabled. . . . . . . . . : $($metadata.WINSProxyEnabled)" -ForegroundColor Yellow
Write-Host "   DNS Suffix Search List. . . . . . . : $($metadata.DNSSuffixSearchList)" -ForegroundColor Yellow
Write-Host ""

# v0.4.0.1 new Get-ISP Function
$IspInfo = $allInfo.IspInfo

# v0.3.0.0 logic checks
if ($IspInfo)
{
    # Display information
    Write-Host "Public IP Address" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Public IPv4 Address . . . . . . . . : $($ispInfo.IspIP)" -ForegroundColor Yellow
    Write-Host "   Public DNS Server . . . . . . . . . : $($ispInfo.DnsIP)" -ForegroundColor Yellow
    Write-Host "   ISP Name. . . . . . . . . . . . . . : $($ispInfo.IspName)" -ForegroundColor Yellow
    Write-Host "   ISP Org . . . . . . . . . . . . . . : $($ispInfo.IspOrg)" -ForegroundColor Yellow
    Write-Host "   ISP ASN . . . . . . . . . . . . . . : $($ispInfo.IspAs)" -ForegroundColor Yellow
    Write-Host "   ISP City. . . . . . . . . . . . . . : $($ispInfo.IspCity)" -ForegroundColor Yellow
    Write-Host "   ISP Region. . . . . . . . . . . . . : $($ispInfo.IspRegion)" -ForegroundColor Yellow
    Write-Host "   ISP Country . . . . . . . . . . . . : $($ispInfo.IspCountry)" -ForegroundColor Yellow
    Write-Host "   ISP ZIP Code. . . . . . . . . . . . : $($ispInfo.IspZip)" -ForegroundColor Yellow
    Write-Host "   ISP Location. . . . . . . . . . . . : $($ispInfo.IspLoc)" -ForegroundColor Yellow
    Write-Host "   ISP Timezone. . . . . . . . . . . . : $($ispInfo.IspTimezone)" -ForegroundColor Yellow
    Write-Host ""


}

# Display Ethernet Adapter section
Write-Host "Ethernet Adapter" -ForegroundColor Green
Write-Host ""

# Group by interface name and display consolidated information
$groupedInfo = $localInfo | Group-Object InterfaceName

foreach ($group in $groupedInfo) {
    Write-Host "Interface. . . . . . . . . . . . . . . : $($group.Name)" -ForegroundColor Cyan
    Write-Host ""
    
    # Get all IPv4 and IPv6 addresses for this interface
    $ipv4Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv4" }
    $ipv6Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv6" }
    
    # Display information for the first IPv4 entry (which has the DNS suffix and other common info)
    if ($ipv4Addresses) {
        $firstIPv4 = $ipv4Addresses | Select-Object -First 1
        # Display all IPv4 information
        foreach ($info in $ipv4Addresses) {
            Write-Host "   Description . . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . . : $($info.MediaConnectionState)" -ForegroundColor Yellow
            Write-Host "   Connection-specific DNS Suffix  . . : $($firstIPv4.DnsSuffix)" -ForegroundColor Yellow
            # Display Link-local IPv6 Address if exists
            if ($ipv6Addresses) {
                if ($($ipv6Addresses.IPV6Address))
                {
                    # 0.4.0.7 Fixed IPv6 separation from Local-link IPv6 Address. Sanitised code, removing whitespaces.
                    $cleanIPv6 = $ipv6Addresses | Where-Object { $_.IPV6Address } | ForEach-Object {"$($_.IPV6Address.Trim())"}
                    Write-Host "   IPv6 Address. . . . . . . . . . . . : $($cleanIPv6 -join ', ')" -ForegroundColor Yellow
                    $cleanIPv6 = $null
                }
                if ($($ipv6Addresses.LocalLinkAddress))
                {
                    Write-Host "   Link-local IPv6 Address . . . . . . : $($ipv6Addresses.LocalLinkAddress)" -ForegroundColor Yellow
                }
            }
            If ($info.MediaConnectionState -eq "Disconnected") {
                Write-Host "   Media Type. . . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
            }
            Elseif($info.MediaConnectionState -eq "Connected") {
                Write-Host "   Media Type. . . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                If ($info.PhysicalMediaType -like "*802.11*")
                {
                    Write-Host "   WiFi SSID . . . . . . . . . . . . . : $($info.wifiSSID)" -ForegroundColor Yellow
                    Write-Host "   WiFi Key. . . . . . . . . . . . . . : $($info.wifiKey)" -ForegroundColor Yellow
                }
                Write-Host "   IPv4 Address. . . . . . . . . . . . : $($info.IPAddress)" -ForegroundColor Yellow
                Write-Host "   Subnet Mask . . . . . . . . . . . . : $($info.SubnetMask)" -ForegroundColor Yellow
                Write-Host "   Prefix Length . . . . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                Write-Host "   Default Gateway . . . . . . . . . . : $($info.DefaultGateway)" -ForegroundColor Yellow
                Write-Host "   DNS Servers . . . . . . . . . . . . : $($info.DnsServers)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
                Write-Host "   Received Bytes. . . . . . . . . . . : $($info.ReceivedBytes) MB" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . . : $($info.SentBytes) MB" -ForegroundColor Yellow
                Write-Host "   Physical Address. . . . . . . . . . : $($info.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . . : $($info.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCP variables only if DHCP is enabled
                if ($info.DhcpEnabledV4 -eq "Yes") {
                    Write-Host "   DHCPv4 Server . . . . . . . . . . . : $($info.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV4)" -ForegroundColor Yellow
                    }
                if ($info.DhcpEnabledV6 -eq "Yes") {
                    Write-Host "   DHCPv6 Enabled. . . . . . . . . . . : $($info.DhcpEnabledV6)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 IAID . . . . . . . . . . . . : $($info.Dhcpv6Iaid)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 Client DUID. . . . . . . . . : $($info.Dhcpv6Duid)" -ForegroundColor Yellow
                    if ($info.dhcpLeaseObtainedTimeV6)
                    {
                        Write-Host "   Leasev6 Obtained. . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                        Write-Host "   Leasev6 Expires . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                    }
                }
            }
            Write-Host "   Autoconfiguration Enabled . . . . . : $($info.AutoconfigurationEnabled)" -ForegroundColor Yellow
            Write-Host "   NetBIOS Enabled . . . . . . . . . . : $($info.NetbiosEnabled)" -ForegroundColor Yellow
        }
    }
    
    # Display IPv6 addresses that do not have an IPv4 shared adapter (if any)
    if ($ipv6Addresses -and !$ipv4Addresses) {
        $firstIPv6 = $ipv6Addresses | Select-Object -First 1
        foreach ($info in $ipv6Addresses) {
            Write-Host "   Description . . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . . : $($info.MediaConnectionState)" -ForegroundColor Yellow
            If ($info.MediaConnectionState -eq "Disconnected") {
                Write-Host "   Connection-specific DNS Suffix  . . : $($firstIPv6.DnsSuffix)" -ForegroundColor Yellow
                Write-Host "   Media Type. . . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
            }
            Elseif($info.MediaConnectionState -eq "Connected") {
                If ($info.IPV6Address)
                {
                    $cleanIPv6 = ($info.IPV6Address | Where-Object { $_ } | ForEach-Object { $_.TrimStart() })
                    Write-Host "   IPv6 Address. . . . . . . . . . . . : $($cleanIPv6 -join ', ')" -ForegroundColor Yellow
                    $cleanIPv6 = $null
                }
                If ($info.LocalLinkAddress)
                {
                    Write-Host "   Link-local IPv6 Addres . . . . . . : $($info.LocalLinkAddress)" -ForegroundColor Yellow
                }
                Write-Host "   Media Type. . . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                If ($info.PhysicalMediaType -like "*802.11*")
                {
                    Write-Host "   WiFi SSID . . . . . . . . . . . . . : $($info.wifiSSID)" -ForegroundColor Yellow
                    Write-Host "   WiFi Key. . . . . . . . . . . . . . : $($info.wifiKey)" -ForegroundColor Yellow
                }
                Write-Host "   Subnet Mask . . . . . . . . . . . . : $($info.SubnetMask)" -ForegroundColor Yellow
                Write-Host "   Prefix Length . . . . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                Write-Host "   Default Gateway . . . . . . . . . . : $($info.DefaultGateway)" -ForegroundColor Yellow
                Write-Host "   DNS Servers . . . . . . . . . . . . : $($info.DnsServers)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
                Write-Host "   Received Bytes. . . . . . . . . . . : $($info.ReceivedBytes)" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . . : $($info.SentBytes)" -ForegroundColor Yellow
                Write-Host "   Physical Address. . . . . . . . . . : $($info.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . . . : $($info.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCP variables only if DHCP is enabled
                if ($info.DhcpEnabledV4 -eq "Yes") {
                    Write-Host "   DHCPv4 Server . . . . . . . . . . . . : $($info.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimev4)" -ForegroundColor Yellow
                }
                if ($info.DhcpEnabledV6 -eq "Yes") {
                    Write-Host "   DHCPv6 Enabled. . . . . . . . . . . : $($info.DhcpEnabledV6)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 IAID . . . . . . . . . . . . : $($info.Dhcpv6Iaid)" -ForegroundColor Yellow
                    Write-Host "   DHCPv6 Client DUID. . . . . . . . . : $($info.Dhcpv6Duid)" -ForegroundColor Yellow
                    if ($info.dhcpLeaseObtainedTimeV6)
                    {
                        Write-Host "   Leasev6 Obtained. . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                        Write-Host "   Leasev6 Expires . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                    }
                }
            }
        Write-Host "   Autoconfiguration Enabled . . . . . : $($info.AutoconfigurationEnabled)" -ForegroundColor Yellow
        Write-Host "   NetBIOS Enabled . . . . . . . . . . : $($info.NetbiosEnabled)" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}
# Line space
Write-Host ""
<# DISPLAY OUTPUT END #>