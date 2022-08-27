#!/bin/bash

### This script will check if IP has been changed and update firewall rules for VPN connection

# my env variables are saved in .profile . Remember to source this file when
# running crontab

HOSTS_REMOVE=./ufw-old-list.allow # old firewall rules
DOMAIN=$MYDOMAIN
WG_PORT=$WG_PORT
WG_PROTO="udp"
start=`date +"%Y-%m-%d %T"`

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

# Find domain name in ${HOSTS_REMOVE} and check if IP changed.
if [ -f "$HOSTS_REMOVE" ]; then
    sed '/^[[:space:]]*$/d' ${HOSTS_REMOVE} | sed '/^[[:space:]]*#/d' | while read line
    do
        proto=$(echo ${line} | cut -d: -f1) # protocol type
        port=$(echo ${line} | cut -d: -f2) # port number
        host=$(echo ${line} | cut -d: -f3) # host name or IP
        IP=$(echo ${line} | cut -d: -f4) # host IPv4

        if [ "$DOMAIN" = "$host" ]; then
            if valid_ip $host; then new_ip=$host; else new_ip=$(dig +short $host | tail -n 1); fi

            if [ "$new_ip" = "$IP" ]; then
                add_rule $WG_PROTO $WG_PORT $new_ip
                echo "${start}:IP in NOT changed"

            else
                delete_rule $WG_PROTO $WG_PORT $IP
                add_rule $WG_PROTO $WG_PORT $new_ip
                echo "${start}:IP changed run script"
                $CNODE_HOME/scripts/updateFirewall.sh
            fi
            break
        fi
    done
fi

