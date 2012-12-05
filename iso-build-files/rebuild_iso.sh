#!/bin/sh

if [ $# -ne 1 ]
then
  echo "USAGE:  `echo $0 | awk -F'/' '{print $(NF)}' -` ISO_VERSION"
  echo "  where ISO_VERSION is the version of the ISO file you are creating"
  echo "  (it will be transformed into a filename that looks like:"
  echo '        rz_mk_dev-image_${ISO_VERSION}.iso'
  exit
fi

ISO_VERSION=$1
ISO_NAME=rz_mk_dev-image.${ISO_VERSION}.iso
DIR_NAME=`pwd`
set -x
# build the YAML file in the Microkernel's filesystem that will be used to
# display this same version information during boot
./add_version_to_mk_fs.rb extract ${ISO_VERSION}
# run chroot and ldconfig on the extract directory (preparing it for construction
# of a bootable core.gz file)
#chroot ${DIR_NAME}/tmp depmod -a 3.0.21-tinycore
chroot ${DIR_NAME}/extract depmod -a `ls ${DIR_NAME}/extract/lib/modules`
ldconfig -r ${DIR_NAME}/extract
# build the new core.gz file (containing the contents of the extract directory)
cd extract
find | cpio -o -H newc | gzip -2 > ../core.gz
cd ..
# compress the file and copy it to the correct location for building the ISO
advdef -z4 core.gz
cp -p core.gz newiso/boot/
# build the YAML file needed for use in Razor, place it into the root of the
# ISO filesystem
./build_iso_yaml.rb newiso ${ISO_VERSION} boot/vmlinuz boot/core.gz
# finally, build the ISO itself (using the contents of the newiso directory as input
mkisofs -l -J -R -V TC-custom -no-emul-boot -boot-load-size 4   -boot-info-table -b boot/isolinux/isolinux.bin   -c boot/isolinux/boot.cat -o ${ISO_NAME} newiso
