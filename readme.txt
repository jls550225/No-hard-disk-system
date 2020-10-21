1.伺服器配備:
CPU : i5 以上
RAM : 8G 以上
硬碟: 500 G 一顆(安裝 Linux 系統用)
SSD硬碟:480G 二顆以上(做RAID 陣列用)
網路卡:1000Mbps傳輸速二片以上(分流用)

2.客戶端電腦必需相同配備,不然進不了 Windows 10 系統(目前還再研究中)

(一)伺服器系統安裝及設定
下載CentOS 7 x86_64-Minimal 的ISO
ftp://drbl.nchc.org.tw/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-1908.iso

使用最小安裝即可
###設定固定IP 外網:163.23.xxx.xxx 內網:192.168.10.254
nmtui-edit
###設定好IP後,重啟網卡
service network restart
ping 168.95.1.1

#安裝所需套件
yum -y install epel-release
yum -y update
#yum -y install ftp://drbl.nchc.org.tw/drbl-core/x86_64/RPMS.drbl-unstable/drbl-2.30.20-drbl1.noarch.rpm
yum -y install net-tools fuse-sshfs zip unzip cups dialog mtools mdadm ntfs-3g ntfsprogs
yum -y install ntsysv ntp vim man nmap rp-pppoe gcc wget make iptstate iptraf iptables-devel gpm
yum -y install yum-utils rpcbind tftp-server tftp telnet ftp rsync mailx nfs-utils xinetd
yum -y install dhcp* targetcli iscsi-initiator-utils grub2-efi-x64* xz-devel mkisofs git ipxe-bootimgs
#yum -y install https://archive.fedoraproject.org/pub/archive/fedora/linux/releases/19/Everything/x86_64/os/Packages/a/aoetools-30-5.fc19.x86_64.rpm
#yum -y install https://archive.fedoraproject.org/pub/archive/fedora/linux/releases/19/Everything/x86_64/os/Packages/v/vblade-14-10.fc19.x86_64.rpm

###關掉 SELINUX 
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

###新增一個使用者來設定 tftpboot 路徑
adduser acfs
passwd acfs
usermod -aG wheel acfs
mkdir -p /home/acfs/tftpboot/win10
chmod 777 /home/acfs/tftpboot -R

#############TFTPD Server Config
echo "/home/acfs/tftpboot/win10 192.168.10.*(rw,async,no_root_squash,no_subtree_check)" > /etc/exports
cat > /etc/xinetd.d/tftp << EOF
# default: off
# description: The tftp server serves files using the trivial file transfer \
#       protocol.  The tftp protocol is often used to boot diskless \
#       workstations, download configuration files to network-aware printers, \
#       and to start the installation process for some operating systems.
service tftp
{
        socket_type             = dgram
        protocol                = udp
        wait                    = yes
        user                    = root
        server                  = /usr/sbin/in.tftpd
        server_args             = -s /home/acfs/tftpboot
        disable                 = no
        per_source              = 11
        cps                     = 100 2
        flags                   = IPv4
}
EOF

###設定開機後自動啟動
chkconfig target on
chkconfig iscsid on
chkconfig tftp on
chkconfig dhcpd on
chkconfig dhcpd6 off
chkconfig firewalld off
chkconfig crond on
chkconfig ntpdate off
chkconfig nfs on
chkconfig xinetd on
chkconfig sshd on
chkconfig rpcbind on
chkconfig rsyncd on
chkconfig gpm on
chkconfig cups on
sync
sync
sync
reboot

(二)設定磁碟陣列(RAID)
##設定二顆SSD的磁陣
fdisk /dev/sdb
fdisk /dev/sdc
#更新 Linux Kernel 分割表資訊,讓新 partition 不需重開機即可生效
partprobe

[root@localhost ~]# fdisk -l /dev/sdb
所用裝置 開機      開始         結束      區塊   識別號  系統
/dev/sdb1            2048   104857599    52427776   fd  Linux raid autodetect

[root@localhost ~]# fdisk -l /dev/sdc
所用裝置 開機      開始         結束      區塊   識別號  系統
/dev/sdc1            2048   104857599    52427776   fd  Linux raid autodetect

