#!/bin/bash

# This script will set up 20 masternodes on a Hetzner CX41 VPS.
# You can also use a less powerful machine, as long as it has at the very least 200 MB ram per MN.
# Credit @mnblister 2019

# Configuration details
rpcuser=mnodin
rpcpassword=passhash1
n=20				          # Number of masternodes.
n_initial=1			      # Index of first MN.
n_final=$n			      # Index of last MN.
odinversion=1.4.2 		# Used to wget from ODIN github. Hopefully github path format doesn't change in future. 
swap=4G			          # Size of swap file that is configured.

# Welcome message
clear
echo "This script will now set up and start $n masternodes."

# Set up swap for low memory vps.  It's easier to do so via a swapfile managed by 
# systemd vs creating an entry in fstab.  That way I don't have to worry about this script appending 
# multiple lines in fstab each time it is run.  
echo "Configuring swapfile..."
swapoff -a -v
fallocate -l $swap /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapsys=/etc/systemd/system/swapfile.swap
echo "[Unit]" >> $swapsys
echo "Description=Turn on swap" >> $swapsys
echo " " >> $swapsys
echo "[Swap]" >> $swapsys
echo "What=/swapfile" >> $swapsys
echo " " >> $swapsys
echo "[Install]" >> $swapsys
echo "WantedBy=multi-user.target" >> $swapsys
systemctl enable swapfile.swap
systemctl start swapfile.swap
free
echo " " 

# ipv6 configuration.  Relies on the fact that a single ipv6 address is already enabled on eth0. 
# ifconfig shows this ip address having Global scope (sometimes global, hence making grep case insensitive with -i). 
# If this script runs multiple times, ifconfig would return multiple ipv6 addresses, so I ask grep
# to only return the first hit (grep -m 1 inet6). 
printf "Configuring additional ipv6 addresses..."
ipv6base=`ifconfig | grep -m 1 -i Global | grep lobal | awk -F"addr: " '{print $2}' | awk -F"::" '{print $1}'`  

# Enable additional ipv6 addresses. This doesn't stick after reboots.
for ((i=2; i<=$n_final; i++))
do
  ip -6 addr add $ipv6base::$(printf "%02x" $i)/64 dev eth0    
done

# Configuring network to make extra ipv6 addresses persist after reboots. 
file=/etc/network/interfaces
message="# IPV6 ODIN.MASH SETUP - Credit @mrblister"

read -r firstline<$file
if [[ "$firstline" == "$message" ]]
then
  printf "/etc/network/interfaces already configured! Moving on...\n"
else
  cp $file $file.bak    
  echo $message >> $file
  echo "# interfaces(5) file used by ifup(8) and ifdown(8)" >> $file
  echo "auto lo" >> $file
  echo "iface lo inet loopback" >> $file
  echo " " >> $file
  echo "auto eth0" >> $file
  echo "iface eth0 inet dhcp" >> $file
  echo "dns-nameservers 213.133.98.98 213.133.99.99 213.133.100.100" >> $file
  echo " " >> $file
  echo "iface eth0 inet6 static" >> $file
  echo "address $ipv6base::1" >> $file
  echo "netmask 64" >> $file
  echo "gateway fe80::1" >> $file
  echo "# Add additional 19 IPv6 addresses when eth0 goes up" >> $file
	
  for ((i=2; i<=$n_final; i++))
	do
		echo "up ip -6 addr add $ipv6base::$i/64 dev eth0" >> $file    
	done

	echo "# Remove them when eth0 goes down" >> $file
	for ((i=2; i<=$n_final; i++))
	do
		echo "down ip -6 addr add $ipv6base::$i/64 dev eth0" >> $file    
	done
  printf "done!\n"
fi

# Install ODIN binaries if not already done.
printf "Installing ODIN binaries..."
if [ -f /usr/local/bin/odind ];
then
  printf "ODIN binaries already installed. Moving on.\n"
else
  printf "\n"
  mkdir Downloads
  wget https://github.com/odinblockchain/Odin/releases/tag/v1.4.2
  wget https://github.com/odinblockchain/Odin/releases/download/v$odinversion/odin-$odinversion-x86_64-linux-gnu.tar.gz -P ~/Downloads/
  cd Downloads
  tar xvzf ~/Downloads/odin-$odinversion-x86_64-linux-gnu.tar.gz
  ln -s ~/Downloads/odin-$odinversion/bin/odind /usr/local/bin/odind
  ln -s ~/Downloads/odin-$odinversion/bin/odin-cli /usr/local/bin/odin-cli
  ln -s ~/Downloads/odin-$odinversion/bin/odin-tx /usr/local/bin/odin-tx
  cd ~
  printf "ODIN binaries linked to /usr/local/bin\n"
