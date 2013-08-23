#!/usr/bin/env bash
#
# Used to build the bundle file needed to build a new version of the
# Razor Microkernel ISO (from the contents of the Razor Microkernel
# project and it's dependencies.  The file built by this script can
# be copied over to another directory (on another machine?) and unpacked.
# Once it has been unpacked, running the 'build_initial_directories.sh'
# script in that directory, followed by the 'rebuild_iso.sh' script,
# will result in a new ISO built from the current state of the this
# (Razor-Microkernel) project.
#
# Note:  the bundle file does not creaate a subdirectory, so a new, clean
#    directory should be used when unpacking the bundle file to build a
#    new version of the Microkernel ISO.

# define a function we can use to print out the usage for this script

usage()
{
cat << EOF

Usage: $0 OPTIONS

This script builds a gzipped tarfile containing all of the files necessary to
build an instance of the Razor Microkernel ISO.

OPTIONS:
   -h, --help                 print usage for this command
   -b, --builtin-list=FILE    file containing extensions to install as builtin
   -m, --mirror-list=FILE     file containing extensions to add to TCE mirror
   -p, --build-prod-image     build a production ISO (no openssh, no passwd)
   -d, --build-debug-image    build a debug ISO (enable automatic console login)
   -t, --tc-passwd=PASSWD     specify a password for the tc user
   -c, --config=FILE          optional: specify a file containing configuration 
                                values; see bundle.cfg.example
   -v, --verbose              be (extremely) verbose about the build process

Note; currently, the default is to build a development ISO (which includes the
openssh.tcz extension along with the openssh/openssl configuration file changes
and the passwd changes needed to access the Microkernel image from the command
line or via the console).  Also note that only one of the '-p' and '-d' flags
may be specified and the '-t' option may not be used when building a production
ISO (using the '-p' flag).

EOF
}

# Define a function to read configuration-values in from a file
read_config_file()
{
  while read LINE; do
    VAR=`printf '%s' "$LINE" | sed 's|\(.*\)=.*|\1|'`

    VAL=`printf '%s' "$LINE" | sed 's|.*=\(.*\)|\1|'`
    eval "$VAR=\"$VAL\""
  done < $1
}

# options may be followed by one colon to indicate they have a required argument
if ! options=$(getopt -o hb:m:pdt:c:v -l help,builtin-list:,mirror-list:,build-prod-image,build-debug-image,tc-passwd:,config:,verbose,dpkg-list: -- "$@")
then
    usage
    # something went wrong, getopt will put out an error message for us
    exit 1
fi
set -- $options

# Some internal defaults - be quiet by default.
WGET_V='-nv'
TAR_V=''

# Explicitly create DEB_PACKAGE_LIST_URL as an array
DEB_PACKAGE_LIST_URL=()

# loop through the command line arguments, parsing them as we go along
# (and shifting them off of the list of command line arguments as they,
# and their arguments if they have any, are parsed).  Note the use of
# the 'tr' and 'sed' commands when parsing the command arguments. The
# 'tr' command is used to remove the leading and trailing quotes from
# the arguments while the 'sed' command is used to remove the leading
# equals sign from the argument (if it exists).
BUNDLE_TYPE_SELECTED=0
while [ $# -gt 0 ]
do
  case $1 in
  -b|--builtin-list) BUILTIN_LIST=`echo $2 | tr -d "'" | sed 's:^[=]\?\(.*\)$:\1:'`; shift;;
  -m|--mirror-list) MIRROR_LIST=`echo $2 | tr -d "'" | sed 's:^[=]\?\(.*\)$:\1:'`; shift;;
  -p|--build-prod-image) 
    if [ $BUNDLE_TYPE_SELECTED -eq 0 ]; then 
      BUNDLE_TYPE='prod'; 
      BUNDLE_TYPE_SELECTED=1
    else 
      printf '%s: ERROR, cannot specify both -d and -p\n' "$0"
      printf '    (bundle must be either prod or debug, not both)\n'
      usage
      exit 1
    fi
    ;;
  -d|--build-debug-image)
    if [ $BUNDLE_TYPE_SELECTED -eq 0 ]; then 
      BUNDLE_TYPE='debug'; 
      BUNDLE_TYPE_SELECTED=1
    else 
      printf '%s: ERROR, cannot specify both -d and -p\n' "$0"
      printf '    (bundle must be either prod or debug, not both)\n'
      usage
      exit 1
    fi
    ;;
  -t|--tc-passwd)
    TC_PASSWD=`echo $2 | tr -d "'"`
    test1=`echo $TC_PASSWD | grep '^c-passwd='`
    if [[ ! -z $test1 ]]; then
      test=`echo $test1 | sed 's:^c-passwd=\(.*\)$:\1:'`
      printf '%s: WARNING, found value that looks like it includes part' "$0"
      printf ' of the long argument name (%s); should the password value be' "$TC_PASSWD"
      printf ' "%s" instead?\n' "$test"
    fi;
    test2=`echo $TC_PASSWD | grep '^='`
    if [[ ! -z $test2 ]]; then
      printf "%s: WARNING, password value with a leading '=' found" "$0"
      printf " (%s), did you use an '=' between the short argument (-t)" "$test2"
      printf " and its value? If so, you might not get the password you expect...\n"
    fi;
    shift;;
  --dpkg-list)
    DEB_PACKAGE_LIST_URL+=(`echo $2 | tr -d "'"`)
    shift;;
  -c|--config) CONFIG_FILE=`printf '%s' "$2" | tr -d "'" | sed 's:^[=]\?\(.*\)$:\1:'`; shift;;
  -h|--help) usage; exit 0;;
  -v|--verbose)
          TAR_V='v'
          WGET_V='-v'
          ;;
  (--) shift; break;;
  (-*) echo "$0: error - unrecognized option $1" 1>&2; usage; exit 1;;
  esac
  shift
