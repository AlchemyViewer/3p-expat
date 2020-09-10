#!/usr/bin/env bash

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about undefined vars
set -u

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$(dirname "$0")"
STAGING_DIR="$(pwd)"

# load autbuild provided shell functions and variables
source_environment_tempfile="$STAGING_DIR/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

EXPAT_SOURCE_DIR=expat
EXPAT_VERSION="$(sed -n -E "s/^ *PACKAGE_VERSION *= *'(.*)' *\$/\1/p" \
                     "$top/$EXPAT_SOURCE_DIR/configure")"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${EXPAT_VERSION}.${build}" > "${STAGING_DIR}/VERSION.txt"

pushd "$top/$EXPAT_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            load_vsvars

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                archflags="/arch:SSE2"
            else
                archflags=""
            fi

            mkdir -p "$STAGING_DIR/lib/debug"
            mkdir -p "$STAGING_DIR/lib/release"

            mkdir -p "build_debug"
            pushd "build_debug"
                # Invoke cmake and use as official build
                cmake -E env CFLAGS="$archflags" CXXFLAGS="$archflags /std:c++17 /permissive-" LDFLAGS="/DEBUG:FULL" \
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DEXPAT_SHARED_LIBS=ON -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF

                cmake --build . --config Debug --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    cp Debug/libexpatd.dll "tests/Debug/"
                    ctest -C Debug
                fi

                cp Debug/libexpatd.{lib,dll,exp,pdb} "$STAGING_DIR/lib/debug/"
            popd

            mkdir -p "build_release"
            pushd "build_release"
                # Invoke cmake and use as official build
                cmake -E env CFLAGS="$archflags /Ob3 /GL /Gy /Zi" CXXFLAGS="$archflags /Ob3 /GL /Gy /Zi /std:c++17 /permissive-" LDFLAGS="/LTCG /OPT:REF /OPT:ICF /DEBUG:FULL" \
                cmake -G "$AUTOBUILD_WIN_CMAKE_GEN" -A "$AUTOBUILD_WIN_VSPLATFORM" .. -DEXPAT_SHARED_LIBS=ON -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF

                cmake --build . --config Release --clean-first

                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    cp Release/libexpat.dll "tests/Release/"
                    ctest -C Release
                fi

                cp Release/libexpat.{lib,dll,exp,pdb} "$STAGING_DIR/lib/release/"
            popd

            INCLUDE_DIR="$STAGING_DIR/include/expat"
            mkdir -p "$INCLUDE_DIR"
            cp lib/expat.h "$INCLUDE_DIR"
            cp lib/expat_external.h "$INCLUDE_DIR"
        ;;
        darwin*)
            opts="-arch $AUTOBUILD_CONFIGURE_ARCH $LL_BUILD_RELEASE"
            export CFLAGS="$opts"
            export CXXFLAGS="$opts"
            export LDFLAGS="$opts"
            export CC="clang"
            export PREFIX="$STAGING_DIR"
            if ! ./configure --prefix=$PREFIX
            then
                cat config.log >&2
                exit 1
            fi
            make
            make install

            mv "$PREFIX/lib" "$PREFIX/release"
            mkdir -p "$PREFIX/lib"
            mv "$PREFIX/release" "$PREFIX/lib"
            pushd "$PREFIX/lib/release"
            fix_dylib_id "libexpat.dylib"
            popd

            mv "$PREFIX/include" "$PREFIX/expat"
            mkdir -p "$PREFIX/include"
            mv "$PREFIX/expat" "$PREFIX/include"
        ;;
        linux*)
            PREFIX="$STAGING_DIR"
            CFLAGS="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE" ./configure --prefix="$PREFIX" --libdir="$PREFIX/lib/release"
            make
            make install

            mv "$PREFIX/include" "$PREFIX/expat"
            mkdir -p "$PREFIX/include"
            mv "$PREFIX/expat" "$PREFIX/include"
        ;;
    esac

    mkdir -p "$STAGING_DIR/LICENSES"
    cp "COPYING" "$STAGING_DIR/LICENSES/expat.txt"
popd