fi

# set up individual masternode configuration and data directories
echo "Setting up masternode configuration files..."
mkdir -p /etc/masternodes
mkdir -p /var/lib/masternodes
for ((i=$n_initial; i<=$n_final; i++))
do
  mkdir -p /var/lib/masternodes/odin$i
  config=/etc/masternodes/odin$i.conf
  if [ -f $config ];
  then
      rm $config
  fi
  rpcport=2210$(printf "%02d" $i)
  iptmp="[$ipv6base::$i]"
  ip_array[$i]=$iptmp 
  echo "# RPC" >> $config
  echo "rpcuser=$rpcuser" >> $config
  echo "rpcpassword=$rpcpassword" >> $config
  echo "rpcport=$rpcport" >> $config
  echo " " >> $config
  echo "# General" >> $config
  echo "listen=1" >> $config
  echo "daemon=1" >> $config
  echo "logtimestamps=1" >> $config
  echo "maxconnections=256" >> $config
  echo " " >> $config
  echo "# Masternode Stuff" >> $config
  echo "masternode=1" >> $config
  echo "bind=$iptmp" >> $config
  echo "externalip=$iptmp" >> $config
  echo "masternodeaddr=$iptmp" >> $config
done

# Temporarily start a single odin daemon in order to generate masternode keys
odind -daemon > /dev/null #redirect output to /dev/null to hide "ODIN server starting..." message
echo "Generating masternode keys..."
sleep 1
for ((i=$n_initial; i<=$n_final; i++))
do
  config=/etc/masternodes/odin$i.conf
  mnkey_array[$i]=$(odin-cli masternode genkey)
  echo "masternodeprivkey=${mnkey_array[$i]}" >> $config
  echo ${mnkey_array[$i]}
done
odin-cli stop > /dev/null #redirect output to /dev/null for quiet operation.

# Set up odin masternode systemd service file
echo "Setting up Odin masternode systemd service..."
servicefile=/etc/systemd/system/odin@.service
if [ -f $servicefile ];
then
  rm $servicefile
fi
echo "[Unit]" >> $servicefile
echo "Description=ODIN Blockchain Daemon" >> $servicefile
echo "After=network.target" >> $servicefile
echo " " >> $servicefile
echo "[Service]" >> $servicefile
echo "User=root" >> $servicefile
echo "Group=root" >> $servicefile
echo "Type=forking" >> $servicefile
echo "PIDFile=/var/lib/masternodes/odin%i/odin.pid" >> $servicefile
echo "ExecStart=/usr/local/bin/odind -daemon -pid=/var/lib/masternodes/odin%i/odin.pid -conf=/etc/masternodes/odin%i.conf -datadir=/var/lib/masternodes/odin%i" >> $servicefile
echo " " >> $servicefile
echo "Restart=always" >> $servicefile
echo "RestartSec=5" >> $servicefile
echo "PrivateTmp=true" >> $servicefile
echo "TimeoutStopSec=60s" >> $servicefile
echo "TimeoutStartSec=5s" >> $servicefile
echo "StartLimitInterval=120s" >> $servicefile
echo "StartLimitBurst=15" >> $servicefile
echo " " >> $servicefile
echo "[Install]" >> $servicefile
echo "WantedBy=multi-user.target" >> $servicefile 

# Enable masternode services so they start at boot, and start masternodes
echo "Enabling odin masternode systemd service..."
odin_enable="systemctl enable odin@{$n_initial..$n_final}"
odin_start="systemctl start odin@{$n_initial..$n_final}"
eval $odin_enable
echo "Starting odin masternodes..."
eval $odin_start
echo " "

echo "Creating admin scripts..."

# Create mnstart script.
mnstart=/usr/bin/mnstart
cat > $mnstart <<EOF
printf "Starting masternodes $n_initial to $n_final..."
systemctl start odin@{$n_initial..$n_final}
printf "done!\n"
EOF
chmod +x $mnstart

# Create mnstop script.
mnstop=/usr/bin/mnstop
cat > $mnstop <<EOF
#!/bin/bash
printf "Stopping masternodes $n_initial to $n_final..."
systemctl stop odin@{$n_initial..$n_final}
printf "done!\n"
EOF
chmod +x $mnstop

# Create mncmd script to send single command to a specific masternode
mncmd=/usr/bin/mncmd
cat > $mncmd <<EOF
#!/bin/bash

