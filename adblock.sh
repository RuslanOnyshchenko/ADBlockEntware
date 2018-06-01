#!/bin/sh

# ------------------------------------------- Variables ------------------------------------------- #

DWS_URL="https://raw.githubusercontent.com/Nummer/Destroy-Windows-10-Spying/master/DWS/DWSResources.cs"
ADBLOCK_DIR="/opt/etc/adblock"
ADBLOCK_URL="$ADBLOCK_DIR/adblock.url"
ADBLOCK_IP="$ADBLOCK_DIR/adblock.ip"
ADBLOCK_IP_BLACK="$ADBLOCK_DIR/adblock.ipblack"
ADBLOCK_IP_WHITE="$ADBLOCK_DIR/adblock.ipwhite"
ADBLOCK_BLACK="$ADBLOCK_DIR/adblock.black"
ADBLOCK_WHITE="$ADBLOCK_DIR/adblock.white"
ADBLOCK_HOST="$ADBLOCK_DIR/adblock.host"
ADBLOCK_IPSET="$ADBLOCK_DIR/adblock.ipset"
ADBLOCK_IPSET_NAME="adblock-ip"
DWS_RES="$ADBLOCK_DIR/adblock.dws"
HOSTS_BLOCK="/opt/etc/hosts.block"
ADBLOCK_LOG_TAG="ADBlock"
STDERR=$1

url_counter=0
host_name=""
host_title=""

# ------------------------------------------- Functions ------------------------------------------- #

# Logging
log() {
  args="-t $ADBLOCK_LOG_TAG $1";
  [ "$STDERR" != "off" ] && args="${args} -s";
  [ $2 ] && args="${args} -p local0.$2";
  logger ${args};
}

# Clearing temporary files
clearFiles() {
  rm -f $DWS_RES
  rm -f $ADBLOCK_IP
  #rm -f $ADBLOCK_HOST
}

# Initialize the structure of folders and files if needed
init() {
  if [ ! -d $ADBLOCK_DIR ]; then mkdir $ADBLOCK_DIR; fi
  if [ ! -f $ADBLOCK_WHITE ]; then echo -e "\n" > $ADBLOCK_WHITE; fi
  if [ ! -f $ADBLOCK_BLACK ]; then echo -e "ui.skype.com\n" > $ADBLOCK_BLACK; fi
  if [ ! -f $ADBLOCK_URL ]; then
    echo "http://winhelp2002.mvps.org/hosts.txt" > $ADBLOCK_URL
    echo "http://www.malwaredomainlist.com/hostslist/hosts.txt" >> $ADBLOCK_URL
    echo "https://www.getblackbird.net/documentation/Blackbird_Blacklist.txt" >> $ADBLOCK_URL
    echo "https://adaway.org/hosts.txt" >> $ADBLOCK_URL
    echo "https://hosts-file.net/ad_servers.txt" >> $ADBLOCK_URL
    echo "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext" >> $ADBLOCK_URL
    echo "https://bitbucket.org/ancile_development/ancileplugin_networking/raw/4d47fc58ab43fedec6119261fa6ade14dab0975e/data/modify_Hosts/modify_hosts.lst" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/yous/YousList/master/hosts.txt" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/WindowsLies/BlockWindows/master/hosts" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/greatis/Anti-WebMiner/master/hosts" >> $ADBLOCK_URL
  fi
}

# Get DWS data
getDWS() {
  [ ! -f $DWS_RES ] && curl --silent --insecure $DWS_URL > $DWS_RES

  cat $DWS_RES | \
  awk "
  /^$2/ { skip=1; }
  /^$3/ { skip=0; }
  skip { print; } " | \
  sed 's/\/.*//g' | \
  grep '\,\s*$\|\"\s*$' | \
  cut -d \" -f 2 | 
  sort -u > $1
}

# Get host title
getHostTitle() {
  local url=$1
  local host=$(echo ${url/www.} | awk -F/ '{print$3}')
  [[ "$host" == "raw.githubusercontent.com" || "$host" == "bitbucket.org" ]] && host="$(echo $url | awk -F/ '{print$5}').${host/raw.}"
  echo $host | tr "[A-Z]" "[a-z]"
}