###使用 mdadm 指令，以建立 RAID 0 陣列：
mdadm -C /dev/md0 --level=raid0 --raid-devices=2 /dev/sdb1 /dev/sdc1

#1. 顯示目前 RAID 狀態
# mdadm --detail /dev/md0 | tail -n 2
#    Number   Major   Minor   RaidDevice State
#       0       8        1        0      active sync   /dev/sdb1
#       1       8       17        1      active sync   /dev/sdc1

#2. 停用及刪除 RAID
mdadm --stop /dev/md0
..mdadm: stopped /dev/md02. 移除 RAID
mdadm --remove /dev/md0
#
#3. 移除 superblocks
mdadm --zero-superblock /dev/sdb1 /dev/sdc1

(三)建立 LVM 磁區以便設定快照(建立順序：PV、VG、LV)
#如果沒有需先安裝 lvm2 套件:
yum install -y lvm2
#2. 進入磁碟分割功能
fdisk /dev/md0
#Command (m for help): l     <--列出磁碟格式表
#3. 新建一個磁區
#Command (m for help): n     <--新建一個磁區 
#4. 變更磁碟格式 ID
#Command (m for help): t     <--輸入 8e (8e磁碟格式 LVM)
#5. 儲存磁區設定 & 離開磁碟格式功能
#Command (m for help): w
#6. 更新 Linux Kernel 分割表資訊,讓新 partition 不需重開機即可生效
partprobe
#7. 建立 PV
pvcreate /dev/md0p1
#8. 建立 VG
vgcreate vg_iscsi /dev/md0p1
#9. 建立 100G LV (安裝 Windows 10 系統母碟用)
lvcreate -L 100G -n lv_main vg_iscsi
###加大 LV 容量 50G
#lvresize -L +51200M /dev/vg_iscsi/lv_main

(四)建立 iSCSI 連線磁碟機 (安裝 Windows 10 系統母碟用)
targetcli << EOF
backstores/block create name=win10_main dev=/dev/vg_iscsi/lv_main
iscsi/ create iqn.2019-08.win10.acfs:main
iscsi/iqn.2019-08.win10.acfs:main/tpg1/acls create iqn.2019-08.win10.acfs:desktop
iscsi/iqn.2019-08.win10.acfs:main/tpg1/luns create /backstores/block/win10_main
EOF

(五)設定 dhcpd server

###編輯一個 dhcpd.conf 的設定檔
cat > /etc/dhcp/dhcpd.conf << EOF
# DHCP Server Configuration file.
#   see /usr/share/doc/dhcp*/dhcpd.conf.sample
#
### iPXE-specific options
# http://www.ipxe.org/howto/dhcpd
#
# Generating iPXE build image ROM 
#https://rom-o-matic.dev
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

        host main {
                      #copy the id corresponding to the card 客戶端連線網卡實體位址(MAC 位址)
                      hardware ethernet f4:4d:30:a1:f8:9a;
                      fixed-address 192.168.10.10;
                      option host-name "main";
                      ddns-hostname "main";
                      if exists user-class and option user-class = "iPXE" {
                              filename "";
                              option root-path "iscsi:192.168.10.254::::iqn.2019-08.win10.acfs:main";
                              #option root-path "aoe:e0.1"; 	
                                         }
                 }
EOF

###拷貝 /usr/share/ipxe/undionly.kpxe & ipxe.efi 到 /home/acfs/tftpboot/ dhcpd.conf 設定檔會用到
cp -arf /usr/share/ipxe/undionly.kpxe /home/acfs/tftpboot/
cp -arf /usr/share/ipxe/ipxe.efi /home/acfs/tftpboot/

###新增 win10-main.ipxe  dhcpd.conf 設定檔會用到
#cat > /home/acfs/tftpboot/win10/win10-main.ipxe << EOF
##!ipxe
##dhcp
#set keep-san 1
#set initiator-iqn iqn.2019-08.win10.acfs:desktop
#sanboot iscsi:192.168.10.254::3260:0:iqn.2019-08.win10.acfs:main
#boot
#EOF

