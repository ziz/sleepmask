#!/usr/bin/env bash

cd ..

die() {
    echo "$*"
    exit 1
}

remglk() {
    (
        echo "Rebuilding remglk..."
        cd remglk
        make -s
    )
}
fizmo() {
    (
        echo "Rebuilding fizmo..."
        cd fizmo-rem
        find . -type f -name fizmo-glktermw -delete
        make -s fizmo-glktermw
        return $?
    )
}

glulxe() {
    (
        echo "Rebuilding glulxe..."
        cd glulxe-047-rem
        rm -f glulxe
        make -s
        return $?
    )
}

tads() {
    (
        echo "Rebuilding TADS..."
        cd floyd-tads-rem
        rm -f build/linux.release/tads/libremblk.a build/linux.release/tads/tadsr
        cp ../remglk/libremglk.a build/linux.release/tads/
        (
            cd tads
            jam -d 0 || return 1
        )
        
        rm -f build/linux.debug/tads/libremblk.a build/linux.debug/tads/tadsr
        cp ../remglk/libremglk.a build/linux.debug/tads/
        (
            cd tads
            BUILD=DEBUG jam -d 0 || return 1
        )
    )
}

hugo() {
    (
        echo "Rebuilding hugo..."
        cd hugo-rem/glk
        rm heglk
        make -s
        return $?
    )
}
remglk || die "Error building remglk!"
fizmo || die "Error building fizmo!"
glulxe || die "Error building glulxe!"
tads || die "Error building TADS!"
hugo || die "Error building hugo!"

echo "All done."
