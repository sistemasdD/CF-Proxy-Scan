#!/usr/bin/env bash

function ctrl_c(){
        echo -e "\nExiting..."; sleep 2; exit 0
}

function get_ips(){
        local ips
        ips=$(grep -v "\#" licencia.sh | grep -iPo "\d{1,3}(\.\d{1,3}){3}" \
        | sort -u)
        echo "${ips}"
}

function check_ssh_port(){
        local ips_12021
        mapfile -t ips_12021 < <(while read -r ip ; do (timeout 1 bash -c \
        "echo '' > /dev/tcp/${ip}/12021" &>/dev/null && echo "${ip}" &); done < <(get_ips; wait))
        for ip in "${ips_12021[@]}"; do
                echo "${ip}"
        done
}

function get_web_domains(){
        declare -a ips_12021
        declare -a webs
        regex="system|default|chroot"
        mapfile -t ips_12021 < <(check_ssh_port)
        mapfile -t webs < <(for ip in "${ips_12021[@]}"; do (ssh -p12021 root@$ip \
        "ls /var/www/vhosts" 2>/dev/null &); done; wait)
        for web in "${webs[@]}"; do
        #       if [[ ! "${web}" =~ ${regex} ]]; then
        #               echo "${web}"
        #       fi
                [[ ! "${web}" =~ ${regex} ]] && echo "${web}"
        done
}

function check_cf(){
        while IFS= read -r domain; do
                local ip=$(dig ${domain} +short | head -n1) && \
                (echo "${domain} -> ${ip} -> $(test -n "${ip}" && timeout 1 bash -c "whois "${ip}" | grep \
                -iPom 1 'cloudflare' || echo ' Not Cloudflare'")" &)
        done < <(get_web_domains); wait
}

function send_email_cf_active(){
        check_cf | grep -iP '\-\>\scloudflare$' > host_cf.txt

        scp -P22 ./host_cf.txt root@172.26.0.110:/root/ &>/dev/null && ssh -p22 root@172.26.0.110 \
        "cat /root/host_cf.txt | mail -s 'Webs con Proxy de CloudFlare Activo' alertas@digitaldot.es" &>/dev/null

        rm -rf ./host_cf.txt
}

function send_email_cf_no_active(){
        check_cf | grep -iP '.*\snot\scloudflare.*' > host_without_cf.txt

        scp -P22 ./host_without_cf.txt root@172.26.0.110:/root/ &>/dev/null && ssh -p22 root@172.26.0.110 \
        "cat /root/host_without_cf.txt | mail -s 'Webs sin Proxy de CloudFlare Activo' alertas@digitaldot.es" &>/dev/null

        rm -rf ./host_without_cf.txt
}

trap ctrl_c INT

send_email_cf_active
send_email_cf_no_active
