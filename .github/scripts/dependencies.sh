#! /usr/bin/env sh

set -ex

install_gnustep_make() {
    echo "::group::GNUstep Make"
    cd $DEPS_PATH
    git clone -q -b ${TOOLS_MAKE_BRANCH:-master} https://github.com/gnustep/tools-make.git
    cd tools-make
    MAKE_OPTS=
    if [ -n "$HOST" ]; then
      MAKE_OPTS="$MAKE_OPTS --host=$HOST"
    fi
    if [ -n "$RUNTIME_VERSION" ]; then
      MAKE_OPTS="$MAKE_OPTS --with-runtime-abi=$RUNTIME_VERSION"
    fi
    ./configure --prefix=$INSTALL_PATH --with-library-combo=$LIBRARY_COMBO $MAKE_OPTS || cat config.log
    make install

    echo Objective-C build flags:
    $INSTALL_PATH/bin/gnustep-config --objc-flags
    echo "::endgroup::"
}

install_libobjc2() {
    echo "::group::libobjc2"
    cd $DEPS_PATH
    git clone -q https://github.com/gnustep/libobjc2.git
    cd libobjc2
    git submodule sync
    git submodule update --init
    mkdir build
    cd build
    cmake \
      -DTESTS=off \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DGNUSTEP_INSTALL_TYPE=NONE \
      -DCMAKE_INSTALL_PREFIX:PATH=$INSTALL_PATH \
      ../
    make install
    echo "::endgroup::"
}

install_gnustep_base() {
    echo "::group::GNUstep Base"
    cd $DEPS_PATH
    . $INSTALL_PATH/share/GNUstep/Makefiles/GNUstep.sh
    git clone -q -b ${LIBS_BASE_BRANCH:-master} https://github.com/gnustep/libs-base.git
    cd libs-base
    ./configure
    make
    make install
    echo "::endgroup::"
}

install_gnustep_gui() {
    echo "::group::GNUstep Gui"
    cd $DEPS_PATH
    git clone -q -b ${LIBS_GUI_BRANCH:-master} https://github.com/gnustep/libs-gui.git
    cd libs-gui
    ./configure
    make
    make install
    echo "::endgroup::"
}

install_gnustep_back() {
    echo "::group::GNUstep Back"
    cd $DEPS_PATH
    git clone -q -b ${LIBS_BACK_BRANCH:-master} https://github.com/gnustep/libs-back.git
    cd libs-back
    ./configure
    make
    make install
    echo "::endgroup::"
}

mkdir -p $DEPS_PATH

# Windows MSVC toolchain uses tools-windows-msvc scripts to install non-GNUstep dependencies
if [ "$LIBRARY_COMBO" = "ng-gnu-gnu" -a "$IS_WINDOWS_MSVC" != "true" ]; then
    install_libobjc2
fi

install_gnustep_make
install_gnustep_base
install_gnustep_gui
install_gnustep_back
