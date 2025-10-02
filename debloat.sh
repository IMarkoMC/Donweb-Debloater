#!/bin/bash

cat <<'MSG'
WARNING:
This script will:
  - stop/disable services and remove packages (snmpd, rsyslog, postfix, collectd, qemu-guest-agent, etc.)
  - enforce IPv6 drop and disable IPv6 via sysctl
  - modify /etc/hosts, /etc/ssh/sshd_config, and your ~/.bashrc
  - remove ~/.ssh/authorized_keys and other files

Proceeding may lock you out if you don't have key-based SSH access.
MSG

  # Ask for confirmation (30s timeout, default = No)
  if ! read -r -t 30 -p "Do you want to continue? (y/N): " REPLY; then
    echo -e "\nNo response (timeout). Aborting."
    exit 1
  fi
  case "${REPLY,,}" in
    y|Y|yes) echo "Continuing...";;
    *)     echo "Aborted."; exit 1;;
  esac

systemctl stop snmpd.service rsyslog.service postfix.service postfix@-.service collectd.service qemu-guest-agent.service
systemctl disable snmpd.service rsyslog.service postfix.service postfix@-.service collectd.service qemu-guest-agent.service

apt remove snmpd rsyslog postfix collectd qemu-guest-agent mc -y
apt autoremove -y 

apt install iptables iptables-persistent -y

# Drop everything in IPV6
/usr/sbin/ip6tables -P INPUT DROP
/usr/sbin/ip6tables -P FORWARD DROP
/usr/sbin/ip6tables -P OUTPUT DROP

# Save the v6 rules
ip6tables-save > /etc/iptables/rules.v6

echo "net.ipv6.conf.all.disable_ipv6 = 1" |  tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" |  tee -a /etc/sysctl.conf
sysctl -p

echo "Deleting V6 rules from /etc/hosts"
cp /etc/hosts /etc/hosts.bak
sed -i -E '/^\s*::/d; /^\s*ff[0-9a-f]*::/Id; /^[0-9a-f:]{2,}:/Id' /etc/hosts

# nuke all their access to your machine
rm -rf ~/.ssh/authorized_keys

# create a empty authorized_keys so you can add your key
touch  ~/.ssh/authorized_keys

# nuke all the dumb .sh files they have in the template
rm -rf ~/*.sh 

# Fuck ICMP.
/usr/sbin/iptables -t raw -A PREROUTING -p ICMP -j DROP

iptables-save > /etc/iptables/rules.v4

echo "All Donweb bloat has been deleted and their access has been revoked. Please change the root password and finish setting up the iptables routes :)"


read -rp "Do you want to disable password auth? (y/n): " answer
case "$answer" in
    [Yy]* )
        SSHD="/etc/ssh/sshd_config"
        echo "A backup of the sshd config was saved as sshd_config.back"
        
         cp "$SSHD" "$SSHD.back"
        
        echo "Disabling password auth..."
        if grep -qE '^[#[:space:]]*PasswordAuthentication' "$SSHD"; then
         sed -i -E 's/^[#[:space:]]*PasswordAuthentication.*$/PasswordAuthentication no/' "$SSHD"
        else
         echo "PasswordAuthentication no" >> "$SSHD"
        fi

        if grep -qE '^[#[:space:]]*ChallengeResponseAuthentication' "$SSHD"; then
         sed -i -E 's/^[#[:space:]]*ChallengeResponseAuthentication.*$/ChallengeResponseAuthentication no/' "$SSHD"
        else
         echo "ChallengeResponseAuthentication no" >> "$SSHD"
        fi
        ;;
    [Nn]* )
        echo "Leaving password auth enabled."
        ;;
    * )
        echo "Invalid input, please answer y or n."
        ;;
esac

read -rp "Do you want to save your SSH public key now? (y/n): " answer
case "$answer" in
    [Yy]* )
        echo "Paste your SSH public key below (single line, usually starts with ssh-rsa or ssh-ed25519):"
        read -rp "> " sshkey
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        echo "$sshkey" >> /root/.ssh/authorized_keys
        chmod 600 /root/.ssh/authorized_keys
        echo "SSH key saved to /root/.ssh/authorized_keys"
        ;;
    [Nn]* )
        echo "Okay, you can add it later to /root/.ssh/authorized_keys"
        ;;
    * )
        echo "Invalid input, please answer y or n."
        ;;
esac


if grep -qE '^[#[:space:]]*PermitEmptyPasswords' "$SSHD"; then
 sed -i -E 's/^[#[:space:]]*PermitEmptyPasswords.*$/PermitEmptyPasswords no/' "$SSHD"
else
 echo "PermitEmptyPasswords no" >> "$SSHD"
fi

echo "Disabling the SSH listener on port 22"
sed -i -E 's/^[[:space:]]*Port[[:space:]]+22/#&/' /etc/ssh/sshd_config

echo "Disabling IPV6 in SSHD"
if grep -qE '^[#[:space:]]*AddressFamily' /etc/ssh/sshd_config; then
    sed -i -E 's/^[#[:space:]]*AddressFamily.*/AddressFamily inet/' /etc/ssh/sshd_config
else
    echo "AddressFamily inet" >> /etc/ssh/sshd_config
fi

echo "Deleting the nonsense they add to ~/.bashrc. A backup was saved as bashrc.back"
 cp -a ~/.bashrc ~/.bashrc.back
 cp /etc/skel/.bashrc ~/.bashrc

echo "Please log in again for the bashrc changes to take effect :)"

read -rp "Do you want to change the root password now? (y/n): " answer
case "$answer" in
    [Yy]* )
        echo "Changing root password..."
        passwd
        ;;
    [Nn]* )
        echo "Skipping root password change."
        ;;
    * )
        echo "Invalid input, please answer y or n."
        ;;
esac
