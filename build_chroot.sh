#!/usr/bin/env bash
#
# SPDX-License-Identifier: MPL-2.0
#
# Copyright: © 2024 Serpent OS Developers
#

# build_chroot.sh:
# script for conveniently creating a clean, minimal, self-hosting LupuS root
# suitable for use in a chroot or systemd-nspawn context for testing.

source shared_functions.bash

showHelp() {
    cat <<EOF

This will create an up-to-date LupuS minimal root dir using the -unstable repo.

Current \$PATH:

${PATH}

EOF
}

# clean up env
cleanEnv () {
    unset PISICACHE
    unset LOCALREPO
    unset MSG
    unset PACKAGES
    unset LUPNAME
    unset LUPROOT

    unset BOLD
    unset RED
    unset RESET
    unset YELLOW
}

EDITION=

if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]];
then
    showHelp
    cleanEnv
    exit 1
else
    EDITION="minimal"
    printInfo "Building ${EDITION} self-hosting LupuS chroot environment ..."
fi

LOCALREPO="/var/lib/lupbuild/local"
PISICACHE="/var/cache/pisi/packages"
LUPNAME="lupus_${EDITION}_chroot"
LUPROOT="${PWD}/${LUPNAME}"

checkPrereqs () {
    # prerequisite checks
    test -x $(command -v chroot) || die "\n${0} assumes that chroot is available\n"
    test -x $(command -v pisi.py) || die "\n${0} assumes that pisi.py is available\n"
    test -x $(command -v find) || die "\n${0} assumes that find is available\n"
    test -x $(command -v groupadd) || die "\n${0} assumes that groupadd is available\n"
    test -x $(command -v passwd) || die "\n${0} assumes that passwd is available\n"
    test -x $(command -v systemd-nspawn) || die "\n${0} assumes that systemd-nspawn is available\n"
    test -x $(command -v useradd) || die "\n${0} assumes that useradd is available\n"
    test -x $(command -v yq) || die "\n${0} assumes that yq is available.\n"
    ldconfig -p |grep -q iksemel.so || die "\n${0} assumes that iksemel.so is available (check /etc/ld.so.conf).\n"
}

mountBindMounts() {
    # automagically go out of scope
    local mkdir='sudo mkdir -pv'
    local mount='sudo mount -v'

    MSG="Setting up virtual kernel file systems ..."
    printInfo "${MSG}"
    # NB: systemd-nspawn handles all the necessary /dev setup on its own.
    #${mount} -t devtmpfs devtmpfs "${LUPROOT}"/dev
    #${mkdir} "${LUPROOT}"/dev/pts
    #${mount} -t devpts devpts "${LUPROOT}"/dev/pts
    #${mkdir} "${LUPROOT}"/dev/shm
    #${mount} -t tmpfs tmpfs "${LUPROOT}"/dev/shm
    ${mount} -t proc proc "${LUPROOT}"/proc
    ${mount} -t sysfs sysfs "${LUPROOT}"/sys
    # when systemd-nspawn is not pid1, we need ot mount this ourselves
    ${mount} -t tmpfs tmpfs "${LUPROOT}"/run

    # ensure it exists first
    ${mkdir} "${LUPROOT}${LOCALREPO}"
    if [[ -d "${LOCALREPO}" ]]; then
        MSG="Bind-mounting the host ${LOCALREPO} directory ..."
        printInfo "${MSG}"
        ${mount} --bind "${LOCALREPO}" "${LUPROOT}${LOCALREPO}"
    fi

    # ensure it exists first
    ${mkdir} "${LUPROOT}${PISICACHE}"
    if [[ -d "${PISICACHE}" ]]; then
        MSG="Bind-mounting the host ${PISICACHE} directory ..."
        printInfo "${MSG}"
        ${mount} --bind "${PISICACHE}" "${LUPROOT}${PISICACHE}"
    fi
}

