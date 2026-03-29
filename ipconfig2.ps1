# Script metadata
$author = "Hugo Remington"
$version = "0.4.0.3"
$date = "29-Mar-2026"

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

# v0.4.0.2 Master function for parallel processing.
function Get-AllSystemInfo {
    # Start both functions as separate jobs
    $job1 = Start-Job -ScriptBlock {
        # Get-Isp function definition
        function Get-Isp {
            # v0.4.0.0 Parallel REST methods for public IP.
            # Start jobs for both commands
            $ispJob1 = Start-Job -ScriptBlock {
                try {
                    Invoke-RestMethod "http://ip-api.com/json/" -ErrorAction Stop
                    #noInternet flag.
                }
                catch {
                    #Write-Error "Failed to get ip-api.com data: $($_.Exception.Message)"
                    #$null
                }
            }

            $ispJob2 = Start-Job -ScriptBlock {
                try {
                    Invoke-RestMethod "https://ipinfo.io/json" -ErrorAction Stop
                }
                catch {
                    #Write-Error "Failed to get ipinfo.io data: $($_.Exception.Message)"
                    #$null
                }
            }

            # Wait for both jobs to complete
            Wait-Job -Job $ispJob1, $ispJob2 | Out-Null

            # Get results
            $Isp = Receive-Job -Job $ispJob1
            $MyIspDNSInfo = Receive-Job -Job $ispJob2
            # Clean up jobs
            Remove-Job -Job $ispJob1, $ispJob2
            # Finish Jobs.

            if ($Isp) {
                return [PSCustomObject]@{
                    # ISP variables
                    IspIP = $Isp.query
                    IspName = $Isp.isp
                    IspOrg = $Isp.org
                    IspCity = $Isp.city
                    IspCountry = $Isp.country
                    
                    # DNS variables
                    DnsIP = $MyIspDNSInfo.ip
                    DnsCity = $MyIspDNSInfo.city
                    DnsRegion = $MyIspDNSInfo.region
                    DnsCountry = $MyIspDNSInfo.country
                    DnsLoc = $MyIspDNSInfo.loc
                    DnsOrg = $MyIspDNSInfo.org
                    DnsPostal = $MyIspDNSInfo.postal
                    DnsTimezone = $MyIspDNSInfo.timezone
                }
            }
        }
        
        # Call the function
        Get-Isp
    }
    
    $job2 = Start-Job -ScriptBlock {
        # Get-Metadata function definition
        function Get-Metadata {
            $hostname = [System.Environment]::MachineName
            $systemMetadataRegistryPath = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"

            $metaJob1 = Start-Job -ScriptBlock {
                # Get Net Profile Name
                $netProfileName = (Get-NetIPConfiguration).NetProfile.Name
                return $netProfileName
            }

            $metaJob2 = Start-Job -ScriptBlock {
                param($registryPath)
                $ipRoutingEnabled = $null
                try {
                    $ipRoutingValue = Get-ItemProperty -Path $registryPath -Name "IPEnableRouter" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IPEnableRouter
                    $ipRoutingEnabled = if ($ipRoutingValue -eq 1) { "Yes" } else { "No" }
                } catch {
                    $ipRoutingEnabled = "No"
                }
                return $ipRoutingEnabled
            } -ArgumentList $systemMetadataRegistryPath

            $metaJob3 = Start-Job -ScriptBlock {
                param($registryPath)
                $winsProxyEnabled = $null
                try {
                    $winsProxyValue = Get-ItemProperty -Path $registryPath -Name "EnableProxy" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty EnableProxy
                    $winsProxyEnabled = if ($winsProxyValue -eq 1) { "Yes" } else { "No" }
                } catch {
                    $winsProxyEnabled = "No"
                }
                return $winsProxyEnabled
            } -ArgumentList $systemMetadataRegistryPath

            $metaJob4 = Start-Job -ScriptBlock {
                param($registryPath)
                # Get Primary DNS Suffix
                $primaryDnsSuffix = $null
                try {
                    $primaryDnsSuffixsearchList = Get-ItemProperty -Path $registryPath -Name "Domain" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Domain
                    if ($primaryDnsSuffixsearchList -is [array]) {
                        $primaryDnsSuffix = $primaryDnsSuffixsearchList -join ", "
                    } elseif ($primaryDnsSuffixsearchList) {
                        $primaryDnsSuffix = $primaryDnsSuffixsearchList
                    } else {
                        $primaryDnsSuffix = $null
                    }
                } catch {
                }
                return $primaryDnsSuffix
            } -ArgumentList $systemMetadataRegistryPath

            $metaJob5 = Start-Job -ScriptBlock {
                param($registryPath)
                # Get DNS Suffix Search List
                $dnsSuffixSearchList = $null
                try {
                    $searchList = Get-ItemProperty -Path $registryPath -Name "SearchList" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty SearchList
                    if ($searchList -is [array]) {
                        $dnsSuffixSearchList = $searchList -join ", "
                    } elseif ($searchList) {
                        $dnsSuffixSearchList = $searchList
                    } else {
                        $dnsSuffixSearchList = $null
                    }
                } catch {
                }
                return $dnsSuffixSearchList
            } -ArgumentList $systemMetadataRegistryPath

            # Wait for all jobs to complete
            Wait-Job -Job $metaJob1, $metaJob2, $metaJob3, $metaJob4, $metaJob5 | Out-Null

            # Get results
            $netProfileName = Receive-Job -Job $metaJob1
            $ipRoutingEnabled = Receive-Job -Job $metaJob2
            $winsProxyEnabled = Receive-Job -Job $metaJob3
            $primaryDnsSuffix = Receive-Job -Job $metaJob4
            $dnsSuffixSearchList = Receive-Job -Job $metaJob5

            # Clean up jobs
            Remove-Job -Job $metaJob1, $metaJob2, $metaJob3, $metaJob4, $metaJob5

            # Return all metadata as a custom object
            return [PSCustomObject]@{
                Hostname = $hostname
                primaryDnsSuffix = $primaryDnsSuffix
                NetProfileName = $netProfileName
                IPRoutingEnabled = $ipRoutingEnabled
                WINSProxyEnabled = $winsProxyEnabled
                DNSSuffixSearchList = $dnsSuffixSearchList
            }
        }
        
        # Call the function
        Get-Metadata
    }
    
    # Wait for both jobs to complete
    Wait-Job -Job $job1, $job2 | Out-Null
    
    # Get results
    $IspInfo = Receive-Job -Job $job1
    $metadata = Receive-Job -Job $job2
    
    # Clean up jobs
    Remove-Job -Job $job1, $job2
    
    # Return both results
    return @{
        Metadata = $metadata
        IspInfo = $IspInfo
    }
}

