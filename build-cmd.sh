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
            build_sln "$PROJECT.sln" "Debug|$AUTOBUILD_WIN_VSPLATFORM"
            build_sln "$PROJECT.sln" "Release|$AUTOBUILD_WIN_VSPLATFORM"
    
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
        # Setup osx sdk platform
        SDKNAME="macosx"
        export SDKROOT=$(xcodebuild -version -sdk ${SDKNAME} Path)
        export MACOSX_DEPLOYMENT_TARGET=10.15

        # Setup build flags
        ARCH_FLAGS="-arch x86_64"
        SDK_FLAGS="-mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"
        DEBUG_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Og -g -msse4.2 -fPIC -DPIC -DTARGET_OS_MAC"
        RELEASE_COMMON_FLAGS="$ARCH_FLAGS $SDK_FLAGS -Ofast -ffast-math -flto -g -msse4.2 -fPIC -DPIC -fstack-protector-strong -DTARGET_OS_MAC"
        DEBUG_CFLAGS="$DEBUG_COMMON_FLAGS"
        RELEASE_CFLAGS="$RELEASE_COMMON_FLAGS"
        DEBUG_CXXFLAGS="$DEBUG_COMMON_FLAGS -std=c++17"
        RELEASE_CXXFLAGS="$RELEASE_COMMON_FLAGS -std=c++17"
        DEBUG_CPPFLAGS="-DPIC"
        RELEASE_CPPFLAGS="-DPIC"
        DEBUG_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"
        RELEASE_LDFLAGS="$ARCH_FLAGS $SDK_FLAGS -Wl,-headerpad_max_install_names -Wl,-macos_version_min,$MACOSX_DEPLOYMENT_TARGET"

        mkdir -p "$stage/lib/debug/"
        mkdir -p "$stage/lib/release/"

        mkdir -p "build_debug"
        pushd "build_debug"
            CFLAGS="$DEBUG_CFLAGS" \
            CXXFLAGS="$DEBUG_CXXFLAGS" \
            CPPFLAGS="$DEBUG_CPPFLAGS" \
            LDFLAGS="$DEBUG_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON -DBUILD_CODEC:BOOL=ON \
                -DCMAKE_C_FLAGS="$DEBUG_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$DEBUG_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Debug

            cp -a src/Debug/libndofdev.dylib* "${stage}/lib/debug/"
        popd

        mkdir -p "build_release"
        pushd "build_release"
            CFLAGS="$RELEASE_CFLAGS" \
            CXXFLAGS="$RELEASE_CXXFLAGS" \
            CPPFLAGS="$RELEASE_CPPFLAGS" \
            LDFLAGS="$RELEASE_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON -DBUILD_CODEC:BOOL=ON \
                -DCMAKE_C_FLAGS="$RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$RELEASE_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_X86_VECTOR_INSTRUCTIONS=sse4.2 \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=x86_64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Release

            cp -a src/Release/libndofdev.dylib* "${stage}/lib/release/"
        popd

        pushd "${stage}/lib/debug"
            install_name_tool -id "@rpath/libndofdev.dylib" "libndofdev.dylib"
            strip -x -S libndofdev.dylib
        popd

        pushd "${stage}/lib/release"
            install_name_tool -id "@rpath/libndofdev.dylib" "libndofdev.dylib"
            strip -x -S libndofdev.dylib
        popd
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
