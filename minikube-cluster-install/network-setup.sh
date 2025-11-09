# Check which bridges are in use
sudo brctl show
ip link show | grep virbr

# List all existing networks and their bridges
sudo virsh net-list --all
for net in $(sudo virsh net-list --all --name); do
  echo -n "$net: "
  sudo virsh net-dumpxml $net 2>/dev/null | grep "bridge name" || echo "no bridge"
done

# Try virbr99 (likely unused)
sudo virsh net-define /dev/stdin <<EOF
<network>
  <name>default</name>
  <forward mode='nat'/>
  <bridge name='virbr99' stp='on' delay='0'/>
  <ip address='192.168.199.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.199.2' end='192.168.199.254'/>
    </dhcp>
  </ip>
</network>
EOF

sudo virsh net-start default
sudo virsh net-autostart default

# Verify
sudo virsh net-list --all | grep default