sync
sync
reboot

(六)先在客戶端電腦安裝一個 Windows 10 1809 或 1903 專業教育版 的作業系統(包含一些您想預裝的應用程式等....),然後 ghost 起來備用
掛載 iSCSI 磁碟機 
##參考以下網頁 http://blog.ilc.edu.tw/blog/index.php?op=printView&articleId=690759&blogId=25793
掛載成磁碟機後就可以用 ghost 檔把客戶端的 Windows 10 系統 整個複製(ghost)到 iSCSI 磁碟中
#HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Memory Management\PagingFiles
#HKEY_LOCAL_MACHINE\SYSTEM\ControlSet001\Control\Session Manager\Memory Management\ExistingPageFiles
#以上二個修改為空字串

###如用vhdx安裝 Windows 10 要在以下值設定為4
HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\services\FsDepends\Parameters\VirtualDiskExpandOnMount


#diskpart
#list disk
#select disk z (where z is the number corresponding for your USB disk. You have to replace it with the corresponding letter from your own system).
#SELECT PARTITION=1
#active
#exit
######
##掛載 Windows 10 安裝光碟 ISO 檔到 (F: 槽)
##複製光碟內容到已掛載 iSCSI 磁碟中 (G: 槽)
#F:
#cd boot
#bootsect.exe /nt60 G: /mbr
#
#

####進入客戶端電腦 BIOS ,設定網卡 ROM 啟動
####測試是否能無硬碟開機進入 Windows 10 系統

####以下是製作多個快照、iSCSI磁碟機及設定dhcpd.conf,以便多台電腦可以同時連線

###
###
##產生多個 20G 維護快照 
lvcreate -L 20G -s -n lv_st1 /dev/vg_iscsi/lv_main
lvcreate -L 20G -s -n lv_st2 /dev/vg_iscsi/lv_main
lvcreate -L 20G -s -n lv_st3 /dev/vg_iscsi/lv_main

#建立 iSCSI 連線磁碟機 (快照 Windows 10 系統用)
targetcli << EOF
backstores/block create name=win10_st1 dev=/dev/vg_iscsi/lv_st1
iscsi/ create iqn.2019-08.win10.acfs:st1
iscsi/iqn.2019-08.win10.acfs:st1/tpg1/acls create iqn.2019-08.win10.acfs:desktop
iscsi/iqn.2019-08.win10.acfs:st1/tpg1/luns create /backstores/block/win10_st1
backstores/block create name=win10_st2 dev=/dev/vg_iscsi/lv_st2
iscsi/ create iqn.2019-08.win10.acfs:st2
iscsi/iqn.2019-08.win10.acfs:st2/tpg1/acls create iqn.2019-08.win10.acfs:desktop
iscsi/iqn.2019-08.win10.acfs:st2/tpg1/luns create /backstores/block/win10_st2
backstores/block create name=win10_st3 dev=/dev/vg_iscsi/lv_st3
iscsi/ create iqn.2019-08.win10.acfs:st3
iscsi/iqn.2019-08.win10.acfs:st3/tpg1/acls create iqn.2019-08.win10.acfs:desktop
iscsi/iqn.2019-08.win10.acfs:st3/tpg1/luns create /backstores/block/win10_st3
EOF

##Linux 掛載 iSCSI 磁碟機
cat > /etc/iscsi/initiatorname.iscsi << EOF
InitiatorName=iqn.2019-08.win10.acfs:desktop
EOF

service iscsi restart
iscsiadm -m discovery -t st -p 192.168.10.254
iscsiadm -m node -T iqn.2019-08.win10.acfs:st1 -p 192.168.10.254 -l
iscsiadm -m session
fdisk -l
ntfsfix /dev/sdd1
mount /dev/sdd1 /mnt