unmountBindMounts() {
    # automagically goes out of scope
    local umount='sudo umount -Rfv'

    if [[ -d "${LUPROOT}/${PISICACHE}" ]]; then
        MSG="Unmounting existing ${LUPROOT}${PISICACHE} bind-mount ..."
        printInfo "${MSG}"
        ${umount} "${LUPROOT}${PISICACHE}"
    fi

    if [[ -d "${LUPROOT}/${LOCALREPO}" ]]; then
        MSG="Unmounting existing ${LUPROOT}${LOCALREPO} bind-mount ..."
        printInfo "${MSG}"
        ${umount} "${LUPROOT}${LOCALREPO}"
    fi

    MSG="Unmounting existing ${LUPROOT} virtual kernel file systems ..."
    printInfo "${MSG}"
    for d in run sys proc; do
        ${umount} "${LUPROOT}"/${d}
        # avoid the kernel tripping itself up and failing to recursively unmount
        sleep 0.5
    done
}

basicSetup () {
    # local variables go out of scope at the end of the function
    local chroot="sudo systemd-nspawn --as-pid2 --quiet -D ${LUPROOT}" # better chroot essentially
    #local chroot="sudo chroot ${LUPROOT}"
    # necessary cruft for sudo to work with the pisi_venv
    local pisi_py3="sudo -E env PATH=${PATH} pisi.py --debug"
    local pisi_bin='pisi.bin --debug'
    local mkdir='sudo mkdir -pv'

    local pisi_py3_path="$(command -v pisi.py)"
    MSG="Path to pisi.py: ${pisi_py3_path}"
    printInfo "${MSG}"
    MSG="Elevated pisi.py command: ${pisi_py3}"
    printInfo "${MSG}"

    # should no longer be necessary
    # unmountBindMounts

    MSG="Removing old ${LUPROOT} directory ..."
    printInfo "${MSG}"
    sudo rm -rf "${LUPROOT}" || { unmountBindMounts && sudo rm -rf "${LUPROOT}"; } || die "${MSG}"

    MSG="Setting up new ${LUPROOT} directory ..."
    printInfo "${MSG}"
    ${mkdir} "${LUPROOT}"/{dev,dev/shm,proc,sys,run} || die "${MSG}"

    mountBindMounts

    if [[ -d "${LOCALREPO}" ]]; then
        MSG="Adding ${LOCALREPO} repo to list of active repositories ..."
        printInfo "${MSG}"
        ls -l "${LUPROOT}/${LOCALREPO}"
        ${pisi_py3} add-repo --ignore-check Local "${LOCALREPO}/pisi-index.xml" -D "${LUPROOT}" || die "${MSG}"
    fi

    MSG="Adding unstable lupus repository ..."
    printInfo "${MSG}"
    ${pisi_py3} add-repo Unstable https://packages.teknoanka.com/unstable/pisi-index.xml.xz -D "${LUPROOT}" || die "${MSG}"

    MSG="Removing automatically (and unhelpfully) added LupuS repo ..."
    printInfo "${MSG}"
    ${pisi_py3} remove-repo LupuS -D "${LUPROOT}" || die "${MSG}"

    MSG="Listing enabled repositories ..."
    printInfo "${MSG}"
    ${pisi_py3} list-repo -D "${LUPROOT}" || die "${MSG}"
    #MSG="Installing baselayout ..."
    #${pisi_py3} install -y -D "${LUPROOT}" --ignore-safety --ignore-comar baselayout || die "${MSG}"

    # Since we're testing pisi.py from a venv, let's use that instead for creating the root
    #MSG="Installing packages to act as a seed for systemd-nspawn chroot runs ..."
    #printInfo "${MSG}"
    #${pisi_py3} install -y -D "${LUPROOT}" --ignore-safety "${SELFHOSTINGPISI[@]}" || die "${MSG}"
    MSG="Installing system.base ..."
    ${pisi_py3} install -y -D "${LUPROOT}" --ignore-safety -c system.base || die "${MSG}"

    MSG="Installing remaining packages from the chroot_pkglist.txt file ..."
    printInfo "${MSG}"
    # The lack of quoting around ${PACKAGES} is deliberate
    ${pisi_py3} install -y -D "${LUPROOT}" ${PACKAGES} || die "${MSG}"
    
    MSG="Adding root group and user in ${LUPROOT} install ..."
    printInfo "${MSG}"
    # setting this as interactive, as the dir won't exist if $LUPROOT is non-empty.
    # IFF by some fluke $LUPROOT is empty, THEN we don't want to inadvertently rm -rf the _host_ /root dir,
    # hence the extra -i flag.
    sudo rm -irf "${LUPROOT}"/root
    sudo groupadd -g 0 -r -R "${LUPROOT}" root
    sudo useradd -c Charlie -r -m -d /root/ -u 0 -g 0 -R "${LUPROOT}" root || die "${MSG}"

    MSG="Re-setting password for root user in ${LUPROOT} ..."
    printInfo "${MSG}"
    ${chroot} passwd -d root || die "${MSG}"
    echo -n "I am (g)"
    ${chroot} whoami || die "${MSG}"

    MSG="Listing pisi related directory permissions ..."
    printInfo "${MSG}"
    ${chroot} ls -la /var/cache/pisi /var/run/lock/subsys/pisi

    MSG="Checking for network connectivity from within the systemd-nspawn chroot ..."
    printInfo "${MSG}"
    ${chroot} ip addr
    ${chroot} ip route
    ${chroot} nslookup packages.teknoanka.com

    MSG="Forcing usysconf run inside the chroot (to enable pisi to use https:// URIs) ..."
    printInfo "${MSG}"
    ${chroot} usysconf run -f

    MSG="Disabling temporary Local repo within the systemd-nspawn chroot ..."
    printInfo "${MSG}"
    ${chroot} ${pisi_bin} dr Local
    ${chroot} ${pisi_bin} lr
}