done

# if there are still arguments left, the syntax of the command is wrong
# (there were extra arguments given that don't belong)
if [ ! $# -eq 0 ]; then
  echo "$0: error - extra fields included in commmand; remaining args=$@" 1>&2; usage; exit 1
fi

# If a config-file was specified on the command-line, read it into the
# environment (obliterating any values already in the environment)
if [ -n "$CONFIG_FILE" ]; then
  read_config_file $CONFIG_FILE
fi
# Use any config-values which were provided in the config file or environment 
# variables, but not over-ridden on the command-line
[ -z "$BUILTIN_LIST" -a -n "$MK_BUNDLE_BUILTIN_LIST" ] && 
  BUILTIN_LIST="$MK_BUNDLE_BUILTIN_LIST"
[ -z "$MIRROR_LIST" -a -n "$MK_BUNDLE_MIRROR_LIST" ] && 
  MIRROR_LIST="$MK_BUNDLE_MIRROR_LIST"
[ -z "$TC_PASSWD" -a -n "$MK_BUNDLE_TC_PASSWD" ] && 
  TC_PASSWD="$MK_BUNDLE_TC_PASSWD"
[ -z "$BUNDLE_TYPE" -a -n "$MK_BUNDLE_TYPE" ] && 
  BUNDLE_TYPE="$MK_BUNDLE_TYPE"
[ -z "$TCL_MIRROR_URI" -a -n "$MK_BUNDLE_TCL_MIRROR_URI" ] && 
  TCL_MIRROR_URI="$MK_BUNDLE_TCL_MIRROR_URI"
[ -z "$TCL_ISO_URL" -a -n "$MK_BUNDLE_TCL_ISO_URL" ] && 
  TCL_ISO_URL="$MK_BUNDLE_TCL_ISO_URL"
[ -z "$RUBY_GEMS_URL" -a -n "$MK_BUNDLE_RUBY_GEMS_URL" ] && 
  RUBY_GEMS_URL="$MK_BUNDLE_RUBY_GEMS_URL"
[ -z "$OPEN_VM_TOOLS_URL" -a -n "$MK_BUNDLE_OPEN_VM_TOOLS_URL" ] && 
  OPEN_VM_TOOLS_URL="$MK_BUNDLE_OPEN_VM_TOOLS_URL"
[ -z "$GEM_SERVER_URI" -a -n "$MK_BUNDLE_GEM_SERVER_URI" ] && 
  GEM_SERVER_URI="$MK_BUNDLE_GEM_SERVER_URI"

# Set to default anything still not specified, for which there is a reasonable
# default-value
[ -z "$BUNDLE_TYPE" ] && BUNDLE_TYPE='dev'
[ -z "$TCL_MIRROR_URI" ] && TCL_MIRROR_URI='http://distro.ibiblio.org/tinycorelinux/4.x/x86/tcz'
[ -z "$TCL_ISO_URL" ] && TCL_ISO_URL='http://distro.ibiblio.org/tinycorelinux/4.x/x86/release/Core-current.iso'
[ -z "$RUBY_GEMS_URL" ] && RUBY_GEMS_URL='http://production.cf.rubygems.org/rubygems/rubygems-1.8.24.tgz'
[ -z "$OPEN_VM_TOOLS_URL" ] && OPEN_VM_TOOLS_URL='http://downloads.puppetlabs.com/razor/open-vm-tools/mk-open-vm-tools.tar.gz'
[ -z "${DEB_PACKAGE_LIST_URL[*]}" ] && DEB_PACKAGE_LIST_URL[0]='http://distro.ibiblio.org/tinycorelinux/5.x/x86/debian_wheezy_main_i386_Packages.gz'
[ -z "$DEB_MIRROR_URL" ] && DEB_MIRROR_URL='ftp://ftp.us.debian.org/debian'

# Save our top level directory; watch out for spaces!
TOP_DIR="${PWD}"

# otherwise, sanity check the arguments that were parsed to ensure that
# the required arguments are present and the optional ones make sense
# (in terms of which optional arguments were given, and in what combination)
if [[ -z $BUILTIN_LIST ]] || [[ -z $MIRROR_LIST ]]; then
  printf "\nError (Missing Argument); the 'builtin-list' and 'mirror-list' must both be specified\n"
  usage
  exit 1
elif [ ! -r $BUILTIN_LIST ] || [ ! -r $MIRROR_LIST ]; then
  printf "\nError; the 'builtin-list' and 'mirror-list' values must both be readable files;"
  printf ' values parsed are as follows:\n'
  printf '\tbuiltin-list\t=> "%s"\n' "$BUILTIN_LIST"
  printf '\tmirror-list\t=> "%s"\n' "$MIRROR_LIST"
  usage
  exit 1
elif [ "$BUNDLE_TYPE" != 'prod' ] && [ "$BUNDLE_TYPE" != 'debug' ] && [ "$BUNDLE_TYPE" != 'dev' ]; then
  printf "\nBundle type must be one of 'prod', 'dev', or 'debug'\n"
  usage
  exit 1
elif [[ ! -z $TC_PASSWD ]] && [ $BUNDLE_TYPE = 'prod' ]; then
  printf "Warning; a 'tc' password cannot be set for a production Microkernel ISO,\n"
  printf "     the specified password (${TC_PASSWD}) will be ignored\n"
fi

# Make sure we're starting with a clean (i.e. empty) build directory to hold
# the gzipped tarfile that will contain all of dependencies
rm -rf tmp-build-dir
mkdir -p tmp-build-dir/build_dir/dependencies

# copy over the scripts that are needed to actually build the ISO into
# the build_dir (from there, they will be included into a single
# gzipped tarfile that can be unpacked and will contain almost all of
# the files/tools needed to build the Microkernel ISO)
cp -p iso-build-files/* tmp-build-dir/build_dir
if [ $BUNDLE_TYPE = 'prod' ]; then
  sed -i 's/ISO_NAME=rz_mk_dev-image/ISO_NAME=rz_mk_prod-image/' tmp-build-dir/build_dir/rebuild_iso.sh
elif [ $BUNDLE_TYPE = 'debug' ]; then
  sed -i 's/ISO_NAME=rz_mk_dev-image/ISO_NAME=rz_mk_debug-image/' tmp-build-dir/build_dir/rebuild_iso.sh
fi

# create a copy of the modifications to the DHCP client configuration that
# are needed for the Razor Microkernel Controller to find the appropriate
# Razor server for it's first checkin
mkdir -p tmp-build-dir/etc/init.d
cp -p etc/init.d/dhcp.sh tmp-build-dir/etc/init.d
mkdir -p tmp-build-dir/usr/share/udhcpc
cp -p usr/share/udhcpc/dhcp_mk_config.script tmp-build-dir/usr/share/udhcpc

# create copies of the files from this project that will be placed
# into the /usr/local/bin directory in the Razor Microkernel ISO
mkdir -p tmp-build-dir/usr/local/bin
cp -p rz_mk_*.rb tmp-build-dir/usr/local/bin

# create copies of the files from this project that will be placed
# into the /usr/local/lib/ruby/1.8/razor_microkernel directory in the Razor
# Microkernel ISO
mkdir -p tmp-build-dir/usr/local/lib/ruby/1.8/razor_microkernel
cp -p razor_microkernel/*.rb tmp-build-dir/usr/local/lib/ruby/1.8/razor_microkernel

# create a copy of the files from this project that will be placed into the
# /opt directory in the Razor Microkernel ISO; as part of this process will
# download the latest version of the gems in the 'gem.list' file into the
# appropriate directory to use in the build process (rather than including
# fixed versions of those gems as part of the Razor-Microkernel project)
mkdir -p tmp-build-dir/opt
cp -t tmp-build-dir/opt -p opt/boot*.sh
chmod +rx tmp-build-dir/opt/boot*.sh
[ -n "$GEM_SERVER_URI" ] && GEM_SERVER_ARG="-s $GEM_SERVER_URI"
./bin/mirror-gem $GEM_SERVER_ARG -d tmp-build-dir/tmp/gem-mirror -f opt/gems/gem.list

# Add GemRC file to the ISO to use the mirror
cp -p opt/gems/gem.list tmp-build-dir/tmp/gem-mirror/gems/gem.list
mkdir -p tmp-build-dir/root
cp rz_mk_gemrc.yaml tmp-build-dir/root/.gemrc

# Download the .deb package list if necessary
if [ ! -z "`cat "$MIRROR_LIST" "$BUILTIN_LIST" | grep .deb$`" ]; then
  LIST_ARGS=""
  for URL in "${DEB_PACKAGE_LIST_URL[@]}"; do
    echo $URL
    LIST_ARGS+=" --list-url $URL"
  done
  ./bin/download-deb-pkg-list $LIST_ARGS --download-dir "./tmp/" --list-file "./tmp/dpkg-package-list"
fi

# create a copy of the local TCL Extension mirror that we will be running within
# our Microkernel instances
mkdir -p tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz
cp -p tmp/tinycorelinux/*.yaml tmp-build-dir/tmp/tinycorelinux
for file in `cat $MIRROR_LIST`; do
  if [ ${file##*.} != "deb" ]; then
    wget $WGET_V -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file
    wget $WGET_V -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file.md5.txt
    wget $WGET_V -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file.info
    wget $WGET_V -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file.list
    wget $WGET_V -P tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz $TCL_MIRROR_URI/$file.dep
  else
    PKGNAME=${file%.*}
    echo "Installing .deb package for mirroring: $PKGNAME"
    ./bin/download-deb-pkg --list-file "./tmp/" --mirror-url "$DEB_MIRROR_URL" --output-dir ./tmp/ $PKGNAME
    ./bin/deb2tcz.sh ./tmp/$PKGNAME.deb tmp-build-dir/tmp/tinycorelinux/4.x/x86/tcz/$PKGNAME.tcz

  fi
done

# download a set of extensions that will be installed during the Microkernel
# boot process.  These files will be placed into the /tmp/builtin directory in
# the Microkernel ISO.  The list of files downloaded (and loaded at boot) are
# assumed to be contained in the file specified by the BUILTIN_LIST parameter
echo "working in ${PWD}"
mkdir -p tmp-build-dir/tmp/builtin/optional
rm tmp-build-dir/tmp/builtin/onboot.lst 2> /dev/null
for file in `cat $BUILTIN_LIST`; do
  if [ ${file##*.} != "deb" ]; then
    if [ $BUNDLE_TYPE != 'prod' ] || [ ! $file = 'openssh.tcz' ]; then
        wget $WGET_V -P tmp-build-dir/tmp/builtin/optional $TCL_MIRROR_URI/$file
        wget $WGET_V -P tmp-build-dir/tmp/builtin/optional $TCL_MIRROR_URI/$file.md5.txt
        wget $WGET_V -P tmp-build-dir/tmp/builtin/optional $TCL_MIRROR_URI/$file.dep
        echo $file >> tmp-build-dir/tmp/builtin/onboot.lst
    elif [ $BUNDLE_TYPE = 'prod' ] && [ -f tmp-build-dir/tmp/builtin/optional/$file ]
    then
        rm tmp-build-dir/tmp/builtin/optional/$file
        rm tmp-build-dir/tmp/builtin/optional/$file.md5.txt 2> /dev/null
        rm tmp-build-dir/tmp/builtin/optional/$file.dep 2> /dev/null
    fi
  else
    PKGNAME=${file%.*}
    echo "Installing .deb package as builtin: $PKGNAME"
    ./bin/download-deb-pkg --list-file "./tmp/dpkg-package-list" --mirror-url "$DEB_MIRROR_URL" --output-dir ./tmp/ $PKGNAME
    ./bin/deb2tcz.sh ./tmp/$PKGNAME.deb tmp-build-dir/tmp/builtin/optional/$PKGNAME.tcz
    echo $PKGNAME.tcz >> tmp-build-dir/tmp/builtin/onboot.lst
  fi
done

# download the ruby-gems distribution (will be installed during the boot
# process prior to starting the Microkernel initialization process)
file=`echo $RUBY_GEMS_URL | awk -F/ '{print $NF}'`
wget $WGET_V -P tmp-build-dir/opt $RUBY_GEMS_URL

# copy over a couple of initial configuration files that will be included in the
# /tmp and /etc directories of the Microkernel instance (the first two control the
# initial behavior of the Razor Microkernel Controller, the third disables automatic
# login of the tc user when the Microkernel finishes booting)
cp -p tmp/first_checkin.yaml tmp-build-dir/tmp
if [ $BUNDLE_TYPE = 'debug' ]
then
  # if we're building a "debug" bundle, then copy over a microkernel configuration
  # file that will enable logging of DEBUG messages from the start
  cp -p tmp/mk_conf_debug.yaml tmp-build-dir/tmp/mk_conf.yaml
else
  # else copy over a file that will only enable logging of INFO/ERROR messages
  # from the start
  cp -p tmp/mk_conf.yaml tmp-build-dir/tmp
fi
cp -p etc/inittab tmp-build-dir/etc
# check to see if we're building a "Debug ISO"; if so, use sed to modify the inittab
# file we just copied over so that re-enables autologin
if [ $BUNDLE_TYPE = 'debug' ]; then
  AUTO_LOGIN_STR='-nl /sbin/autologin'
  OLD_INITTAB_TTY1_PAT='^\(tty1.*\)\(38400 tty1\)$'
  sed -i "s/$OLD_INITTAB_TTY1_PAT/\1$(echo $AUTO_LOGIN_STR | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/&/\\\&/g') \2/" tmp-build-dir/etc/inittab
fi

# get a copy of the current Tiny Core Linux "Core" ISO
file=`echo $TCL_ISO_URL | awk -F/ '{print $NF}'`
wget $WGET_V -P tmp-build-dir/build_dir $TCL_ISO_URL

# add a soft-link in what will become the /usr/local/sbin directory in the
# Microkernel ISO (this fixes an issue with where Facter expects to find
# the 'dmidecode' executable)
mkdir -p tmp-build-dir/usr/sbin
rm tmp-build-dir/usr/sbin 2> /dev/null
ln -s /usr/local/sbin/dmidecode tmp-build-dir/usr/sbin 2> /dev/null

# copy over a few additional dependencies (currently, this includes the
# following files:
#   1. ssh-setup-files.tar.gz -> contains the setup files needed for the
#         SSH/SSL (used for development access to the Microkernel); if
#         the '--build-prod-image' flag is set, then this file will be skipped
#   2. mk-open-vm-tools.tar.gz -> contains the files needed for the
#         'open_vm_tools.tcz' extension
#   3. the etc/passwd and etc/shadow files from the Razor-Microkernel project
#         (note; if this is a production system then the etc/shadow-nologin
#         file will be copied over instead of the etc/shadow file (to block
#         access to the Microkernel from the console)
cp -p additional-build-files/*.gz tmp-build-dir/build_dir/dependencies
file=`echo $OPEN_VM_TOOLS_URL | awk -F/ '{print $NF}'`
wget $WGET_V -P tmp-build-dir/build_dir/dependencies $OPEN_VM_TOOLS_URL

# get the latest util-linux.tcz, then extract the two executables that
# we need from that file (using the unsquashfs command)
#
# TJMCS as per https://github.com/puppetlabs/Razor-Microkernel/issues/45#issuecomment-12376846
#
# The reason we're only pulling a couple of binaries out of this package
# (rather than installing the entire util-linux TCE) is that we ran into
# issues with Facter (if I remember correctly) when some of the utilities
# contained in that package were installed. Rather than trying to get the
# issues with Facter resolved for the busybox versions of some of these
# commands (which are different from more standard Linux distributions), it
# was felt that we should just install the bits that we need out of that
# particular TCE...
file='util-linux.tcz'
wget $WGET_V -P tmp-build-dir $TCL_MIRROR_URI/$file
unsquashfs -f -d tmp-build-dir tmp-build-dir/util-linux.tcz `cat additional-build-files/util-linux-exec.lst`

echo ""
echo "************************************************************************"
echo "All resources downloaded, configuring:"

# Copy over the etc/passwd file to the tmp-build-dir/etc directory.
# If we're building a production system, development system, also copy over the
# etc/shadow file to the same directory.  If it's a production system we're
# building the ISO for, then copy over the etc/shadow-nologin file instead
# (and remove the SSH setup files from the files we just copied over to the
# dependencies directory)
cp -p etc/passwd tmp-build-dir/etc
if [ $BUNDLE_TYPE != 'prod' ]; then
  cp -p etc/shadow tmp-build-dir/etc
  # if a password for the tc user was passed in (using the -t or --tc-passwd flag)
  # then use it to replace the default password for the tc user in the shadow
  # password file we're burning into the ISO here (requires that openssl be installed
  # locally for this to work)
  #
  # The default password for the debug and development flavours.  Since this is
  # a publicly documented default password, there is no greater security
  # exposure putting it here than manually putting it into the build process.
  #
  # The purpose is to allow users who run the dev/debug builds to log in, so in
  # that regard it is necessary to include the password, and to publicly
  # document it.
  #
  # Without that ability, the debug and dev builds are literally useless, so we
  # also can't omit the password - at least for now.
  #
  # This will set the password to the default, if it wasn't already set.
  : TC_PASSWD=${TC_PASSWD:=test1234}

  echo " * Changing password for 'tc' user to $TC_PASSWD"
  NEW_PWD_ENTRY=`echo $TC_PASSWD | openssl passwd -1 -stdin`
  # use sed to replace the default password with the new one generated (above)
  # (but remember, need to escape the replacement string for use with sed first,
  # which is what the "$(echo ... | sed -e ...)" part of this command does; it
  # escapes any '\', '/', and '&' characters in the $NEW_PWD_ENTRY string so that
  # they will be passed as literals during replacement instead of being used as
  # part of the surrounding sed command)
  sed -i "s/^\(tc:\)[^\:]*\(.*\)/\1$(echo $NEW_PWD_ENTRY | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g' -e 's/&/\\\&/g')\2/" tmp-build-dir/etc/shadow
else
  cp -p etc/shadow-nologin tmp-build-dir/etc/shadow
  rm tmp-build-dir/build_dir/dependencies/ssh-setup-files.tar.gz
fi

# determine, and store, the git derived ISO file version into the bundle
gitversion="$(git describe --tags --dirty --always | sed -e 's@-@+@' | sed -e 's/^v//')"
if test $? -gt 0; then
    echo " ! Unable to determine the build version with git!"
    exit 1
fi
echo " * this build is tagged as version [${gitversion}]"
echo "ISO_VERSION='${gitversion}'" > tmp-build-dir/build_dir/gitversion.sh

# ensure the copyright and license content is added to the image
cp COPYING LICENSE tmp-build-dir/build_dir/

# create a gzipped tarfile containing all of the files from the Razor-Microkernel
# project that we just copied over, along with the files that were downloaded from
# the network for the gems and TCL extensions; place this gzipped tarfile into
# a dependencies subdirectory of the build_dir
cd tmp-build-dir
echo " * creating razor microkernel overlay tarball"
tar zc${TAR_V}f build_dir/dependencies/razor-microkernel-overlay.tar.gz usr etc opt tmp root

# and create a gzipped tarfile containing the dependencies folder and the set
# of scripts that are used to build the ISO (so that all the user has to do is
# copy over this one file to a directory somewhere and unpack it and they will
# be ready to build the ISO
bundle_out_file_name='razor-microkernel-bundle-dev.tar.gz'
if [ $BUNDLE_TYPE = 'prod' ]; then
  bundle_out_file_name='razor-microkernel-bundle-prod.tar.gz'
elif [ $BUNDLE_TYPE = 'debug' ]; then
  bundle_out_file_name='razor-microkernel-bundle-debug.tar.gz'
fi

# and, finally, create our bundle file
if [ ! -d "${TOP_DIR}/build-files" ]; then
    # make a directory we can use to build our gzipped tarfile
    mkdir "${TOP_DIR}/build-files"
fi
cd build_dir
echo " * creating build bundle ${bundle_out_file_name}"
tar zc${TAR_V}f "${TOP_DIR}/build-files/${bundle_out_file_name}" *
cd "${TOP_DIR}"
