#!/bin/bash

CLOUDFALRE_USER_MAIL=""
CLOUDFALRE_GLOBAL_API=""
CLOUDFALRE_ZONES_ID=""
CLOUDFALRE_DOMAIN=""
CLOUDFALRE_DNS_RECORD_ID=""

INTERFACE_NAME=""
GET_NTH_ADDRESS=""

OPENWRT_ADDRESS=""
OPENWRT_USERNAME=""
OPENWRT_FIREWALL_RULE_ID=""

LogOut() {
  if [ "$1" = "ERROR" ]; then
    echo -e "$(date "+%H:%M:%S") \033[31m[$1]\033[0m $2"
  elif [ "$1" = "WARNING" ]; then
    echo -e "$(date "+%H:%M:%S") \033[33m[$1]\033[0m $2"
  else
    echo -e "$(date "+%H:%M:%S") \033[32m[$1]\033[0m $2"
  fi
}

GetInterfaceIPv6Address() {
  LogOut "INFO" "正在获取网卡的IPv6地址"
  IPV6ADDRESS=$(ip -6 addr show dev ${INTERFACE_NAME} | grep global | awk '{print $2}' | awk -F "/" '{print $1}' | sed -n ${GET_NTH_ADDRESS}p)
  LogOut "INFO" "当前IPv6地址为: ${IPV6ADDRESS}"
}

GetAddressFormCloudflare() {
  LogOut "INFO" "正在获取当前DNS记录的地址"
  CLOUDFLARE_IP_CONTENT=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${CLOUDFALRE_ZONES_ID}/dns_records?type=AAAA&name=${CLOUDFALRE_DOMAIN}&content=127.0.0.1&page=1&per_page=100&order=type&direction=desc&match=any" \
    -H "X-Auth-Email: ${CLOUDFALRE_USER_MAIL}" \
    -H "X-Auth-Key: ${CLOUDFALRE_GLOBAL_API}" \
    -H "Content-Type: application/json" | \
    jq --raw-output '.result[0].content')
  LogOut "INFO" "获取到当前DNS记录地址为: ${CLOUDFLARE_IP_CONTENT}"
}

PutAddress2Cloudflare() {
  LogOut "INFO" "正在更新Cloudflare上的IPv6地址为: ${IPV6ADDRESS}"
  CLOUDFLARE_RETURN_STATUS=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${CLOUDFALRE_ZONES_ID}/dns_records/${CLOUDFALRE_DNS_RECORD_ID}" \
    -H "X-Auth-Email: ${CLOUDFALRE_USER_MAIL}" \
    -H "X-Auth-Key: ${CLOUDFALRE_GLOBAL_API}" \
    -H "Content-Type: application/json" --data '{"type":"AAAA","name":"'"${CLOUDFALRE_DOMAIN}"'","content":"'"${IPV6ADDRESS}"'","ttl":1,"proxied":false}' | \
    jq --raw-output '.success')
  if [ "$CLOUDFLARE_RETURN_STATUS" = "true" ]; then
    LogOut "INFO" "更新IPV6地址成功"
  else
    LogOut "ERROR" "更新IPV6地址失败"
  fi
}

CheckJqInstalled() {
  local isInstall=$(dpkg-query -l | grep jq | awk '{print $2}' | sed -n 1p)
  if [ "$isInstall" = "jq" ]; then
    LogOut "INFO" "检测到jq的存在，跳过安装"
  else
    LogOut "WARNING" "没有检测到jq的安装，即将安装jq依赖"
    apt update -y && apt install -y jq
  fi
}

PutOpenwrtFirewall() {
  LogOut "INFO" "正在在Openwrt中放行${IPV6ADDRESS}地址"
  ssh ${OPENWRT_USERNAME}@${OPENWRT_ADDRESS} "uci del firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip; \
    uci add_list firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip='${IPV6ADDRESS}'; \
    uci commit; \
    uci changes; "
  OPENWRT_FIREWALL_DEST_IP=$(ssh ${OPENWRT_USERNAME}@${OPENWRT_ADDRESS} "uci show firewall.@rule[${OPENWRT_FIREWALL_RULE_ID}].dest_ip" | awk -F \' '{print $2}')
  LogOut "INFO" "防火墙放行地址已修改为: ${OPENWRT_FIREWALL_DEST_IP}"
}

ShellRun() {
  CheckJqInstalled
  GetInterfaceIPv6Address
  GetAddressFormCloudflare
  if [ "$IPV6ADDRESS" != "$CLOUDFLARE_IP_CONTENT" ]; then
    PutAddress2Cloudflare
    PutOpenwrtFirewall
  else 
    LogOut "INFO" "IPv6地址无变化，无需更新"
  fi
}

ShellRun

exit