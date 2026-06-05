# Domain-join a Windows client to soc.lab. Run as local Administrator.
# See docs/04-active-directory.md

$DC_IP = "10.0.30.83"   # <-- your Domain Controller's private IP

# Find the right adapter alias first:  Get-NetAdapter
$Alias = "Ethernet 3"   # <-- adjust to match your NIC

# Point DNS at the DC (required before the join can resolve soc.lab)
Set-DnsClientServerAddress -InterfaceAlias $Alias -ServerAddresses $DC_IP

# Join the domain (prompts for SOC\Administrator credentials) and reboot
Add-Computer -DomainName "soc.lab" -Credential (Get-Credential) -Restart
