#!/bin/bash

# fail at the first error
set -e
set -o pipefail

VERSION=7.4.0
GLIBC_VERSION=2.12.2
LINUX_VERSION=2.6.32.27
LINUX_MAJOR_VERSION=2.6
export AR_FLAGS=cqD

cd -P "$( dirname "$0" )"
source ${PWD}/../../env/env.sh

LIBPREFIX=${PWD}/../../install-lib/
PACKPREFIX=${PWD}/../../install-package/
PREFIX=${PWD}/../../prefix

[ -e gcc-${VERSION}.tar.xz ] || wget https://ftp.gnu.org/gnu/gcc/gcc-${VERSION}/gcc-${VERSION}.tar.xz
tar xfv gcc-${VERSION}.tar.xz

[ -e glibc-${GLIBC_VERSION}.tar.xz ] || wget https://ftp.gnu.org/gnu/libc/glibc-${GLIBC_VERSION}.tar.xz
tar xfv glibc-${GLIBC_VERSION}.tar.xz

[ -e linux-${LINUX_VERSION}.tar.xz ] || wget https://mirrors.edge.kernel.org/pub/linux/kernel/v${LINUX_MAJOR_VERSION}/linux-${LINUX_VERSION}.tar.xz
tar xfv linux-${LINUX_VERSION}.tar.xz

[ -e glibc-patched ] && rm -R glibc-patched
cp -R glibc-${GLIBC_VERSION} glibc-patched
# Allow modern gmake
sed -i 's/3\.79\* | 3\.\[89\]\*)/3\.79\* | 3\.\[89\]\* | 4\.\*)/g' glibc-patched/configure
# Allow modern gcc
sed -i 's/3\.4\* | 4\.\[0-9\]\* )/3\.4\* | \[4-9\].* )/g' glibc-patched/configure
# Give obstack a value
# https://www.lordaro.co.uk/posts/2018-08-26-compiling-glibc.html
sed -i -e 's/struct obstack \*_obstack_compat;/struct obstack \*_obstack_compat = NULL;/g' glibc-patched/malloc/obstack.c

mkdir -p gcc-build-1
(
    cd gcc-build-1
    export PATH=${PACKPREFIX}/binutils/bin/:${PATH}
    ../gcc-${VERSION}/configure --target=x86_64-astraeus-linux-gnu --disable-multilib --prefix=${PREFIX}/usr/ --enable-languages=c,c++ --with-system-zlib --with-gnu-ld --with-gnu-as --without-headers --with-gmp=${LIBPREFIX}/gmp --with-mpc=${LIBPREFIX}/mpc --with-mpfr=${LIBPREFIX}/mpfr --with-isl=${LIBPREFIX}/isl
    make all-gcc ${MAKEOPTS}
    make install-gcc
)

(
    cd linux-${LINUX_VERSION}
    make ARCH=x86 INSTALL_HDR_PATH=${LIBPREFIX}/linux/ headers_install
)

mkdir -p glibc-build
(
    cd glibc-build
    export PATH=${PACKPREFIX}/binutils/bin/:${PREFIX}/usr/bin:${PATH}
    ../glibc-patched/configure --build=x86_64-unknown-linux-gnu --host=x86_64-astraeus-linux-gnu --disable-multilib --prefix=/usr/ --with-headers=${LIBPREFIX}/linux/include/ --disable-nls libc_cv_forced_unwind=yes libc_cv_c_cleanup=yes MAKEINFO=false
    make install-bootstrap-headers=yes install-headers install_root=${PREFIX}
    make csu/subdir_lib

    mkdir -p ${PREFIX}/usr/x86_64-astraeus-linux-gnu/{lib,include/gnu/}

    install csu/crt1.o csu/crti.o csu/crtn.o ${PREFIX}/usr/x86_64-astraeus-linux-gnu/lib
    install bits/* ${PREFIX}/usr/include/bits/
    x86_64-astraeus-linux-gnu-gcc -nostdlib -nostartfiles -shared -x c /dev/null -o ${PREFIX}/usr/lib/libc.so
    touch ${PREFIX}/usr/x86_64-astraeus-linux-gnu/include/gnu/stubs.h
)

mkdir -p gcc-build-2
(
    cd gcc-build-2
    export CPATH=${CPATH}:${LIBPREFIX}/linux/include/
    export PATH=${PACKPREFIX}/binutils/bin/:${PREFIX}/usr/bin/:${PATH}
    ../gcc-${VERSION}/configure --target=x86_64-astraeus-linux-gnu --disable-multilib --prefix=${PREFIX}/usr/ --enable-languages=c,c++ --with-system-zlib --with-gnu-ld --with-gnu-as --without-headers --with-gmp=${LIBPREFIX}/gmp --with-mpc=${LIBPREFIX}/mpc --with-mpfr=${LIBPREFIX}/mpfr --with-isl=${LIBPREFIX}/isl --with-build-sysroot=${PREFIX}/ --with-sysroot=${PREFIX}/ --disable-libsanitizer --enable-libgomp --with-pic
    make all-gcc all-target-libgcc
    make install-gcc install-target-libgcc
)

(
    cd glibc-build

    export PATH=${PREFIX}/usr/bin/:${PATH}
    make
    make install install_root=${PREFIX}
)

(
    cd gcc-build-2
    export CPATH=${CPATH}:${LIBPREFIX}/linux/include/
    export PATH=${PACKPREFIX}/binutils/bin/:${PREFIX}/usr/bin/:${PATH}
    make
    make install
)

(
    cd ${PREFIX}/usr
    strip bin/x86_64-astraeus-linux-gnu-strip libexec/gcc/x86_64-astraeus-linux-gnu/${VERSION}/{cc1,cc1plus,collect2,lto1,lto-wrapper,liblto_plugin.so,liblto_plugin.so.0,liblto_plugin.so.0.0.0}
    rm -R libexec/gcc/x86_64-astraeus-linux-gnu/${VERSION}/{liblto_plugin.la,install-tools} lib/gcc/x86_64-astraeus-linux-gnu/${VERSION}/install-tools/ lib64/gconv/ share/
    sed -i 's: /: =/:g' lib64/libc.so lib64/libpthread.so
)
