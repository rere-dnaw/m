#!/bin/bash

# my env variables are saved in .profile . Remember to source this file when
# running crontab

start=`date +"%Y-%m-%d %T"`
HOSTS_ALLOW=$CNODE_HOME/scripts/ufw-new-list.allow # new firewall rules
HOSTS_REMOVE=$CNODE_HOME/scripts/ufw-old-list.allow # old firewall rules
file=$CNODE_CONFIG_DIR/$NODE_CONFIG-topology.json # path to topology file


# grabing ADDRESS from topology file
arrAddress=( $(jq -r '.Producers [] .addr' $file) )
#echo ${arrAddress[*]}

# grabing PORT from topology file
arrPort=( $(jq -r '.Producers [] .port' $file) )
#echo ${arrPort[*]}

# create file
> $HOSTS_ALLOW

# saving [PROTOCOL]:[PORT]:[ADDRESS] line into $HOSTS_ALLOW
i=0
while [ $i -lt ${#arrAddress[*]} ]; do
    echo "tcp:${arrPort[$i]}:${arrAddress[$i]}" >> ${HOSTS_ALLOW}
    i=$(( $i + 1))
done

# Adding firewall rule to UFW based on HOSTS_ALLOW
add_rule() {
  local proto=$1
  local port=$2
  local ip=$3
  local regex="${port}\/${proto}.*ALLOW.*IN.*${ip}"
  local rule=$(/usr/sbin/ufw status numbered | grep $regex)
  if [ -z "$rule" ]; then
      /usr/sbin/ufw allow proto ${proto} from ${ip} to any port ${port}
      echo "${start} rule does not exist. Added ${proto} from ${ip} to any ${port}"
  else
      echo "${start} rule already exists. nothing to do."
  fi
}

# Removing firewall rule from UFW based on HOSTS_REMOVE
delete_rule() {
  local proto=$1
  local port=$2
  local ip=$3
  local regex="${port}\/${proto}.*ALLOW.*IN.*${ip}"
  local rule=$(/usr/sbin/ufw status numbered | grep $regex)
  if [ -n "$rule" ]; then
      /usr/sbin/ufw delete allow proto ${proto} from ${ip} to any port ${port}
      echo "${start} rule deleted ${proto} from ${ip} to any port ${port}"
  else
      echo "${start} rule does not exist. nothing to do."
  fi
}

# this function is cheaking if address is in IPv4 format
# or domain name
# return 1 -> domain name
# return 0 -> IPv4
valid_ip()
{
    local  ip=$1
    local  stat=1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# if ${HOSTS_REMOVE} exist, read line by line from file
# in order to remove old firewall rules
if [ -f "$HOSTS_REMOVE" ]; then
    sed '/^[[:space:]]*$/d' ${HOSTS_REMOVE} | sed '/^[[:space:]]*#/d' | while read line
    do
        proto=$(echo ${line} | cut -d: -f1) # protocol type
        port=$(echo ${line} | cut -d: -f2) # port number
        host=$(echo ${line} | cut -d: -f3) # host IP

        if valid_ip $host; then ip=$host; else ip=$(dig +short $host | tail -n 1); fi
        if [ -n ${ip} ]; then
            delete_rule $proto $port $ip
        fi
    done
fi

> ${HOSTS_REMOVE}.bak
# if ${HOSTS_ALLOW} exist, read line by line from file
# in order to add new firewall rules
if [ -f "$HOSTS_ALLOW" ]; then
    sed '/^[[:space:]]*$/d' ${HOSTS_ALLOW} | sed '/^[[:space:]]*#/d' | while read line
    do
        proto=$(echo ${line} | cut -d: -f1) # protocol type
        port=$(echo ${line} | cut -d: -f2) # port number
        host=$(echo ${line} | cut -d: -f3) # host IP

        if valid_ip $host; then ip=$host; else ip=$(dig +short $host | tail -n 1); fi

        add_rule $proto $port $ip

        echo "${proto}:${port}:${host}:${ip}" >> ${HOSTS_REMOVE}.bak
    done
fi

mv ${HOSTS_REMOVE}.bak ${HOSTS_REMOVE}
