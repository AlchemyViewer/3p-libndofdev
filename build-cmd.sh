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

        # Deploy Targets
        X86_DEPLOY=10.15
        ARM64_DEPLOY=11.0

        # Setup build flags
        ARCH_FLAGS_X86="-arch x86_64 -mmacosx-version-min=${X86_DEPLOY} -isysroot ${SDKROOT} -msse4.2"
        ARCH_FLAGS_ARM64="-arch arm64 -mmacosx-version-min=${ARM64_DEPLOY} -isysroot ${SDKROOT}"
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
        export MACOSX_DEPLOYMENT_TARGET=${X86_DEPLOY}

        mkdir -p "build_debug_x86"
        pushd "build_debug_x86"
            CFLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_X86 $DEBUG_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_X86 $DEBUG_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $DEBUG_CXXFLAGS" \
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
        popd

        mkdir -p "build_release_x86"
        pushd "build_release_x86"
            CFLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_X86 $RELEASE_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_X86 $RELEASE_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON\
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_X86 $RELEASE_CXXFLAGS" \
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
        popd

        # ARM64 Deploy Target
        export MACOSX_DEPLOYMENT_TARGET=${ARM64_DEPLOY}

        mkdir -p "build_debug_arm64"
        pushd "build_debug_arm64"
            CFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_ARM64 $DEBUG_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $DEBUG_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="0" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=NO \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=NO \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Debug
        popd

        mkdir -p "build_release_arm64"
        pushd "build_release_arm64"
            CFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
            CXXFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
            CPPFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CPPFLAGS" \
            LDFLAGS="$ARCH_FLAGS_ARM64 $RELEASE_LDFLAGS" \
            cmake $TOP/../$SOURCE_DIR -GXcode -DBUILD_SHARED_LIBS:BOOL=ON \
                -DCMAKE_C_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CFLAGS" \
                -DCMAKE_CXX_FLAGS="$ARCH_FLAGS_ARM64 $RELEASE_CXXFLAGS" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_OPTIMIZATION_LEVEL="fast" \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_FAST_MATH=YES \
                -DCMAKE_XCODE_ATTRIBUTE_GCC_GENERATE_DEBUGGING_SYMBOLS=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
                -DCMAKE_XCODE_ATTRIBUTE_LLVM_LTO=YES \
                -DCMAKE_XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING=YES \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
                -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED="NO" \
                -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
                -DCMAKE_OSX_ARCHITECTURES:STRING=arm64 \
                -DCMAKE_OSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET} \
                -DCMAKE_OSX_SYSROOT=${SDKROOT} \
                -DCMAKE_MACOSX_RPATH=YES \
                -DCMAKE_INSTALL_PREFIX=$stage

            cmake --build . --config Release
        popd

        # create fat libs
        lipo -create build_debug_x86/src/Debug/libndofdev.dylib build_debug_arm64/src/Debug/libndofdev.dylib -output ${stage}/lib/debug/libndofdev.dylib
        lipo -create build_release_x86/src/Release/libndofdev.dylib build_release_arm64/src/Release/libndofdev.dylib -output ${stage}/lib/release/libndofdev.dylib

        # create debug bundles
        pushd "${stage}/lib/debug"
            install_name_tool -id "@rpath/libndofdev.dylib" "libndofdev.dylib"
            dsymutil libndofdev.dylib
            strip -x -S libndofdev.dylib
        popd

        pushd "${stage}/lib/release"
            install_name_tool -id "@rpath/libndofdev.dylib" "libndofdev.dylib"
            dsymutil libndofdev.dylib
            strip -x -S libndofdev.dylib
        popd

        if [ -n "${APPLE_SIGNATURE:=""}" -a -n "${APPLE_KEY:=""}" -a -n "${APPLE_KEYCHAIN:=""}" ]; then
            KEYCHAIN_PATH="$HOME/Library/Keychains/$APPLE_KEYCHAIN"
            security unlock-keychain -p $APPLE_KEY $KEYCHAIN_PATH
            for dylib in $stage/lib/*/libndofdev*.dylib;
            do
                if [ -f "$dylib" ]; then
                    codesign --keychain "$KEYCHAIN_PATH" --sign "$APPLE_SIGNATURE" --force --timestamp "$dylib" || true
                fi
            done
            security lock-keychain $KEYCHAIN_PATH
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
