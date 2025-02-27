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

if [[ "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" ]] ; then
    autobuild="$(cygpath -u $AUTOBUILD)"
else
    autobuild="$AUTOBUILD"
fi

stage="$(pwd)"

# load autobuild provided shell functions and variables
source_environment_tempfile="$stage/source_environment.sh"
"$autobuild" source_environment > "$source_environment_tempfile"
. "$source_environment_tempfile"

# remove_cxxstd
source "$(dirname "$AUTOBUILD_VARIABLES_FILE")/functions"

build=${AUTOBUILD_BUILD_ID:=0}
echo "${VERSION}.${build}" > "${stage}/VERSION.txt"

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
        export MACOSX_DEPLOYMENT_TARGET="$LL_BUILD_DARWIN_DEPLOY_TARGET"

        opts="-DTARGET_OS_MAC $LL_BUILD_RELEASE"
        cmake ../libndofdev -DCMAKE_CXX_FLAGS="$opts" \
            -DCMAKE_C_FLAGS="$(remove_cxxstd $opts)" \
            -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
            -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
            -DCMAKE_MACOSX_RPATH=YES
        make -j$(nproc)
        mkdir -p "$stage/lib/release"
        cp "src/libndofdev.dylib" "$stage/lib/release"
        pushd "$stage/lib/release/"
            dsymutil libndofdev.dylib
            strip -x -S libndofdev.dylib
        popd
    ;;
esac

mkdir -p "$stage/include/"
cp "$TOP/$SOURCE_DIR/src/ndofdev_external.h" "$stage/include/"
mkdir -p "$stage/LICENSES"
cp -v "$TOP/$SOURCE_DIR/COPYING"  "$stage/LICENSES/$PROJECT.txt"
