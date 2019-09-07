#!/bin/bash

(
    cd scripts
    (
        cd gmp
        ./build.sh
    )

    (
        cd mpfr
        ./build.sh
    )

    (
        cd mpc
        ./build.sh
    )
    (
        cd isl
        ./build.sh
    )
    (
        cd binutils-gdb
        ./build.sh
    )
)
