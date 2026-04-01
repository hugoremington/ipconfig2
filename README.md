# IPConfig2

IPConfig2 is an enhanced Windows network configuration utility built in PowerShell.

It extends the native `ipconfig` command by combining local network adapter data with public IP, ISP, and DNS context into a single CLI output.

The tool provides a comprehensive, human-readable snapshot of a system’s current network state across Ethernet, Wi-Fi, Bluetooth PAN, and virtual interfaces.

---

## Overview

IPConfig2 was originally created as a simple one-liner utility to retrieve a machine’s public IP address. It has since evolved into a more feature-rich diagnostic tool that provides deeper visibility into both local and external network configuration.

The application is lightweight, runs entirely in the command line (CLI), and can be executed as either a PowerShell script or compiled executable.

It is still experimental, some features may or may not work depending on your environment. Use it with care.

---

## Features

### Public Network Information
- Public IPv4 Address (via external REST API)
- ISP Name and Organisation
- ISP Location (Geolocation)
- Public DNS Server
- DNS Provider Organisation
- Timezone

### System Metadata
- Host Name
- Primary DNS Suffix
- Network Profile Name
- Network Profile Type
- IP Routing Status
- WINS Proxy Status
- DNS Suffix Search List

### Network Operations
- DHCP Release switch.
- DHCP Renew switch.

### Network Interface Reporting
- Interface Name
- Interface Description
- Media State (Connected / Disconnected)
- Media Type (Ethernet, Wi-Fi, Bluetooth, Virtual)

### IP Addressing
- IPv4 Address
- IPv6 Address
- Subnet Mask
- Prefix Length
- Default Gateway
- DNS Servers

### Wi-Fi Features
- Wi-Fi SSID
- Wi-Fi Key

### DHCP Information
- DHCPv4 Enabled Status
- DHCPv4 Server
- Lease Information
- DHCPv6 Enabled Status
- DHCPv6 IAID
- DHCPv6 Client DUID

### Network Telemetry
- Link Speed (Mbps / Gbps)
- Received Bytes (MB)
- Sent Bytes (MB)

### Additional Capabilities
- Bluetooth PAN adapter support
- Virtual adapter support (e.g. Hyper-V switches)
- Dynamic interface grouping (IPv4 + IPv6 per adapter)
- Graceful handling of no-internet scenarios
- Multi-threaded REST API calls for performance optimisation

---

## To-Do
 - Output to TXT/CSV feature.

---

## Performance Notes

- ~5–10 seconds  

Runtime depends on:
- External API response time (public IP / DNS)
- Number of network interfaces
- System performance

IPConfig2 prioritises comprehensive information over raw execution speed, providing significantly more context than native `ipconfig`.

---

## Usage

powershell .\ipconfig2.ps1

cmd ipconfig2.exe


## Parameter
```powershell
ipconfig2 [/release] [/renew] [/version]
```

```
release         = Release DHCP IP addresses on local network interface cards on system with DHCP enabled.
renew           = Renew DHCP IP Address on local network interface cards on system with DHCP enabled.
version         = Get utility version and attribution metadata.
```

## Changelog