# Collecting a DWS IP addresses
collectDWSIP() {
  log "Collecting a DWS IP addresses"
  getDWS $ADBLOCK_IP "        public static string\[\] IpAddr" "        public static List"

  # Merge ip lists
  [ $(wc -l < $ADBLOCK_IP_BLACK) -ne 0 ] && cat $ADBLOCK_IP_BLACK >> $ADBLOCK_IP

  # White list applying
  [[ $(wc -l < $ADBLOCK_IP) -ge 1 && $(wc -l < $ADBLOCK_IP_WHITE) -ne 0 ]] && echo "$(grep -f $ADBLOCK_IP_WHITE -vFhx $ADBLOCK_IP)" > $ADBLOCK_IP

  # Generating and applying ipset
  if [ $(wc -l < $ADBLOCK_IP) -ge 1 ]; then
    rm -f $ADBLOCK_IPSET

    # Generating ipset
    echo "flush $ADBLOCK_IPSET_NAME" > $ADBLOCK_IPSET
    for ip in `cat $ADBLOCK_IP | sort -u`; do
      echo -e "add $ADBLOCK_IPSET_NAME $ip" >> $ADBLOCK_IPSET
    done

    log " - Collected $(wc -l < $ADBLOCK_IP) IP addresses, subnets or ranges of addresses from DWS"
    log "Generation of adblock.ipset completed"
  else
    log "WARNING!!! Used the old adblock.ipset file since we could not get updates" "err"
  fi

  # Applying ipset
  ipset -N $ADBLOCK_IPSET_NAME iphash -exist
  cat $ADBLOCK_IPSET | ipset restore
}

# Collecting a DWS hosts
collectDWSHosts() {
  log "Collecting a DWS hosts"
  getDWS $ADBLOCK_HOST "        public static string\[\] Hostsdomains" "        };"
  log " - Collected $(wc -l < $ADBLOCK_HOST) hosts from DWS"
}

# Collecting hosts from remote host files using the adblock.url
collectHosts() {
  log "Collecting hosts using the adblock.url"
  for url in `cat $ADBLOCK_URL`; do
    host_name=$(getHostTitle $url)
    url_counter=$((url_counter+1))
    host_title="host $url_counter - $host_name"
    file=$(curl --silent --insecure $url | sed 's/127.0.0.1//; s/0.0.0.0//; s/#.*//; s/\r//; /^$/d' | grep -v 'localhost' | awk '{$1=$1};1')
    echo "$file" >> $ADBLOCK_HOST
    log " - Collected $(echo "$file" | wc -l) hosts from $host_title"
  done

  # Merge host lists and store only uniq hosts
  echo "$(cat $ADBLOCK_HOST $([ $(wc -l < $ADBLOCK_BLACK) -ne 0 ] && echo $ADBLOCK_BLACK) | sed 's/ *$//' | tr "[A-Z]" "[a-z]" | sort -u)" > $ADBLOCK_HOST

  # White list applying
  [[ $(wc -l < $ADBLOCK_HOST) -ge 500 && $(wc -l < $ADBLOCK_WHITE) -ne 0 ]] && echo "$(grep -f $ADBLOCK_WHITE -vFhx $ADBLOCK_HOST)" > $ADBLOCK_HOST

  # Generating hosts.block
  if [ $(wc -l < $ADBLOCK_HOST) -ge 500 ]; then
    rm -f $HOSTS_BLOCK
    for host in `cat $ADBLOCK_HOST`; do
      echo -e "127.0.0.1\t$host" >> $HOSTS_BLOCK    # ipv4
      # echo -e "::1\t$host" >> $HOSTS_BLOCK        # ipv6
    done
    log "Generation of hosts.block completed"
  else
    log "WARNING!!! Used the old hosts.block file since we could not get updates" "err"
  fi
}

# ----------------- Collecting hosts & ip addresses to block ads & windows spying ----------------- #

log "Collecting hosts & ip addresses to block ads & windows spying" "warn"

# Initialize the structure of folders and files if needed
init

# Collecting a DWS IP addresses
collectDWSIP

# Collecting a DWS hosts
collectDWSHosts

# Collecting hosts from remote host files using the adblock.url
collectHosts

# Clearing temporary files
clearFiles

log "Added $(ipset list $ADBLOCK_IPSET_NAME | sed -n '$=') ip addresses for blocking" "warn"
log "Added $(wc -l < $HOSTS_BLOCK) hosts for blocking" "warn"

/opt/etc/init.d/S56dnsmasq restart
