#!/bin/sh
# Linux Deploy Component
# (c) Anton Skshidlevsky <meefik@gmail.com>, GPLv3

yum_install()
{
    local packages="$@"
    [ -n "${packages}" ] || return 1
    (set -e
        chroot_exec yum install ${packages} --nogpgcheck --skip-broken -y
        chroot_exec yum clean all
    exit 0) 1>&3 2>&3
    return $?
}

yum_groupinstall()
{
    local groupname="$@"
    [ -n "${groupname}" ] || return 1
    (set -e
        chroot_exec yum groupinstall ${groupname} --nogpgcheck --skip-broken -y
        chroot_exec yum clean all
    exit 0) 1>&3 2>&3
    return $?
}

do_install()
{
    is_archive "${SOURCE_PATH}" && return 0

    msg ":: Installing ${COMPONENT} ... "

    local basic_packages="filesystem audit-libs basesystem bash bzip2-libs ca-certificates chkconfig coreutils cpio cracklib cracklib-dicts crypto-policies cryptsetup-libs curl cyrus-sasl-lib dbus dbus-libs device-mapper device-mapper-libs diffutils elfutils-libelf elfutils-libs expat fedora-release fedora-repos file-libs fipscheck fipscheck-lib gamin gawk gdbm glib2 glibc glibc-common gmp gnupg2 gnutls gpgme grep gzip hwdata info keyutils-libs kmod kmod-libs krb5-libs libacl libarchive libassuan libattr libblkid libcap libcap-ng libcom_err libcurl libdb libdb4 libdb-utils libffi libgcc libgcrypt libgpg-error libidn libmetalink libmicrohttpd libmount libpwquality libseccomp libselinux libselinux-utils libsemanage libsepol libsmartcols libssh2 libstdc++ libtasn1 libuser libutempter libuuid libverto libxml2 lua lzo man-pages ncurses ncurses-base ncurses-libs nettle nspr nss nss-myhostname nss-softokn nss-softokn-freebl nss-sysinit nss-tools nss-util openldap openssl-libs p11-kit p11-kit-trust pam pcre pinentry pkgconfig policycoreutils popt pth pygpgme pyliblzma python python-chardet python-iniparse python-kitchen python-libs python-pycurl python-six python-urlgrabber pyxattr qrencode-libs readline rootfiles rpm rpm-build-libs rpm-libs rpm-plugin-selinux rpm-python sed selinux-policy setup shadow-utils shared-mime-info sqlite sudo systemd systemd-libs systemd-sysv tcp_wrappers-libs trousers tzdata ustr util-linux vim-minimal xz-libs yum yum-metadata-parser yum-utils which zlib"

    if [ "$(get_platform ${ARCH})" = "intel" -o "${ARCH}" != "aarch64" -a "${SUITE}" -ge 20 ]
    then local repo="${SOURCE_PATH%/}/fedora/linux/releases/${SUITE}/Everything/${ARCH}/os"
    else local repo="${SOURCE_PATH%/}/fedora-secondary/releases/${SUITE}/Everything/${ARCH}/os"
    fi

    msg "Repository: ${repo}"

    msg -n "Preparing for deployment ... "
    tar xzf "${COMPONENT_DIR}/filesystem.tgz" -C "${CHROOT_DIR}"
    is_ok "fail" "done" || return 1

    msg -n "Retrieving packages list ... "
    local pkg_list="${CHROOT_DIR}/tmp/packages.list"
    (set -e
        repodata=$(wget -q -O - "${repo}/repodata/repomd.xml" | sed -n '/<location / s/^.*<location [^>]*href="\([^\"]*\-primary\.xml\.gz\)".*$/\1/p')
        [ -z "${repodata}" ] && exit 1
        wget -q -O - "${repo}/${repodata}" | gzip -dc | sed -n '/<location / s/^.*<location [^>]*href="\([^\"]*\)".*$/\1/p' > "${pkg_list}"
    exit 0)
    is_ok "fail" "done" || return 1

    msg "Retrieving base packages: "
    local package i pkg_url pkg_file
    for package in ${basic_packages}; do
        msg -n "${package} ... "
        pkg_url=$(grep -m1 -e "^.*/${package}-[0-9][0-9\.\-].*\.rpm$" "${pkg_list}")
        test "${pkg_url}"; is_ok "skip" || continue
        pkg_file="${pkg_url##*/}"
        # download
        for i in 1 2 3
        do
            wget -q -c -O "${CHROOT_DIR}/tmp/${pkg_file}" "${repo}/${pkg_url}" && break
            sleep 30s
        done
        [ "${package}" = "filesystem" ] && { msg "done"; continue; }
        # unpack
        (cd "${CHROOT_DIR}"; rpm2cpio "./tmp/${pkg_file}" | cpio -idmu)
        is_ok "fail" "done" || return 1
    done

    component_exec core/emulator

    msg "Installing base packages: "
    chroot_exec /bin/rpm -iv --excludepath / --force --nosignature --nodeps --justdb /tmp/*.rpm 1>&3 2>&3
    is_ok "fail" "done" || return 1

    msg -n "Clearing cache ... "
    rm -rf "${CHROOT_DIR}"/tmp/*
    is_ok "skip" "done"

    component_exec core/dns core/mtab core/repository

    msg "Installing minimal environment: "
    yum_groupinstall minimal-environment --exclude filesystem,openssh-server
    is_ok || return 1

    return 0
}