### 0.5.0.2 - 01-Apr-2026
* Improved DHCP release/renew functions to use modern CimInstance methods. Retained classic WMIObject methods as a fallback using try/catch blocks.
* Improved output table even more. Now more efficient and consistent with less foreach loops. 
* More output now visible irrespective to media state, such as physical MAC address, dhcp, and more.
* Improved metadata table which now dynamically displays multiple network profiles where available.
* Slight formatting tweaks.
### 0.5.0.1 - 01-Apr-2026
* Minor cosmetic bug fix with line spacing before/after release/renew commands.
* Improved cosmetic line spacing after splash screen, more consistent with entire script.
### 0.5.0.0 - 01-Apr-2026
* April Fool's Day major update, this release is no joke!
* New DHCP v4 and v6 release feature. Factored in new function called Invoke-IPConfigRelease. This is independent from Windows native ipconfig and a viable fallback feature.
* New DHCP v4 and v6 renew feature. Factored in new function called Invoke-IPConfigRenew. This is independent from Windows native ipconfig and a viable fallback feature.
* Now supporting NICs with multiple IP addresses! This was not working previously due to output syntax.
* Now displays hidden DHCP 169.254 addresses.
* Implemented new line break concatenation for multiple output values using (-join "`n                                         "). This now grants streamline output structure for elements such as NIC DNS server.
* Refactored output tables, resolving multiple duplication bugs and hidden values.
* Resolved duplicate NIC rows when releasing DHCP IP.
* Resolved value duplication in metadata output when releasing DHCP IP. By filtering basic using ( | Select-Object -First 1) in metadata output table.
* Implemented start-sleep timer after IP release to compile output table correctly.
* Significantly improved IP release/renew performance times within Invoke functions by filtering with where-object logic: $_.InterfaceIndex -eq $($adapter.IfIndex). More efficient.
* Appended IPv4 and IPv6 distinguishment for subnet prefix length.
* Sort-object when releasing/renewing IPs by InterfaceMetric number. This now resolves the bug where NICs would sequentially failover and not be scoped for DHCP release.
* Fixed IP release by omitting logic IPEnabled, ensuring even disconnected NICs drop their DHCP lease.
* Got IPv6 Link-local and Address subnet prefix length display to function.
* Numerous bug fixes.
### 0.4.1.2 - 31-Mar-2026
* Cosmetic change: renamed Ethernet Adapter section to Network Interface Card.
* Cosmetic change: renamed Network Profile Category to Network Profile Type.
### 0.4.1.1 - 31-Mar-2026
* Fixed network profile category not appearing in certain conditions.
* Appended Internet connectivity checks in metadata.
* Fixed display wording for Autoconfiguration enabled.
* Fixed display wording for NetBIOS over Tcpip.
### 0.4.1.0 - 31-Mar-2026
* Appended network profile category into metadata output table.
* Refactored IPv6 output, omitted LocalLinkAddress from retun tables. Appended better logic in output display area for both IPv4 and IPv6 sections.
* Fixed External DNS Server reporting by appending -join operator for multi support.
* Omitted $cleanIPv6.
* Omitted duplicate Media Type output code in both if/else conditions.
* Media Type now displays nicely underneat Media State.
* Slight re-wording and optimisation.
### 0.4.0.9 - 30-Mar-2026
* Resolved metadata output line spacing.
### 0.4.0.8 - 30-Mar-2026
* Removed multi-threading for Get-Metadata as it is slower when multithreading in function, might be quicker to multithread when there are multiple functions greater than 2.
* Reinstated ISP ZIP Code data point.
### 0.4.0.7 - 30-Mar-2026
* This release brings performance improvements.
* Removed redundant Get-Isp nested function inside MAIN Get-AllSystemInfo function. Reducing unnecessary threads and improving performance.
* Applied multi-threading jobs for Get-Metadata nested function inside Get-AllSystemInfo parent function. This may improve performance, as it is the longest execution time element in the source code atm. 
* Omitted redundant API call to "https://ipinfo.io/json". Improving performance.
* Optimised Get-Isp return array, to match new REST API telemetry.
* Optimised Get-Metadata function to use $tcpipParams.PSObject memory instead of four Get-ItemProperty system registry calls. Improved performance.
* Resolved public DNS retrieval. Now reflecting accurately thanks to whoami.akamai.net.
* Fixed $ip conflict in both IPv4 and IPv6 contexts, risk of leak. Now using $ipV4 and $ipV6.
* Fixed duplicate data in Local-link IPv6 Address field. Separated Local-link from manual address for IPv6. New if/else conditions for display of manual IPv6 address.
* Performed sanitisation using $cleanIPv6 to remove whitespace(s).
* Added new AddressState data point in return arrays for both IPv4 and IPv6 for (Preferred/Deprecated) reporting. Will need to utilise this in future releases.
* Omitted redundant Public DNS Server section.
* Updated output tables to match new categories and return variables.
* Code formatting, organisation and tweaks.
### 0.4.0.6 - 30-Mar-2026
* Significant performance boost by tweaking MAIN Get-AllSystemInfo function omitting nested jobs/threads. Using return arrays over vars.
### 0.4.0.5 - 30-Mar-2026
* Fixed $dhcpEnabledV4 semantics for Yes/No after logic if/else checks for consistency.
* Small performance tweaks by omitting redundant netsh commands and using $netshQuery instead.
* Enabled experimental reporting of additional NICs/IPs by omitting "$_.IPAddress -notmatch "^169\.254" -and $_.PrefixLength -ne 0 -and" from $ipv4Addresses and $ipv6Addresses vars.
* Testing and validation of DHCPv6Enabled status. Verified accuracy.
* Fixed redundant IPv6 Link row output.
* Performance optimisation, moved $networkAdapters, $dnsClients, Get-NetRoute, Get-DnsClientServerAddress outside of foreach loop, improving data collection.
* Fixed DNS Suffix Search List registry reference.
* Fixed DHCPv4 & DHCPv6 output tables and conditional output.
### 0.4.0.4 - 29-Mar-2026
* Fixed $autoConfigurationBinding now reporting correctly thanks to netsh DAD Transmits data point.
### 0.4.0.3 - 29-Mar-2026
* Fixed missing variable $firstIPv6.
* Fixed netbios binding via $netbiosEnabled = if ($netbiosEnabled -eq $True) { "Enabled" } else { "Disabled" }.
* Minor bug fix with $autoConfigurationBinding = Get-NetIPAddress.
### 0.4.0.2 - 29-Mar-2026
* Implemented new master function called Get-AllSystemInfo which combines System Metadata, Public IP and Public DNS calls for parallel processing using jobs/threads. Performance improvement.
* Omitted former independant functions Get-Isp and Get-Metadata.
### 0.4.0.1 - 29-Mar-2026
* Implemented new function Get-Isp and function call for modular approach.
* Implemented new function Get-Metadata and function call for modular approach.
* Performance improvement by incorporating start-jobs in Get-Isp and Get-Metadata.
* Fixed Primary Dns Suffix data.
* Fixed Dns Suffix Search List data.
### 0.4.0.0 - 29-Mar-2026
* Fixed NetBIOS reporting.
* New feature Bluetooth adapter reporting.
* New compact ico for compile release.
* New feature DHCP AutoConfiguration now working.
* New feature Network Transfer Statistics in MB including ReceivedBytes and SentBytes for connected interfaces.
* Performance improvement by using multi-threaded jobs for tandem REST calls.
* Garbage cleanup optimisation.
* Code clean up.
### 0.3.1.6 - 28-Mar-2026
* New feature WiFi SSID output thanks to netsh profile match.
* New feature WiFi Key thanks to netsh profile match with key=clear.
* WiFi SSID and Keys now only reporting for matching 802.11 wifi adapters only, with if/else checks.
* Formatting tweaks, made NIC Description at top of each interface output.
### 0.3.1.5 - 28-Mar-2026
* New feature system metadata top section including host name, primary dns suffix, net profile name, ip routing, wins prox and dns suffix search list.
* New feature DHCP reporting including v4/v6, status, server, lease, IAID and Client DUID.
* Resolved DUID binary to hex issue.
* DHCP section is dynamic, based on enabled status.
* DHCP v4 and v6 lease durations now available in readable date format, converted from unix time.
* Additional bugfixes.
* To do: Add node type into system metadata section.
### 0.3.1.4 - 28-Mar-2026
* Added link speed feature.
* Added Media State feature.
* Added if/else checks if media state is down then report succinctly.
### 0.3.1.3 - 28-Mar-2026
* Omitted $publicIP to remove redundancy and improve performance.
### 0.3.1.2 - 28-Mar-2026
* Code optimisation and performance improvement for $getAllIpAddresses = Get-NetIPAddress now executing once.
* IPv6 now displays below Connection-specific DNS Suffix.
* Resolved $MyIspDNSInfo nested variable.
### 0.3.1.1 - 28-Mar-2026
* Resolved bug No MSFT_DNSClient objects found with property 'InterfaceIndex' equal to 'X'. Verify the value of the property and retry.
* Fixed local DNS duplication.
### 0.3.0.0 - 28-Mar-2026
* Now checks Internet connectivity using $noInternet flag thanks to try/catch blocks on Invoke-RestMethod calls.
* Public IP Address and Public DNS Server reports will not output if $noInternet -eq $true.
* Optimised code by omitting redundant API calls and replacing with objects instead. Drastically improved performance.
* Appended metadata.
* Fixed redundant NIC output, combining IPv4 and IPv6 in the same interface.
* Improved stability with additional try/catch blocks.
* New feature: local NIC DNS Suffix and MAC Address.
* Formatting and tweaks.
### 0.2.0.0 - 28-Mar-2026
* Now working public DNS server feature using REST API call.
* Includes DNS server locale.
* Appended public IP locale.
* Got subnet mask output working.
### 0.1.0.0 - 28-Mar-2026
* Got public IP address working.
* Initial draft.

---

# Attribution & License

Author: Hugo Remington

License: MIT

Compiled as an EXE using [MScholtes/PS2EXE](https://github.com/MScholtes/PS2EXE)

Public IP and Public DNS retrieval using REST API via free provider [ip-api.com](https://ip-api.com). Licensing is subject to their terms and conditions.