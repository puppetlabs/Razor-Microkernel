#!/bin/sh
set -e

if test `id -u` -ne 0; then
    echo "Rebuilding the ISO image requires (fake)root capabilities."
    echo "You can either run under fakeroot, or as real root."
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
