#!/usr/bin/env bash

TOP="$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
exec 4>&1; export BASH_XTRACEFD=4; set -x
# make errors fatal
set -e
# complain about unset env variables
set -u

PROJECT="libndofdev"
# If there's a version number embedded in the source code somewhere, we
# haven't yet found it.
VERSION="0.1.0"
SOURCE_DIR="$PROJECT"

if [ -z "$AUTOBUILD" ] ; then 
    exit 1
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

echo "${VERSION}" > "${stage}/VERSION.txt"

case "$AUTOBUILD_PLATFORM" in
    windows*)
        pushd "$TOP/$SOURCE_DIR/src"
            load_vsvars
            msbuild.exe $(cygpath -w "$PROJECT.sln") /p:Configuration=Debug /p:Platform=$AUTOBUILD_WIN_VSPLATFORM
            msbuild.exe $(cygpath -w "$PROJECT.sln") /p:Configuration=Release /p:Platform=$AUTOBUILD_WIN_VSPLATFORM
    
            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"

            if [ "$AUTOBUILD_ADDRSIZE" = 32 ]
            then
                cp Debug/libndofdev.{lib,pdb} $stage/lib/debug/
                cp Release/libndofdev.{lib,pdb} $stage/lib/release/
            else
                cp x64/Debug/libndofdev.{lib,pdb} $stage/lib/debug/
                cp x64/Release/libndofdev.{lib,pdb} $stage/lib/release/
            fi
        popd
    ;;
    darwin*)
        # Setup build flags
        ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=11.0 -msse4.2"
        ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=11.0"
        DEBUG_COMMON_FLAGS="-O0 -g -fPIC -DPIC -DTARGET_OS_MAC=1"
        RELEASE_COMMON_FLAGS="-O3 -g -fPIC -DPIC -fstack-protector-strong -DTARGET_OS_MAC=1"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"
        DEBUG_LDFLAGS="-Wl,-headerpad_max_install_names"
        RELEASE_LDFLAGS="-Wl,-headerpad_max_install_names"

        mkdir -p "$stage/lib/debug/"
        mkdir -p "$stage/lib/release/"

        # x86 Deploy Target
        export MACOSX_DEPLOYMENT_TARGET=11.0

        mkdir -p "build_release_x86"
        pushd "build_release_x86"
            CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_X86 $RELEASE_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_X86 $RELEASE_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -G Ninja -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Release
        popd

        mkdir -p "build_release_arm64"
        pushd "build_release_arm64"
            CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -G Ninja -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Release
        popd

        # create fat libs
        lipo -create build_release_x86/src/libndofdev.dylib build_release_arm64/src/libndofdev.dylib -output ${stage}/lib/release/libndofdev.dylib

        # create debug bundles
        pushd "${stage}/lib/release"
            install_name_tool -id "@rpath/libndofdev.dylib" "libndofdev.dylib"
            dsymutil libndofdev.dylib
            strip -x -S libndofdev.dylib
        popd

        if [ -n "${AUTOBUILD_KEYCHAIN_PATH:=""}" -a -n "${AUTOBUILD_KEYCHAIN_ID:=""}" ]; then
            for dylib in $stage/lib/*/libndofdev*.dylib;
            do
                if [ -f "$dylib" ]; then
                    codesign --keychain $AUTOBUILD_KEYCHAIN_PATH --sign "$AUTOBUILD_KEYCHAIN_ID" --force --timestamp "$dylib" || true
                fi
            done
        else
            echo "Code signing not configured; skipping codesign."
        fi
    ;;
    linux*)
        # Given forking and future development work, it seems unwise to
        # hardcode the actual URL of the current project's libndofdef-linux
        # repository in this message. Try to determine the URL of this
        # libndofdev repository and prepend "open-" as a suggestion.
        echo "Linux libndofdev is in a separate open-libndofdev bitbucket repository \
-- try $(hg paths default | sed 's/libndofdev/open-&/')" 1>&2 ; exit 1
    ;;
esac

mkdir -p "$stage/include/"
cp "$TOP/$SOURCE_DIR/src/ndofdev_external.h" "$stage/include/"
mkdir -p "$stage/LICENSES"
cp -v "$TOP/$SOURCE_DIR/COPYING"  "$stage/LICENSES/$PROJECT.txt"
