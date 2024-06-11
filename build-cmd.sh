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
        C_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CFLAGS"
        C_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CFLAGS"
        CXX_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_CXXFLAGS"
        CXX_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_CXXFLAGS"
        LINK_OPTS_X86="-arch x86_64 $LL_BUILD_RELEASE_LINKER"
        LINK_OPTS_ARM64="-arch arm64 $LL_BUILD_RELEASE_LINKER"

        # deploy target
        export MACOSX_DEPLOYMENT_TARGET=${LL_BUILD_DARWIN_BASE_DEPLOY_TARGET}

        mkdir -p "$stage/lib/debug/"
        mkdir -p "$stage/lib/release/"

        mkdir -p "build_release_x86"
        pushd "build_release_x86"
            CFLAGS="$C_OPTS_X86" \
            CXXFLAGS="$CXX_OPTS_X86" \
            LDFLAGS="$LINK_OPTS_X86" \
            cmake $TOP/../$SOURCE_DIR -G Ninja -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS="$C_OPTS_X86" \
                -DCMAKE_CXX_FLAGS="$CXX_OPTS_X86" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Release
        popd

        mkdir -p "build_release_arm64"
        pushd "build_release_arm64"
            CFLAGS="$C_OPTS_ARM64" \
            CXXFLAGS="$CXX_OPTS_ARM64" \
            LDFLAGS="$LINK_OPTS_ARM64" \
            cmake $TOP/../$SOURCE_DIR -G Ninja -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_BUILD_TYPE=Release \
                -DCMAKE_C_FLAGS="$C_OPTS_ARM64" \
                -DCMAKE_CXX_FLAGS="$CXX_OPTS_ARM64" \
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