# execute a given command on a given masternode...
# first arg should be the command
# second arg should be the masternode number
if [[ \$# -eq 0 ]]
then
  echo "Must specify a command to execute"
  exit
elif [[ \$# -eq 1 ]]
then
  echo "Must specify a Masternode number to execute on"
  exit
elif [[ \$# -eq 2 ]]
then
  command=\$1
  rpcport="2210\$(printf "%02d" \$2)"
  printf '\e[32m%s' "Executing \$1 on Masternode-\$2 ..."
  printf '\e[0m%s' " " #end printing in green
  echo " "
  odin-cli -rpcuser=$rpcuser -rpcpassword=$rpcpassword -rpcport=\$rpcport \$command
else
  echo "Too many arguments. Usage: mncmd getinfo 1"
fi
EOF
chmod +x $mncmd

# Create mnstat script for checking on masternode status.
mnstat=/usr/bin/mnstat
cat > $mnstat <<EOF
#!/bin/bash

## Get indices of configured masternodes from conf files. Put this into an array MN.
#tmp=\`ls /etc/masternodes/ | grep -o '[0-9]\+'\`
#MN=(\$tmp)

# If no arguments, check on all masternodes. Otherwise check on the ones specified.
if [[ \$# -eq 0 ]]
then
  #for i in "\${MN[@]}"
  for ((i=$n_initial; i<=$n_final; i++)) 
  do
    rpcport="2210\$(printf "%02d" \$i)"
    printf '\e[32m%s' "mn" #start printing in green
    printf  "%02d" \$i
    printf '\e[0m%s'  " " #end printing in green
    odin-cli -rpcuser=$rpcuser -rpcpassword=$rpcpassword -rpcport=\$rpcport masternode status
  done
elif [[ \$# -eq 2 ]]
then
  for ((i=\$1; i<=\$2; i++))
  do
    rpcport="2210\$(printf "%02d" \$i)"
    printf '\e[32m%s' "mn" #start printing in green
    printf  "%02d" \$i
    printf '\e[0m%s'  " " #end printing in green
    odin-cli -rpcuser=$rpcuser -rpcpassword=$rpcpassword -rpcport=\$rpcport masternode status
  done
else
  echo "Needs start and ending index number of masternode"
fi
EOF
chmod +x $mnstat

# Create mnlist command to easily view list of masternodes that were configured
mnlist=/usr/bin/mnlist
cat > $mnlist <<'EOF'
#!/bin/bash
echo "The following masternodes have been configured:"
tmp=`ls /etc/masternodes/ | grep -o '[0-9]\+'`
MN=($tmp)
for i in "${MN[@]}"
do
  echo "masternode $i"
done    
EOF
chmod +x $mnlist

###
# Refresh a Masternode Private Key
###
mnrefresh=/usr/bin/mnrefresh
cat > $mnrefresh <<EOF
#!/bin/bash

if [[ \$# -eq 0 ]]
then
  echo "Missing Masternode Id" && exit
fi

node=\$1
rpcuser=$rpcuser
rpcpassword=$rpcpassword
rpcport="2210\$(printf "%02d" \$node)"
conf="/etc/masternodes/odin\$node.conf"
newprivkey=\$(odin-cli -rpcuser=\$rpcuser -rpcpassword=\$rpcpassword -rpcport=\$rpcport  masternode genkey)

sed -i "s/masternodeprivkey=.*$/masternodeprivkey=\${newprivkey}/g" "\$conf"

restartnode="systemctl restart odin@\$node"
checkstatus="systemctl is-active --quiet odin@\$node && echo \$newprivkey || echo failed"
eval \${restartnode}
eval \${checkstatus}
EOF
chmod +x $mnrefresh

# Finishing up
echo "*******************************************************"
echo "Masternode setup complete: $n masternodes were started."
echo "*******************************************************"
echo " "
echo "The individual masternode configuration files are in /etc/masternodes"
echo "The individual masternode data folders are in /var/lib/masternodes"
echo " "
echo "Some custom commands to manage masternodes: "
echo "To stop the masternodes: systemctl stop odin@{$n_initial..$n_final}, or simply: mnstop"
echo "To start the masternodes: systemctl start odin@{$n_initial..$n_final}, or simply: mnstart"
echo "To stop a single masternode (i.e., masternode $n_initial): systemctl stop odin@$n_initial"
echo "To list masternodes that were set up: 'ls /etc/masternodes/odin*', or simply: mnlist"
echo "To check on the status of all MNs (wait a few minutes before checking): mnstat"
echo "To check on a range of MNs (wait a few minutes before checking): mnstat $n_initial $n_final"
echo " "
host=`hostname`
echo "Configuration details (they are also stored in file $host.conf):"
out=/root/$host.conf
if [ -f $out ];
then 
  rm $out
fi
for ((i=$n_initial; i<=$n_final; i++))
do
  echo "mn$(printf "%02d" $i) ${ip_array[$i]} ${mnkey_array[$i]}" 
  echo "mn$(printf "%02d" $i) ${ip_array[$i]} ${mnkey_array[$i]}" >> $out
done



