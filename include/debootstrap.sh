#!/bin/bash
#
#             UU                                                              
#         U   UU  UU                                                          
#         UU  UU  UU                                                          
#         UU  UU  UU  UU                                                      
#         UU  UU  UU  UU                                                      
#         UU  UUU UU  UU                                 Filesystem Builder   
#                                                                             
#         UUUUUUUUUUUUUU  DDDDDDDDDD         OOOOOOOO         OOOOOOOOO       
#    UUU  UUUUUUUUUUUUUU  DDDDDDDDDDDD     OOOOOOOOOOOO     OOOOOOOOOOOOO     
#     UUU UUUUUUUUUUUUUU  DDDDDDDDDDDDD  OOOOOOOOOOOOOOOO  OOOOOOOOOOOOOOOO   
#       UUUUUUUUUUUUUUUU  DDDDDDDDDDDDD  OOOOOOOOOOOOOOOO  OOOOOOOOOOOOOOOO   
#        UUUUUUUUUUUUUU   DDDDDDDDDDDDD  OOOOOOOOOOOOOOOO  OOOOOOOOOOOOOOOO   
#          UUUUUUUUUUUU   DDDDDDDDDDDD    OOOOOOOOOOOOOO    OOOOOOOOOOOOOO    
#           UUUUUUUUUU    DDDDDDDDDDD       OOOOOOOOOO        OOOOOOOOOO      
#
#   Author: Francesco Montefoschi <francesco.monte@gmail.com>
#   Author: Ettore Chimenti <ek5.chimenti@gmail.com>
#   Based on: Igor Pečovnik's work - https://github.com/igorpecovnik/lib
#   License: GNU GPL version 2
#
################################################################################

checkroot
umountroot

export LC_ALL=C LANGUAGE=C LANG=C
UBUNTURELEASE="vivid"

echo -e "Debootstrapping" >&1 >&2

debootstrap  --foreign \
             --arch=armhf \
             --include=ubuntu-keyring \
             $UBUNTURELEASE "$ROOTFS" http://127.0.0.1:3142/ports.ubuntu.com

(( $? )) && error "Debootstrap exited with error $?"
             
echo -e "Using emulator to finish install" >&1 >&2
cp /usr/bin/qemu-arm-static "$ROOTFS/usr/bin"
chroot "$ROOTFS/" /bin/bash -c "dpkg -i /var/cache/apt/archives/ubuntu-keyring*.deb"
chroot "$ROOTFS/" /bin/bash -c "/debootstrap/debootstrap --second-stage"

mountroot
echo -e "Disabling services" >&1 >&2
mkdir "$ROOTFS/fake"
for i in initctl invoke-rc.d restart start stop start-stop-daemon service
do
  ln -s /bin/true "$ROOTFS/fake/$i" || error "Cannot make link to /bin/true, stopping.."
done

cp patches/gpg.key "$ROOTFS/tmp/"

echo -e "Upgrade, dist-upgrade" >&1 >&2
install -m 644 patches/01proxy          "$ROOTFS/etc/apt/apt.conf.d/01proxy"
install -m 644 patches/sources.list     "$ROOTFS/etc/apt/sources.list"
install -m 644 patches/udoo.list        "$ROOTFS/etc/apt/sources.list.d/udoo.list"
install -m 644 patches/udoo.preferences "$ROOTFS/etc/apt/preferences.d/udoo"
sed -e "s/UBUNTURELEASE/$UBUNTURELEASE/g" -i "$ROOTFS/etc/apt/sources.list"

chroot "$ROOTFS/" /bin/bash -c "apt-key add /tmp/gpg.key"
chroot "$ROOTFS/" /bin/bash -c "apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 40976EAF437D05B5"
chroot "$ROOTFS/" /bin/bash -c "apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 3B4FE6ACC0B21F32"

chroot "$ROOTFS/" /bin/bash -c "apt-get -y update"
chroot "$ROOTFS/" /bin/bash -c "apt-get -y -f install"
chroot "$ROOTFS/" /bin/bash -c 'PATH=/fake:$PATH apt-get -y dist-upgrade'
chroot "$ROOTFS/" /bin/bash -c 'PATH=/fake:$PATH apt-get -y -qq install locales'
chroot "$ROOTFS/" /bin/bash -c "locale-gen en_US.UTF-8 it_IT.UTF-8 en_GB.UTF-8"
chroot "$ROOTFS/" /bin/bash -c "export LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8"
chroot "$ROOTFS/" /bin/bash -c "export DEBIAN_FRONTEND=noninteractive"
chroot "$ROOTFS/" /bin/bash -c "update-locale LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_MESSAGES=POSIX"

echo -e "Install packages" >&1 >&2
chroot "$ROOTFS/" /bin/bash -c "PATH=/fake:$PATH DEBIAN_FRONTEND=noninteractive apt-get -y install ${BASE_PACKAGES[*]}"

if [ "$BUILD_DESKTOP" = "yes" ]; then
  echo -e "Install desktop environment" >&1 >&2
  chroot "$ROOTFS/" /bin/bash -c "PATH=/fake:$PATH DEBIAN_FRONTEND=noninteractive apt-get -y install ${DESKTOP_PACKAGES[*]}"
fi

echo -e "Cleanup" >&1 >&2
#touch "$ROOTFS/etc/init.d/modemmanager"
chroot "$ROOTFS/" /bin/bash -c "DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq ${UNWANTED_PACKAGES[*]}"
chroot "$ROOTFS/" /bin/bash -c 'PATH=/fake:$PATH apt-get autoremove -y'
chroot "$ROOTFS/" /bin/bash -c 'PATH=/fake:$PATH apt-get clean -y'
chroot "$ROOTFS/" /bin/bash -c 'PATH=/fake:$PATH apt-get autoclean -y'

rm "$ROOTFS/etc/apt/apt.conf.d/01proxy"
rm -rf "$ROOTFS/fake"

umountroot

echo -n "Saving everything in a tar..."  >&1 >&2
tar -czpf "${ROOTFS}_deboot_$(date +%Y%m%d%H%M).tar.gz" "$ROOTFS"
echo "Done!" >&1 >&2