buildStartChrootScript() {
    cat <<EOF > start_chroot.sh
#!/usr/bin/env bash
#
# Script for chroot-ing into ${LUPROOT}

source shared_functions.bash

mount_bind_mounts() {
    # automagically go out of scope
    local mkdir='sudo mkdir -pv'
    local mount='sudo mount -v'

    MSG="Setting up virtual kernel file systems ..."
    printInfo "\${MSG}"
    # --make-rslave prevents these mounts from affecting the parent dirs
    \${mount} -t proc proc "${LUPROOT}"/proc
    \${mount} -t sysfs /sys "${LUPROOT}"/sys --make-rslave
    \${mount} -o rbind /dev "${LUPROOT}"/dev --make-rslave
    \${mount} -t tmpfs tmpfs "${LUPROOT}"/run

    # needs to exist in any case
    \${mkdir} "${LUPROOT}${LOCALREPO}"
    if [[ -d "${LOCALREPO}" ]]; then
        MSG="Bind-mounting the host ${LOCALREPO} directory ..."
        printInfo "\${MSG}"
        \${mount} --bind "${LOCALREPO}" "${LUPROOT}${LOCALREPO}"
    fi

    # needs to exist in any case
    \${mkdir} "${LUPROOT}${PISICACHE}"
    if [[ -d "${PISICACHE}" ]]; then
        MSG="Bind-mounting the host ${PISICACHE} directory ..."
        printInfo "\${MSG}"
        \${mount} --bind "${PISICACHE}" "${LUPROOT}${PISICACHE}"
    fi
}

unmount_bind_mounts() {
    # automagically goes out of scope
    local umount='sudo umount -Rfv'

    if [[ -d "${LUPROOT}/${PISICACHE}" ]]; then
        MSG="Unmounting existing ${LUPROOT}${PISICACHE} bind-mount ..."
        printInfo "\${MSG}"
        \${umount} "${LUPROOT}${PISICACHE}"
    fi

    if [[ -d "${LUPROOT}/${LOCALREPO}" ]]; then
        MSG="Unmounting existing ${LUPROOT}${LOCALREPO} bind-mount ..."
        printInfo "\${MSG}"
        \${umount} "${LUPROOT}${LOCALREPO}"
    fi

    MSG="Unmounting existing ${LUPROOT} virtual kernel file systems ..."
    printInfo "\${MSG}"
    for d in run dev sys proc; do
        \${umount} "${LUPROOT}"/\${d}
        # avoid the kernel tripping itself up and failing to recursively unmount
        sleep 1
    done
}

# it sucks to leave mounts up in the chroot 
trap unmount_bind_mounts EXIT

MSG="Mounting virtual kernel filesystems in ${LUPROOT} ..."
printInfo "\${MSG}"
mount_bind_mounts || die "\${MSG}"

MSG="Chrooting into ${LUPROOT} ..."
printInfo "\${MSG}"
# ensure that usysconf run -f is run before we exec the login shell for convenience
sudo -E TERM="${TERM}" $(command -v chroot) "${LUPROOT}" /usr/bin/bash -l -c "usysconf run -f && exec /usr/bin/bash -l" || die "${MSG}"

# Should no longer be necessary due to the trap EXIT usage
#MSG="Unmounting virtual kernel filesystems from ${LUPROOT} ..."
#printInfo "${MSG}"
#unmount_bind_mounts || die "${MSG}"

EOF
# be nice to the user
chmod -c a+x start_chroot.sh
}

