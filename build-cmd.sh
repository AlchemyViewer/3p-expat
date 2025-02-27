#!/usr/bin/env bash

set -eu

if [ -z "$AUTOBUILD" ] ; then
    exit 1
fi

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

top="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
stage="$top/stage"
build="$top/build"
src="$top/libexpat/expat"

# load autbuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd apply_patch
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

pushd "$top"
 apply_patch "$top/patches/update-cmake-version.patch" "libexpat"
popd

mkdir -p $top
mkdir -p $build
mkdir -p $stage/LICENSES

cmake_flags="${CMAKE_FLAGS:--DEXPAT_SHARED_LIBS=OFF -DEXPAT_BUILD_TOOLS=OFF -DEXPAT_BUILD_EXAMPLES=OFF -DCMAKE_BUILD_TYPE=Release}"

pushd $build
    case "$AUTOBUILD_PLATFORM" in
        windows*)
            set +x
            load_vsvars
            set -x

            mkdir -p "debug"
            pushd "debug"
                opts="$(replace_switch /Zi /Z7 $LL_BUILD_DEBUG)"
                plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                cmake $(cygpath -w $src) -G"Ninja Multi-Config" $cmake_flags \
                        -DCMAKE_INSTALL_PREFIX=$(cygpath -w $stage) \
                        -DCMAKE_C_FLAGS="$plainopts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                        -DEXPAT_MSVC_STATIC_CRT=OFF

                cmake --build . --config Debug --parallel $AUTOBUILD_CPU_COUNT

                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Debug --parallel $AUTOBUILD_CPU_COUNT
                fi

                cmake --install . --config Debug

                mkdir -p "$stage/lib/debug"
                mv $stage/lib/libexpatdMD.lib "$stage/lib/debug/libexpatd.lib"
            popd

            mkdir -p "release"
            pushd "release"
                opts="$(replace_switch /Zi /Z7 $LL_BUILD_RELEASE)"
                plainopts="$(remove_switch /GR $(remove_cxxstd $opts))"

                cmake $(cygpath -w $src) -G"Ninja Multi-Config" $cmake_flags \
                        -DCMAKE_INSTALL_PREFIX=$(cygpath -w $stage) \
                        -DCMAKE_C_FLAGS="$plainopts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_MSVC_DEBUG_INFORMATION_FORMAT="Embedded" \
                        -DEXPAT_MSVC_STATIC_CRT=OFF

                cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT

                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                fi

                cmake --install . --config Release

                mkdir -p "$stage/lib/release"
                mv $stage/lib/libexpatMD.lib "$stage/lib/release/libexpat.lib"
            popd
        ;;
        darwin*)
            export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

            for arch in x86_64 arm64 ; do
                ARCH_ARGS="-arch $arch"
                opts="${TARGET_OPTS:-$ARCH_ARGS $LL_BUILD_RELEASE}"
                cc_opts="$(remove_cxxstd $opts)"
                ld_opts="$ARCH_ARGS"

                mkdir -p "build_$arch"
                pushd "build_$arch"
                    CFLAGS="$cc_opts" \
                    CXXFLAGS="$opts" \
                    LDFLAGS="$ld_opts" \
                    cmake $src -G "Ninja Multi-Config" $cmake_flags \
                        -DCMAKE_C_FLAGS="$cc_opts" \
                        -DCMAKE_CXX_FLAGS="$opts" \
                        -DCMAKE_BUILD_TYPE=Release \
                        -DCMAKE_INSTALL_PREFIX="$stage" \
                        -DCMAKE_INSTALL_LIBDIR="$stage/lib/release/$arch" \
                        -DCMAKE_OSX_ARCHITECTURES:STRING="$arch" \
                        -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET}

                    cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT
                    cmake --install . --config Release

                    if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                        ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
                    fi
                popd
            done

            # Create universal library
            lipo -create -output "$stage/lib/release/libexpat.a" "$stage/lib/release/x86_64/libexpat.a" "$stage/lib/release/arm64/libexpat.a"
        ;;
        linux*)
            opts="-m$AUTOBUILD_ADDRSIZE $LL_BUILD_RELEASE"
            plainopts="$(remove_cxxstd $opts)"

            cmake $src -G "Ninja" $cmake_flags -DCMAKE_INSTALL_PREFIX=$stage -DCMAKE_C_FLAGS="$plainopts" -DCMAKE_CXX_FLAGS="$opts" -DCMAKE_BUILD_TYPE=Release
            cmake --build . --config Release --parallel $AUTOBUILD_CPU_COUNT

            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                ctest -C Release --parallel $AUTOBUILD_CPU_COUNT
            fi

            cmake --install . --config Release

            mkdir -p "$stage/lib/release"
            mv $stage/lib/*.a "$stage/lib/release/"
        ;;
    esac

popd

mkdir -p "$stage/LICENSES"
mkdir -p "$stage/include/expat"
mv $stage/include/*.h "$stage/include/expat/"
cp "$src/COPYING" "$stage/LICENSES/expat.txt"
