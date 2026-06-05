# Promote a Windows Server 2022 host to a new AD forest. Run as local Administrator.
# See docs/04-active-directory.md

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

Install-ADDSForest `
  -DomainName "soc.lab" `
  -DomainNetbiosName "SOC" `
  -InstallDns `
  -Force
# You'll be prompted for a DSRM password; the server reboots when done.

# After reboot, add a DNS forwarder so the DC can resolve external names:
#   DNS Manager -> server Properties -> Forwarders -> add 10.0.0.2
# (or:)  Add-DnsServerForwarder -IPAddress 10.0.0.2
