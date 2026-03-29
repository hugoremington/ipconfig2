# IPConfig2

IPConfig2 is an enhanced Windows network configuration utility built in PowerShell.

It extends the native `ipconfig` command by combining **local network adapter data** with **public IP, ISP, and DNS context** into a single CLI output.

The tool provides a consolidated, human-readable snapshot of a system’s current network state across Ethernet, Wi-Fi, Bluetooth PAN, and virtual interfaces.

---

## Overview

IPConfig2 was originally created as a simple one-liner utility to retrieve a machine’s public IP address. It has since evolved into a more feature-rich diagnostic tool that provides deeper visibility into both local and external network configuration.

The application is lightweight, runs entirely in the command line, and can be executed as either a PowerShell script or compiled executable.

---

## Features

### System Metadata
- Host Name
- Primary DNS Suffix
- Network Profile Name
- IP Routing Status
- WINS Proxy Status
- DNS Suffix Search List

### Public Network Information
- Public IPv4 Address (via external REST API)
- ISP Name and Organisation
- ISP Location (City / Country)
- Public DNS Server
- Public DNS Location (City / Region / Country)
- DNS Provider Organisation
- Timezone and Geolocation (where available)

### Network Interface Reporting
- Interface Name
- Interface Description
- Media State (Connected / Disconnected)
- Media Type (Ethernet, Wi-Fi, Bluetooth, Virtual)
- Link Speed

### Addressing
- IPv4 Address
- IPv6 Address (including Link-local)
- Subnet Mask
- Prefix Length
- Default Gateway
- DNS Servers

### Wi-Fi Features
- Wi-Fi SSID
- Wi-Fi Key (retrieved via `netsh`)
- Filtered to 802.11 interfaces only

### DHCP Information
- DHCPv4 Enabled Status
- DHCPv4 Server
- Lease Obtained / Expiry Time
- DHCPv6 Enabled Status
- DHCPv6 IAID
- DHCPv6 Client DUID
- DHCPv6 Lease Information (where available)

### Network Activity Insight
- Received Bytes (MB)
- Sent Bytes (MB)

### Additional Capabilities
- Bluetooth PAN adapter support
- Virtual adapter support (e.g. Hyper-V switches)
- Dynamic interface grouping (IPv4 + IPv6 per adapter)
- Graceful handling of no-internet scenarios
- Multi-threaded REST API calls for performance optimisation

---

## Performance Notes

- PowerShell (`.ps1`) execution: ~3–5 seconds  
- Compiled executable (`PS2EXE`): ~10–15 seconds  

Runtime depends on:
- External API response time (public IP / DNS)
- Number of network interfaces
- System performance

IPConfig2 prioritises **depth of information over raw execution speed**, providing significantly more context than native `ipconfig`.

---

## Usage

### Run as PowerShell Script
.\ipconfig2.ps1

## Changelog

### 0.4.0.3
* Fixed missing variable $firstIPv6.
* Fixed netbios binding via $netbiosEnabled = if ($netbiosEnabled -eq $True) { "Enabled" } else { "Disabled" }.
* Minor bug fix with $autoConfigurationBinding = Get-NetIPAddress.
### 0.4.0.2
* Implemented new master function called Get-AllSystemInfo which combines System Metadata, Public IP and Public DNS calls for parallel processing using jobs/threads. Performance improvement.
* Omitted former independant functions Get-Isp and Get-Metadata.
### 0.4.0.1
* Implemented new function Get-Isp and function call for modular approach.
* Implemented new function Get-Metadata and function call for modular approach.
* Performance improvement by incorporating start-jobs in Get-Isp and Get-Metadata.
* Fixed Primary Dns Suffix data.
* Fixed Dns Suffix Search List data.
### 0.4.0.0
* Fixed NetBIOS reporting.
* New feature Bluetooth adapter reporting.
* New compact ico for compile release.
* New feature DHCP AutoConfiguration now working.
* New feature Network Transfer Statistics in MB including ReceivedBytes and SentBytes for connected interfaces.
* Performance improvement by using multi-threaded jobs for tandem REST calls.
* Garbage cleanup optimisation.
* Code clean up.
### 0.3.1.6
* New feature WiFi SSID output thanks to netsh profile match.
* New feature WiFi Key thanks to netsh profile match with key=clear.
* WiFi SSID and Keys now only reporting for matching 802.11 wifi adapters only, with if/else checks.
* Formatting tweaks, made NIC Description at top of each interface output.
### 0.3.1.5
* New feature system metadata top section including host name, primary dns suffix, net profile name, ip routing, wins prox and dns suffix search list.
* New feature DHCP reporting including v4/v6, status, server, lease, IAID and Client DUID.
* Resolved DUID binary to hex issue.
* DHCP section is dynamic, based on enabled status.
* DHCP v4 and v6 lease durations now available in readable date format, converted from unix time.
* Additional bugfixes.
* To do: Add node type into system metadata section.
### 0.3.1.4
* Added link speed feature.
* Added Media State feature.
* Added if/else checks if media state is down then report succinctly.
### 0.3.1.3
* Omitted $publicIP to remove redundancy and improve performance.
### 0.3.1.2
* Code optimisation and performance improvement for $getAllIpAddresses = Get-NetIPAddress now executing once.
* IPv6 now displays below Connection-specific DNS Suffix.
* Resolved $MyIspDNSInfo nested variable.
### 0.3.1.1
* Resolved bug No MSFT_DNSClient objects found with property 'InterfaceIndex' equal to 'X'. Verify the value of the property and retry.
* Fixed local DNS duplication.
### 0.3.0.0
* Now checks Internet connectivity using $noInternet flag thanks to try/catch blocks on Invoke-RestMethod calls.
* Public IP Address and Public DNS Server reports will not output if $noInternet -eq $true.
* Optimised code by omitting redundant API calls and replacing with objects instead. Drastically improved performance.
* Appended metadata.
* Fixed redundant NIC output, combining IPv4 and IPv6 in the same interface.
* Improved stability with additional try/catch blocks.
* New feature: local NIC DNS Suffix and MAC Address.
* Formatting and tweaks.
### 0.2.0.0
* Now working public DNS server feature using REST API call.
* Includes DNS server locale.
* Appended public IP locale.
* Got subnet mask output working.
### 0.1.0.0
* Got public IP address working.
* Initial draft.

## Author: Hugo Remington
## License: MIT