<# === END FUNCTIONS ===#>


<# ===START GET LOCAL NIC IP DATA=== #>
try { # v0.3.0.0 try/catch block for exception handling.
    # Create local NIC array.
    $localInfo = @()
    $networkAdapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {$_.InterfaceDescription -notmatch "Loopback"}
    if ($networkAdapters) {
        foreach ($adapter in $networkAdapters) {
            # Get Connection-specific DNS suffix
            $dnsSuffix = $null
            try {
                $dnsClient = Get-DnsClient -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue
                if ($dnsClient) {
                    $dnsSuffix = $dnsClient.ConnectionSpecificSuffix
                }
            } catch {
                # If we can't get DNS suffix, leave it null
            }
            
            # Get Default Gateway for this specific interface
            $gateway = $null
            try {
                $gateway = (Get-NetRoute -InterfaceIndex $adapter.InterfaceIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -First 1).NextHop
            } catch {
                # If we can't get gateway, leave it null
            }
            
            # Get DNS Servers for this specific interface
            $dnsServers = $null
            try {
                $dnsServerAddresses = Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ServerAddresses
                if ($dnsServerAddresses) {
                    $dnsServers = ($dnsServerAddresses | Select-Object -Unique) -join ', '
                }
            } catch {
                # If we can't get DNS servers, leave it null
            }
            
            # Get Wifi magic.
            $PhysicalMediaType = $adapter.PhysicalMediaType

            If ($PhysicalMediaType -like "*802.11*")
            {
                try {
                    # Get all profiles
                    $allProfiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object { ($_ -split ":")[1].Trim() }
                    
                    if ($allProfiles) {
                        # Find the profile that contains your partial name
                        $matchingProfile = $allProfiles | Where-Object { $_ -like "*$netProfileName*" } | Select-Object -First 1
                        
                        # If no match found, try searching the other way around
                        if (-not $matchingProfile) {
                            $matchingProfile = $allProfiles | Where-Object { $netProfileName -like "*$_*" } | Select-Object -First 1
                        }
                        
                        if ($matchingProfile) {
                            $actualProfileName = $matchingProfile
                            
                            # Get SSID
                            $ssidInfo = netsh wlan show profiles name="$actualProfileName" key=clear | Select-String "SSID name"
                            if ($ssidInfo) {
                                $wifiSsid = ($ssidInfo -split ":")[1].Trim()
                                $wifiSsid = ($wifiSsid).Trim('"')
                            }
                            $wifiKeyInfo = netsh wlan show profiles name="$actualProfileName" key=clear | Select-String "Key Content"
                            if ($wifiKeyInfo) {
                                $wifiKey = ($wifiKeyInfo -split ":")[1].Trim()
                            }
                        }
                    }
                } catch {
                    # Write-Host "Error: $_"
                }
            }


            # Get DHCP information from registry for this interface
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
                    }
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
                        $dhcpEnabledV6 = $registryItemV6.EnableDHCP
                        $dhcpEnabledV6 = "Yes"
                    }
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
            
            # Get Autoconfiguration APIPA
            try {
                $autoConfigurationBinding = Get-NetIPAddress -InterfaceAlias $adapter.Name -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like "169.254.*" }
                If ($autoConfigurationBinding) {
                    $autoConfigurationEnabled = "Enabled"
                }
                else { 
                    $autoConfigurationEnabled = "Disabled" 
                }
            } catch {
            }
            
            # Get NetBIOS over TCP/IP setting
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
            $ipv4Addresses = $getAllIpAddresses | Where-Object {$_.IPAddress -notmatch "^169\.254" -and $_.PrefixLength -ne 0 -and $_.AddressFamily -eq "IPv4"}
            foreach ($ip in $ipv4Addresses) {
                # Convert prefix length to subnet mask using a simpler approach
                $subnetMask = Convert-PrefixToSubnetMask -PrefixLength $ip.PrefixLength
                
                $localInfo += [PSCustomObject]@{
                    MediaConnectionState = $adapter.MediaConnectionState
                    InterfaceDescription = $adapter.InterfaceDescription
                    PhysicalMediaType = $PhysicalMediaType
                    LinkSpeed = $adapter.LinkSpeed
                    InterfaceName = $adapter.Name
                    IPAddress = $ip.IPAddress
                    AddressFamily = "IPv4"
                    SubnetMask = $subnetMask
                    PrefixLength = $ip.PrefixLength
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
            $ipv6Addresses = $getAllIpAddresses | Where-Object {$_.IPAddress -notmatch "^::1" -and $_.PrefixLength -ne 0 -and $_.AddressFamily -eq "IPv6"}
            foreach ($ip in $ipv6Addresses) {
                $localInfo += [PSCustomObject]@{
                    MediaConnectionState = $adapter.MediaConnectionState
                    InterfaceDescription = $adapter.InterfaceDescription
                    PhysicalMediaType = $adapter.PhysicalMediaType
                    LinkSpeed = $adapter.LinkSpeed
                    InterfaceName = $adapter.Name
                    IPAddress = $ip.IPAddress
                    AddressFamily = "IPv6"
                    SubnetMask = ""
                    PrefixLength = $ip.PrefixLength
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
#$metadata = Get-Metadata

<# DISPLAY OUTPUT START #>
# Space
Write-Host ""
Write-Host "   Host Name . . . . . . . . . . . . : $($metadata.Hostname)" -ForegroundColor Yellow
Write-Host "   Primary Dns Suffix  . . . . . . . : $($metadata.primaryDnsSuffix)" -ForegroundColor Yellow
Write-Host "   Net Profile Name. . . . . . . . . : $($metadata.NetProfileName)" -ForegroundColor Yellow
Write-Host "   IP Routing Enabled. . . . . . . . : $($metadata.IPRoutingEnabled)" -ForegroundColor Yellow
Write-Host "   WINS Proxy Enabled. . . . . . . . : $($metadata.WINSProxyEnabled)" -ForegroundColor Yellow
Write-Host "   DNS Suffix Search List. . . . . . : $($metadata.DNSSuffixSearchList)" -ForegroundColor Yellow
Write-Host ""

# v0.4.0.1 new Get-ISP Function
#$IspInfo = Get-Isp
$IspInfo = $allInfo.IspInfo

# v0.3.0.0 logic checks
if ($IspInfo)
{
    # Display information
    Write-Host "Public IP Address" -ForegroundColor Green
    Write-Host ""
    #Write-Host "  Public IP Address . . . . . . . . : $publicIP" -ForegroundColor Yellow
    Write-Host "   Public IPv4 Address . . . . . . . : $($ispInfo.IspIP)" -ForegroundColor Yellow
    Write-Host "   ISP Name. . . . . . . . . . . . . : $($ispInfo.IspName)" -ForegroundColor Yellow
    Write-Host "   ISP Org . . . . . . . . . . . . . : $($ispInfo.IspOrg)" -ForegroundColor Yellow
    Write-Host "   ISP City. . . . . . . . . . . . . : $($ispInfo.IspCity)" -ForegroundColor Yellow
    Write-Host "   ISP Country . . . . . . . . . . . : $($ispInfo.IspCountry)" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Green


    # Display ISP DNS information
    Write-Host "Public DNS Server" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Public DNS Server . . . . . . . . : $($ispInfo.DnsIP)" -ForegroundColor Yellow
    Write-Host "   Public DNS City . . . . . . . . . : $($ispInfo.DnsCity)" -ForegroundColor Yellow
    Write-Host "   Public DNS Region . . . . . . . . : $($ispInfo.DnsRegion)" -ForegroundColor Yellow
    Write-Host "   Public DNS Country. . . . . . . . : $($ispInfo.DnsCountry)" -ForegroundColor Yellow
    Write-Host "   Public DNS Location . . . . . . . : $($ispInfo.DnsLoc)" -ForegroundColor Yellow
    Write-Host "   Public DNS Org. . . . . . . . . . : $($ispInfo.DnsOrg)" -ForegroundColor Yellow
    Write-Host "   Public DNS Post Code. . . . . . . : $($ispInfo.DnsPostal)" -ForegroundColor Yellow
    Write-Host "   Public DNS Timezone . . . . . . . : $($ispInfo.DnsTimezone)" -ForegroundColor Yellow
    Write-Host "" -ForegroundColor Green

}

# Display Ethernet Adapter section
Write-Host "Ethernet Adapter" -ForegroundColor Green
Write-Host ""

# Group by interface name and display consolidated information
$groupedInfo = $localInfo | Group-Object InterfaceName

foreach ($group in $groupedInfo) {
    Write-Host "Interface. . . . . . . . . . . . . . : $($group.Name)" -ForegroundColor Cyan
    Write-Host ""
    
    # Get all IPv4 and IPv6 addresses for this interface
    $ipv4Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv4" }
    $ipv6Addresses = $group.Group | Where-Object { $_.AddressFamily -eq "IPv6" }
    
    # Display information for the first IPv4 entry (which has the DNS suffix and other common info)
    if ($ipv4Addresses) {
        $firstIPv4 = $ipv4Addresses | Select-Object -First 1
        # Display all IPv4 information
        foreach ($info in $ipv4Addresses) {
            Write-Host "   Description . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . : $($info.MediaConnectionState)" -ForegroundColor Yellow
            Write-Host "   Connection-specific DNS Suffix  . : $($firstIPv4.DnsSuffix)" -ForegroundColor Yellow
            # Display Link-local IPv6 Address if exists
            if ($ipv6Addresses) {
                Write-Host "   Link-local IPv6 Address . . . . . : $($ipv6Addresses.IPAddress -join ', ')" -ForegroundColor Yellow
            }
            If ($info.MediaConnectionState -eq "Disconnected") {
                #Write-Host "   Description . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
                Write-Host "   Connection-specific DNS Suffix  . : $($firstIPv4.DnsSuffix)" -ForegroundColor Yellow
                Write-Host "   Media Type. . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
            }
            Elseif($info.MediaConnectionState -eq "Connected") {
                #Write-Host "   Description . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
                Write-Host "   Media Type. . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                If ($info.PhysicalMediaType -like "*802.11*")
                {
                    Write-Host "   WiFi SSID . . . . . . . . . . . . : $($info.wifiSSID)" -ForegroundColor Yellow
                    Write-Host "   WiFi Key. . . . . . . . . . . . . : $($info.wifiKey)" -ForegroundColor Yellow
                }
                Write-Host "   IPv4 Address. . . . . . . . . . . : $($info.IPAddress)" -ForegroundColor Yellow
                Write-Host "   Subnet Mask . . . . . . . . . . . : $($info.SubnetMask)" -ForegroundColor Yellow
                Write-Host "   Prefix Length . . . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                Write-Host "   Default Gateway . . . . . . . . . : $($info.DefaultGateway)" -ForegroundColor Yellow
                Write-Host "   DNS Servers . . . . . . . . . . . : $($info.DnsServers)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
                Write-Host "   Received Bytes. . . . . . . . . . : $($info.ReceivedBytes) MB" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . : $($info.SentBytes) MB" -ForegroundColor Yellow
                Write-Host "   Physical Address. . . . . . . . . : $($info.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . : $($info.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCP variables only if DHCP is enabled
                if ($info.DhcpEnabledV4) {
                    # Write-Host "   DHCPv4 Enabled. . . . . . . . . . : $($info.DhcpEnabledV4)" -ForegroundColor Yellow
                    Write-Host "   DHCPv4 Server . . . . . . . . . . : $($info.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV4)" -ForegroundColor Yellow
                    if ($info.DhcpEnabledV6) {
                        Write-Host "   DHCPv6 Enabled. . . . . . . . . . : $($info.DhcpEnabledV6)" -ForegroundColor Yellow
                        Write-Host "   DHCPv6 IAID . . . . . . . . . . . : $($info.Dhcpv6Iaid)" -ForegroundColor Yellow
                        Write-Host "   DHCPv6 Client DUID. . . . . . . . : $($info.Dhcpv6Duid)" -ForegroundColor Yellow
                        if ($info.dhcpLeaseObtainedTimeV6)
                        {
                            Write-Host "   Leasev6 Obtained. . . . . . . . . : $($info.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                            Write-Host "   Leasev6 Expires . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                        }
                    }
                }
            }
            Write-Host "   Autoconfiguration Enabled . . . . : $($info.AutoconfigurationEnabled)" -ForegroundColor Yellow
            Write-Host "   NetBIOS Enabled . . . . . . . . . : $($info.NetbiosEnabled)" -ForegroundColor Yellow
        }
    }
    
    # Display IPv6 addresses (if any)
    if ($ipv6Addresses -and !$ipv4Addresses) {
        $firstIPv6 = $ipv6Addresses | Select-Object -First 1
        # Only show IPv6 addresses if there are no IPv4 addresses
        foreach ($info in $ipv6Addresses) {
            Write-Host "   Description . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
            Write-Host "   Media State . . . . . . . . . . . : $($info.MediaConnectionState)" -ForegroundColor Yellow
            If ($info.MediaConnectionState -eq "Disconnected") {
                Write-Host "   Connection-specific DNS Suffix  . : $($firstIPv6.DnsSuffix)" -ForegroundColor Yellow
                Write-Host "   Media Type. . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
            }
            Elseif($info.MediaConnectionState -eq "Connected") {
                #Write-Host "   Description . . . . . . . . . . . : $($info.InterfaceDescription)" -ForegroundColor Yellow
                Write-Host "   Link-local IPv6 Address . . . . . : $($info.IPAddress)" -ForegroundColor Yellow
                #Write-Host "   Media State . . . . . . . . . . . : $($info.MediaConnectionState)" -ForegroundColor Yellow
                Write-Host "   Media Type. . . . . . . . . . . . : $($info.PhysicalMediaType)" -ForegroundColor Yellow
                If ($info.PhysicalMediaType -like "*802.11*")
                {
                    Write-Host "   WiFi SSID . . . . . . . . . . . . : $($info.wifiSSID)" -ForegroundColor Yellow
                    Write-Host "   WiFi Key. . . . . . . . . . . . . : $($info.wifiKey)" -ForegroundColor Yellow
                }
                Write-Host "   Subnet Mask . . . . . . . . . . . : $($info.SubnetMask)" -ForegroundColor Yellow
                Write-Host "   Prefix Length . . . . . . . . . . : $($info.PrefixLength)" -ForegroundColor Yellow
                Write-Host "   Default Gateway . . . . . . . . . : $($info.DefaultGateway)" -ForegroundColor Yellow
                Write-Host "   DNS Servers . . . . . . . . . . . : $($info.DnsServers)" -ForegroundColor Yellow
                Write-Host "   Link Speed. . . . . . . . . . . . : $($info.LinkSpeed)" -ForegroundColor Yellow
                Write-Host "   Received Bytes. . . . . . . . . . : $($info.ReceivedBytes)" -ForegroundColor Yellow
                Write-Host "   Sent Bytes. . . . . . . . . . . . : $($info.SentBytes)" -ForegroundColor Yellow
                Write-Host "   Physical Address. . . . . . . . . : $($info.MacAddress)" -ForegroundColor Yellow
                Write-Host "   DHCPv4 Enabled. . . . . . . . . . . : $($info.DhcpEnabledV4)" -ForegroundColor Yellow
                # Display DHCP variables only if DHCP is enabled
                if ($info.DhcpEnabledV4) {
                    Write-Host "   DHCPv4 Server . . . . . . . . . . . : $($info.DhcpServerV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Obtained. . . . . . . . . . . : $($info.dhcpLeaseObtainedTimeV4)" -ForegroundColor Yellow
                    Write-Host "   Lease Expires . . . . . . . . . . . : $($info.dhcpLeaseTerminatesTimev4)" -ForegroundColor Yellow
                    if ($info.DhcpEnabledV6) {
                        Write-Host "   DHCPv6 Enabled. . . . . . . . . . : $($info.DhcpEnabledV6)" -ForegroundColor Yellow
                        Write-Host "   DHCPv6 IAID . . . . . . . . . . . : $($info.Dhcpv6Iaid)" -ForegroundColor Yellow
                        Write-Host "   DHCPv6 Client DUID. . . . . . . . : $($info.Dhcpv6Duid)" -ForegroundColor Yellow
                        if ($info.dhcpLeaseObtainedTimeV6)
                        {
                            Write-Host "   Leasev6 Obtained. . . . . . . . . : $($info.dhcpLeaseObtainedTimeV6)" -ForegroundColor Yellow
                            Write-Host "   Leasev6 Expires . . . . . . . . . : $($info.dhcpLeaseTerminatesTimeV6)" -ForegroundColor Yellow
                        }
                    }
                }
            }
        Write-Host "   Autoconfiguration Enabled . . . . : $($info.AutoconfigurationEnabled)" -ForegroundColor Yellow
        Write-Host "   NetBIOS Enabled . . . . . . . . . : $($info.NetbiosEnabled)" -ForegroundColor Yellow
        }
    }
    
    Write-Host ""
}

# Space
Write-Host ""
<# DISPLAY OUTPUT END #>