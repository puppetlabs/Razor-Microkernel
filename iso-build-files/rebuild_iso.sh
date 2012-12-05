#!/bin/bash
set -ex

PATH=/sbin:/usr/sbin:/bin:/usr/bin

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
DIR_NAME="${PWD}"

if test `id -u` -ne 0; then
    echo "Rebuilding the ISO image requires (fake)root capabilities."
    echo "You can either run under fakeroot, or as real root."
    exit 1
fi

# We need to work out which of the set of tool names for building ISO images
# is used on this platform, and save it for later.
GENISO=$(type -p genisoimage)
test x"$GENISO" = x"" && GENISO=$(type -p mkisofs)
if test x"$GENISO" = x""; then
    echo "Rebuilding the ISO image requires genisoimage or mkisofs."
    echo "Please install one of them; prefer genisoimage."
    exit 1
fi

origdir='original-iso-files'

rm -rf ${origdir} extract newiso

# extract the TCL boot files from the original ISO
mkdir ${origdir}
7z -o${origdir} x Core-current.iso

# Remove the El-Torito boot image that 7zip unpacked for us
rm -r ${origdir}/'[BOOT]'

# extract the boot/core.gz file from that directory to a temporary location
# where we can rebuild...
mkdir extract
cd extract
zcat ../${origdir}/boot/core.gz | cpio -i -H newc -d

# unpack the dependency files that were extracted earlier (these files were
# built from the current contents of the Razor-Microkernel project using the
# build-dependency-files.sh shell script, which is part of that same project)
for file in mk-open-vm-tools.tar.gz razor-microkernel-overlay.tar.gz mcollective-setup-files.tar.gz ssh-setup-files.tar.gz; do
    # all of these files may not exist for all Microkernels, so only try to
    # unpack the files that do exist
    if [ -r ../dependencies/$file ]; then
        echo "extracting ${file}"
        tar zxf ../dependencies/$file
    fi
done

cd ..
mkdir newiso
cp -rp ${origdir}/boot newiso
sed -i "s/timeout 300/timeout 100/" newiso/boot/isolinux/isolinux.cfg

# build the YAML file in the Microkernel's filesystem that will be used to
# display this same version information during boot
./add_version_to_mk_fs.rb extract ${ISO_VERSION}

# Run chroot and ldconfig on the extract directory (preparing it for
# construction of a bootable core.gz file)
#
# We need to modify one symlink from absolute to relative to support doing
# this without the need for a `chroot` jail - which means we can fully build
# the ISO image without root privileges.
KERNEL_VERSION="$(ls "${DIR_NAME}/extract/lib/modules")"
ln -sf "../../../usr/local/lib/modules/${KERNEL_VERSION}/kernel" \
    "extract/lib/modules/${KERNEL_VERSION}/kernel.tclocal"
depmod -b "${DIR_NAME}/extract" -a "${KERNEL_VERSION}"
ldconfig -r "${DIR_NAME}/extract"
# build the new core.gz file (containing the contents of the extract directory)
cd extract
find | cpio -o -H newc | gzip -9 > ../core.gz
cd ..
# compress the file and copy it to the correct location for building the ISO
advdef -z4 core.gz
cp -p core.gz newiso/boot/
# build the YAML file needed for use in Razor, place it into the root of the
# ISO filesystem
./build_iso_yaml.rb newiso ${ISO_VERSION} boot/vmlinuz boot/core.gz

# finally, build the ISO itself from the newiso directory
"${GENISO}" -l -J -R -V TC-custom \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -b boot/isolinux/isolinux.bin \
    -c boot/isolinux/boot.cat \
    -o "${ISO_NAME}" newiso
