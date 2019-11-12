#!/bin/bash

if [ -f /home/acfs/tftpboot/mac.txt ]; then

targetcli clearconfig confirm=True

LVREMOVE_ST=$(/bin/ls /dev/vg_iscsi/lv_st*)

for LVREMOVE_ST in $LVREMOVE_ST; do
	lvremove -y $LVREMOVE_ST
done

cat > /etc/dhcp/dhcpd.conf << EOF
# DHCP Server Configuration file.
#   see /usr/share/doc/dhcp*/dhcpd.conf.sample
#
### iPXE-specific options
# http://www.ipxe.org/howto/dhcpd
#
# Generating iPXE build image ROM
#https://rom-o-matic.eu
#
#ipxe source download
#git clone git://git.ipxe.org/ipxe.git
#
option space ipxe;
option ipxe-encap-opts code 175 = encapsulate ipxe;
option ipxe.priority code 1 = signed integer 8;
option ipxe.keep-san code 8 = unsigned integer 8;
option ipxe.skip-san-boot code 9 = unsigned integer 8;
option ipxe.syslogs code 85 = string;
option ipxe.cert code 91 = string;
option ipxe.privkey code 92 = string;
option ipxe.crosscert code 93 = string;
option ipxe.no-pxedhcp code 176 = unsigned integer 8;
option ipxe.bus-id code 177 = string;
option ipxe.bios-drive code 189 = unsigned integer 8;
option ipxe.username code 190 = string;
option ipxe.password code 191 = string;
option ipxe.reverse-username code 192 = string;
option ipxe.reverse-password code 193 = string;
option ipxe.version code 235 = string;
option iscsi-initiator-iqn code 203 = string;
# Feature indicators
option ipxe.pxeext code 16 = unsigned integer 8;
option ipxe.iscsi code 17 = unsigned integer 8;
option ipxe.aoe code 18 = unsigned integer 8;
option ipxe.http code 19 = unsigned integer 8;
option ipxe.https code 20 = unsigned integer 8;
option ipxe.tftp code 21 = unsigned integer 8;
option ipxe.ftp code 22 = unsigned integer 8;
option ipxe.dns code 23 = unsigned integer 8;
option ipxe.bzimage code 24 = unsigned integer 8;
option ipxe.multiboot code 25 = unsigned integer 8;
option ipxe.slam code 26 = unsigned integer 8;
option ipxe.srp code 27 = unsigned integer 8;
option ipxe.nbi code 32 = unsigned integer 8;
option ipxe.pxe code 33 = unsigned integer 8;
option ipxe.elf code 34 = unsigned integer 8;
option ipxe.comboot code 35 = unsigned integer 8;
option ipxe.efi code 36 = unsigned integer 8;
option ipxe.fcoe code 37 = unsigned integer 8;
option iscsi-initiator-iqn "iqn.2019-08.win10.acfs:desktop";

# speed-up for no proxydhcp user
option ipxe.no-pxedhcp 1;

# common settings
authoritative;
ddns-update-style interim;
ignore client-updates;

allow booting;
allow bootp;

set vendorclass = option vendor-class-identifier;

option client-arch code 93 = unsigned integer 16;
  if option client-arch != 00:00 {
     filename "ipxe.efi";
  } else {
     filename "undionly.kpxe";
  }

subnet 192.168.10.0 netmask 255.255.255.0 {

        option routers                  192.168.10.254;
        option subnet-mask              255.255.255.0;
        option domain-name              "tftp";
        option domain-name-servers 168.95.192.1,1.1.1.1,8.8.8.8;
        default-lease-time 21600;
        max-lease-time 43200;
        next-server 192.168.10.254;
}
EOF

MAC_TXT=$(/bin/cat /home/acfs/tftpboot/mac.txt)
ST=0
IP=10
for MAC in $MAC_TXT; do
ST=$((ST+1))
IP=$((IP+1))
    cat >> /etc/dhcp/dhcpd.conf << EOF

        host st$ST {
                      hardware ethernet $MAC;
                      fixed-address 192.168.10.$IP;
                      option host-name "st$ST";
                      ddns-hostname "st$ST";
                      if exists user-class and option user-class = "iPXE" {
                              filename "";
                              option root-path "iscsi:192.168.10.254::::iqn.2019-08.win10.acfs:st$ST";
                                         }
                 }
EOF
lvcreate -L 10G -s -n lv_st$ST /dev/vg_iscsi/lv_main

targetcli << EOF
backstores/block create name=win10_st$ST dev=/dev/vg_iscsi/lv_st$ST
iscsi/ create iqn.2019-08.win10.acfs:st$ST
iscsi/iqn.2019-08.win10.acfs:st$ST/tpg1/acls create iqn.2019-08.win10.acfs:desktop
iscsi/iqn.2019-08.win10.acfs:st$ST/tpg1/luns create /backstores/block/win10_st$ST
EOF
done

service dhcpd restart
service target restart

else
clear
echo "沒有 /home/acfs/tftpboot/mac.txt 檔,無法執行"
fi