###加入多個客戶端連線
cat >> /etc/dhcp/dhcpd.conf << EOF

        host st1 {
                      #copy the id corresponding to the card 客戶端連線網卡實體位址(MAC 位址)
                      hardware ethernet 94:c6:91:f8:06:51;
                      fixed-address 192.168.10.11;
                      option host-name "st1";
                      ddns-hostname "st1";
                      if exists user-class and option user-class = "iPXE" {
                              filename "";
                              option root-path "iscsi:192.168.10.254::::iqn.2019-08.win10.acfs:st1"; 	
                                         }
                 }

        host st2 {
                      #copy the id corresponding to the card 客戶端連線網卡實體位址(MAC 位址)
                      hardware ethernet 94:c6:91:f8:09:2f;
                      fixed-address 192.168.10.12;
                      option host-name "st2";
                      ddns-hostname "st2";
                      if exists user-class and option user-class = "iPXE" {
                              filename "";
                              option root-path "iscsi:192.168.10.254::::iqn.2019-08.win10.acfs:st2"; 	
                                         }
                 }

        host st3 {
                      #copy the id corresponding to the card 客戶端連線網卡實體位址(MAC 位址)
                      hardware ethernet f4:4d:30:a1:f8:9a;
                      fixed-address 192.168.10.13;
                      option host-name "st3";
                      ddns-hostname "st3";
                      if exists user-class and option user-class = "iPXE" {
                              filename "";
                              option root-path "iscsi:192.168.10.254::::iqn.2019-08.win10.acfs:st3"; 	
                                         }
                 }
EOF

1. 顯示目前 RAID 狀態
# mdadm --detail /dev/md0 | tail -n 4
    Number   Major   Minor   RaidDevice State
       0       8        1        0      active sync   /dev/sdb1
       1       8       17        1      active sync   /dev/sdc1
       2       8       33        2      active sync   /dev/sdd1

2. 停用 RAID
# mdadm --stop /dev/md0
mdadm: stopped /dev/md03. 移除 RAID
# mdadm --remove /dev/md0

3. 移除 superblocks
# mdadm --zero-superblock /dev/sdb1 /dev/sdc1 /dev/sdd1 /dev/sde1

##部份刪除
#targetcli /iscsi delete iqn.2019-08.win10.acfs:main
#targetcli /backstores/block delete win10_main

##全部刪除 iSCSI
#targetcli clearconfig confirm=True

##刪除一個快照
#lvremove -y /dev/vg_iscsi/lv_st1


###下載 ftp://ftp.jls.idv.tw/firewall.sh
wget -O /bin/firewall.sh ftp://ftp.jls.idv.tw/firewall.sh
chmod 700 /bin/firewall.sh
cat >> /etc/rc.d/rc.local << EOF
/bin/firewall.sh
EOF
chmod 700 /etc/rc.d/rc.local

###於 CentOS 7 中實作差異硬碟 (Differential VHD)，之後改開機至「差異硬碟 win10x64_st.vhdx」
git clone https://github.com/NuxRo/vhd-util /opt/vhd-util
### 建立 win10x64_st.vhdx 快照
/opt/vhd-util/vhd-util.sh snapshot -n win10x64_st.vhdx  -p win10x64.vhdx
### 將 win10x64_st.vhdx 合併回 win10x64.vhdx
/opt/vhd-util/vhd-util.sh  coalesce -n win10x64_st.vhdx

###開一個100G 的 VHDX 檔 type=expandable (動態擴展) type=fixed (固定容量)
C:\>diskpart
create vdisk file=d:\vhdos\win10x64.vhdx maximum=102400 type=expandable

###VHD擴充 50G
C:\>diskpart
select vdisk file=C:\vhdos\win10x64.vhdx
expand vdisk maximum=51200

###於 Windows 中實作差異硬碟 (Differential VHD)，之後改開機至「差異硬碟 win10x64_st.vhdx」
C:\>diskpart
DISKPART>create vdisk file=C:\vhdos\win10x64_st.vhdx parent=C:\vhdos\win10x64.vhdx
DISKPART>create vdisk file=C:\vhdos\win10x64_rcst.vhdx parent=C:\vhdos\win10x64.vhdx

###於 Windows 中實作差異硬碟合併(父系、子系)
C:\>diskpart
select vdisk file=C:\vhdos\win10x64_st.vhdx
merge vdisk depth=1


