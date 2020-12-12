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
  rm -f $ADBLOCK_IP
  rm -f $ADBLOCK_HOST
}

# Initialize the structure of folders and files if needed
init() {
  if [ ! -d $ADBLOCK_DIR ]; then mkdir $ADBLOCK_DIR; fi
  if [ ! -f $ADBLOCK_WHITE ]; then echo -e "\n" > $ADBLOCK_WHITE; fi
  if [ ! -f $ADBLOCK_BLACK ]; then echo -e "ui.skype.com\n" > $ADBLOCK_BLACK; fi
  if [ ! -f $ADBLOCK_IP_WHITE ]; then echo -e "13.107.3.128\n" > $ADBLOCK_IP_WHITE; fi
  if [ ! -f $ADBLOCK_IP_BLACK ]; then echo -e "\n" > $ADBLOCK_IP_BLACK; fi
  if [ ! -f $ADBLOCK_URL ]; then
    echo "https://winhelp2002.mvps.org/hosts.txt" > $ADBLOCK_URL
    echo "https://www.malwaredomainlist.com/hostslist/hosts.txt" >> $ADBLOCK_URL
    echo "https://www.getblackbird.net/documentation/Blackbird_Blacklist.txt" >> $ADBLOCK_URL
    echo "https://hosts-file.net/ad_servers.txt" >> $ADBLOCK_URL
    echo "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/yous/YousList/master/hosts.txt" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/WindowsLies/BlockWindows/master/hosts" >> $ADBLOCK_URL
    echo "https://raw.githubusercontent.com/greatis/Anti-WebMiner/master/hosts" >> $ADBLOCK_URL
  fi
}

# Get host title
getHostTitle() {
  local url=$1
  local host=$(echo ${url/www.} | awk -F/ '{print$3}')
  [[ "$host" == "gitlab.com" || "$host" == "raw.githubusercontent.com" || "$host" == "bitbucket.org" ]] && host="$(echo $url | awk -F/ '{gsub(/raw./,"",$3); print $3 "/" $4 "/" $5}')"
  [[ "$host" == "v.firebog.net" ]] && host="$(echo $url | awk -F/ '{gsub(/\.txt/,"",$5); print $3 "/" $5}')"
  echo $host | tr "[A-Z]" "[a-z]"
}

# Collecting hosts from remote host files using the adblock.url
collectHosts() {
  # log "Collecting hosts using the adblock.url"
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

# Collecting hosts from remote host files using the adblock.url
collectHosts

# Clearing temporary files
clearFiles

log "Added $(ipset list $ADBLOCK_IPSET_NAME | sed -n '$=') ip addresses for blocking" "warn"
log "Added $(wc -l < $HOSTS_BLOCK) hosts for blocking" "warn"

/opt/etc/init.d/S56dnsmasq restart
