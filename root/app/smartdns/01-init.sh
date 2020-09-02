#!/bin/sh

sysctl -w net.ipv4.conf.all.rp_filter=2 >/dev/null

var VPN_MULTIPLE true
var -d VPN_COUNTRY

#
# Resolve needed countries
#
for service in $(var SMARTDNS_SERVICES) ; do
    log -d "Configuring $service"

    country=$(cat /app/smartdns/smartdns.country.conf | grep "$service" | sed 's/.*:\([A-Z]\)/\1/g')

    log -d "Service $service requires vpn $country"

    var -a VPN_COUNTRY $country
done

#
# Route all requests to 80/443
#
var port 10
for country in $(var VPN_COUNTRY) ; do
    
    log -d "Configuring vpn country $country to use 80$(var port) and 81$(var port)"

    dict port $country $(var port)

    iptables -A OUTPUT -t nat -o eth0 -p tcp --dport 80$(var port) -j DNAT --to-destination :80
    iptables -A OUTPUT -t nat -o eth0 -p tcp --dport 81$(var port) -j DNAT --to-destination :443

    var port $(($(var port) + 1))
done
var -d port

#
# Create sniproxy.conf
#

> /app/smartdns/10-smartdns-tmp.conf
log -i "Creating sniproxy config"
mkdir -p /etc/sniproxy
cp -f /app/smartdns/sniproxy.template.conf /app/sniproxy/sniproxy.conf

for table in "http" "https" ; do
    echo "table $table {" >> /app/sniproxy/sniproxy.conf

    range="80"
    if [ "$table" = "https" ] ; then
        range="81"
    fi

    for service in $(var SMARTDNS_SERVICES) ; do
        country=$(cat /app/smartdns/smartdns.country.conf | grep "$service" | sed 's/.*:\([A-Z]\)/\1/g')

        domains=$(cat /app/smartdns/smartdns.domain.conf | grep "$service:" | sed 's/.*:\(.*\)/\1/g')

        for domain in $domains ; do
            echo "$domain *:$range$(dict port $country)" >> /app/sniproxy/sniproxy.conf
            log -d "$domain *:$range$(dict port $country)"

            d=$(echo "$domain" | sed -e "s/[\\]//g" -e "s/^\([^*]*\*\)\.//g")
            echo "address=/$d/$(var HOST_IP)" >> /app/smartdns/10-smartdns-tmp.conf
        done
    done
    echo ".* *" >> /app/sniproxy/sniproxy.conf
    echo "}" >> /app/sniproxy/sniproxy.conf
done

cat /app/smartdns/10-smartdns-tmp.conf | sort -u > /app/smartdns/10-smartdns.conf
rm -f /app/smartdns/10-smartdns-tmp.conf
cp -f /app/smartdns/10-smartdns.conf /etc/dnsmasq.d/10-smartdns.conf