buildStartSystemdNspawnScript() {
    cat <<EOF > start_systemd_nspawn.sh
#!/usr/bin/env bash
#
# Script for booting into ${LUPROOT} via systemd-nspawn

source shared_functions.bash

BOOT_CMD="sudo $(command -v systemd-nspawn) -D ${LUPROOT} --boot"

mount_bind_mounts() {
    # automagically go out of scope
    local mkdir='sudo mkdir -pv'
    local mount='sudo mount -v'

    # needs to exist in any case
    \${mkdir} "${LUPROOT}${LOCALREPO}"
    if [[ -d "${LOCALREPO}" ]]; then
        MSG="Bind-mounting the host ${LOCALREPO} directory ..."
        printInfo "\${MSG}"
        BOOT_CMD+=" --bind ${LOCALREPO}"
    fi

    # needs to exist in any case
    \${mkdir} "${LUPROOT}${PISICACHE}"
    if [[ -d "${PISICACHE}" ]]; then
        MSG="Bind-mounting the host ${PISICACHE} directory ..."
        printInfo "\${MSG}"
        BOOT_CMD+=" --bind ${PISICACHE}"
    fi
}

MSG="Checking whether we can bind-mount useful host directories ..."
printInfo "\${MSG}"
mount_bind_mounts || die "\${MSG}"

MSG="Booting into ${LUPROOT} using systemd-nspawn ..."
printInfo "\${MSG}"
# Note that the bind mounts get auto-unmounted by systemd-nspawn on poweroff
exec \${BOOT_CMD} || die "\${MSG}"

EOF
# be nice to the user
chmod -c a+x start_systemd_nspawn.sh
}

showStartMessage() {
    cat <<EOF

Building '${EDITION}' chroot from the -unstable repo in the output folder:

  ${LUPROOT}

succeeded.

You can now chroot into the minimal LupuS install folder above by executing one of:

  ./start_chroot.sh         # normal chroot
  ./start_systemd_nspawn.sh # systemd-nspawn chroot on steroids

Login: By default, the only enabled user is 'root' with no password.

EOF
}

# it sucks to leave mounts up in the chroot
trap unmountBindMounts EXIT

time {

checkPrereqs

# strip out comment lines + empty lines. Yields a space separated string.
# (the string deliberately includes duplicates to keep them visible)
PACKAGES="$(sed -e '/^#.*$/d' -e '/^$/d' chroot_pkglist.txt| sort| tr '\n' ' ')"

echo "PACKAGES: ${PACKAGES}"
#die "Test of PACKAGES."

basicSetup

buildStartChrootScript

buildStartSystemdNspawnScript

showStartMessage

} # end of `time` call
