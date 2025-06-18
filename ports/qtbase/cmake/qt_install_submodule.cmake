include_guard(GLOBAL)

include("${CURRENT_HOST_INSTALLED_DIR}/share/vcpkg-cmake/vcpkg-port-config.cmake")
include("${CURRENT_HOST_INSTALLED_DIR}/share/vcpkg-cmake-config/vcpkg-port-config.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/qt_install_copyright.cmake")

if(NOT DEFINED QT6_DIRECTORY_PREFIX)
    set(QT6_DIRECTORY_PREFIX "Qt6/")
endif()

if(VCPKG_TARGET_IS_ANDROID)
    # ANDROID_HOME: canonical SDK environment variable
    # ANDROID_SDK_ROOT: legacy qtbase triplet variable
    if(NOT ANDROID_SDK_ROOT)
        if("$ENV{ANDROID_HOME}" STREQUAL "")
            message(FATAL_ERROR "${PORT} requires environment variable ANDROID_HOME to be set.")
        endif()
        set(ANDROID_SDK_ROOT "$ENV{ANDROID_HOME}")
    endif()
endif()

function(qt_download_submodule_impl)
    cmake_parse_arguments(PARSE_ARGV 0 "_qarg" "" "SUBMODULE" "PATCHES")

    if("${_qarg_SUBMODULE}" IN_LIST QT_FROM_QT_GIT)
        # qtinterfaceframework is not available in the release, so we fall back to a `git clone`.
        vcpkg_from_git(
            OUT_SOURCE_PATH SOURCE_PATH
            URL "https://code.qt.io/qt/${_qarg_SUBMODULE}.git"
            REF "${${_qarg_SUBMODULE}_REF}"
            PATCHES ${_qarg_PATCHES}
        )
        if(PORT STREQUAL "qttools") # Keep this for beta & rc's
            vcpkg_from_git(
                OUT_SOURCE_PATH SOURCE_PATH_QLITEHTML
                URL https://code.qt.io/playground/qlitehtml.git
                REF "${${PORT}_qlitehtml_REF}"
                FETCH_REF master
                HEAD_REF master
            )
            # port 'litehtml' is not in vcpkg!
            vcpkg_from_github(
                OUT_SOURCE_PATH SOURCE_PATH_LITEHTML
                REPO litehtml/litehtml
                REF "${${PORT}_litehtml_REF}"
                SHA512 "${${PORT}_litehtml_HASH}"
                HEAD_REF master
            )
            file(COPY "${SOURCE_PATH_QLITEHTML}/" DESTINATION "${SOURCE_PATH}/src/assistant/qlitehtml")
            file(COPY "${SOURCE_PATH_LITEHTML}/" DESTINATION "${SOURCE_PATH}/src/assistant/qlitehtml/src/3rdparty/litehtml")
        elseif(PORT STREQUAL "qtwebengine")
            vcpkg_from_git(
                OUT_SOURCE_PATH SOURCE_PATH_WEBENGINE
                URL https://code.qt.io/qt/qtwebengine-chromium.git
                REF "${${PORT}_chromium_REF}"
            )
            if(NOT EXISTS "${SOURCE_PATH}/src/3rdparty/chromium")
                file(RENAME "${SOURCE_PATH_WEBENGINE}/chromium" "${SOURCE_PATH}/src/3rdparty/chromium")
            endif()
            if(NOT EXISTS "${SOURCE_PATH}/src/3rdparty/gn")
                file(RENAME "${SOURCE_PATH_WEBENGINE}/gn" "${SOURCE_PATH}/src/3rdparty/gn")
            endif()
        endif()
    else()
        if(VCPKG_USE_HEAD_VERSION)
            set(sha512 SKIP_SHA512)
        elseif(NOT DEFINED "${_qarg_SUBMODULE}_HASH")
            message(FATAL_ERROR "No information for ${_qarg_SUBMODULE} -- add it to QT_PORTS and run qtbase in QT_UPDATE_VERSION mode first")
        else()
            set(sha512 SHA512 "${${_qarg_SUBMODULE}_HASH}")
        endif()

        qt_get_url_filename("${_qarg_SUBMODULE}" urls filename)
        vcpkg_download_distfile(archive
            URLS ${urls}
            FILENAME "${filename}"
            ${sha512}
        )
        vcpkg_extract_source_archive(
            SOURCE_PATH
            ARCHIVE "${archive}"
            PATCHES ${_qarg_PATCHES}
        )
    endif()
    set(SOURCE_PATH "${SOURCE_PATH}" PARENT_SCOPE)
endfunction()

function(qt_download_submodule)
    cmake_parse_arguments(PARSE_ARGV 0 "_qarg" "" "" "PATCHES")

    qt_download_submodule_impl(SUBMODULE "${PORT}" PATCHES ${_qarg_PATCHES})

    set(SOURCE_PATH "${SOURCE_PATH}" PARENT_SCOPE)
endfunction()


function(qt_cmake_configure)
    cmake_parse_arguments(PARSE_ARGV 0 "_qarg" "DISABLE_NINJA;DISABLE_PARALLEL_CONFIGURE"
                      ""
                      "TOOL_NAMES;OPTIONS;OPTIONS_DEBUG;OPTIONS_RELEASE;OPTIONS_MAYBE_UNUSED")

    vcpkg_find_acquire_program(PERL) # Perl is probably required by all qt ports for syncqt
    get_filename_component(PERL_PATH ${PERL} DIRECTORY)
    vcpkg_add_to_path(${PERL_PATH})
    if(NOT PORT STREQUAL "qtwebengine" OR QT_IS_LATEST) # qtwebengine requires python2; since 6.3 python3
        vcpkg_find_acquire_program(PYTHON3) # Python is required by some qt ports
        get_filename_component(PYTHON3_PATH ${PYTHON3} DIRECTORY)
        vcpkg_add_to_path(${PYTHON3_PATH})
    endif()

    if(NOT PORT MATCHES "^qtbase")
        list(APPEND _qarg_OPTIONS "-DQT_SYNCQT:PATH=${CURRENT_HOST_INSTALLED_DIR}/tools/Qt6/bin/syncqt.pl")
    endif()
    set(PERL_OPTION "-DHOST_PERL:PATH=${PERL}")

    set(ninja_option "")
    if(_qarg_DISABLE_NINJA)
        set(ninja_option WINDOWS_USE_MSBUILD)
    endif()

    set(disable_parallel "")
    if(_qarg_DISABLE_PARALLEL_CONFIGURE)
        set(disable_parallel DISABLE_PARALLEL_CONFIGURE)
    endif()

    if(VCPKG_CROSSCOMPILING)
        list(APPEND _qarg_OPTIONS "-DQT_HOST_PATH=${CURRENT_HOST_INSTALLED_DIR}")
        list(APPEND _qarg_OPTIONS "-DQT_HOST_PATH_CMAKE_DIR:PATH=${CURRENT_HOST_INSTALLED_DIR}/share")
    endif()

    # Disable warning for CMAKE_(REQUIRE|DISABLE)_FIND_PACKAGE_<packagename>
    string(REGEX MATCHALL "CMAKE_DISABLE_FIND_PACKAGE_[^:=]+" disabled_find_package "${_qarg_OPTIONS}")
    list(APPEND _qarg_OPTIONS_MAYBE_UNUSED ${disabled_find_package})

    string(REGEX MATCHALL "CMAKE_REQUIRE_FIND_PACKAGE_[^:=]+(:BOOL)?=OFF" require_find_package "${_qarg_OPTIONS}")
    list(TRANSFORM require_find_package REPLACE "(:BOOL)?=OFF" "")
    list(APPEND _qarg_OPTIONS_MAYBE_UNUSED ${require_find_package})

    # Disable unused warnings for disabled features. Qt might decide to not emit the feature variables if other features are deactivated.
    string(REGEX MATCHALL "(QT_)?FEATURE_[^:=]+(:BOOL)?=OFF" disabled_features "${_qarg_OPTIONS}")
    list(TRANSFORM disabled_features REPLACE "(:BOOL)?=OFF" "")
    list(APPEND _qarg_OPTIONS_MAYBE_UNUSED ${disabled_features})

    list(APPEND _qarg_OPTIONS "-DQT_NO_FORCE_SET_CMAKE_BUILD_TYPE:BOOL=ON")

    if(VCPKG_TARGET_IS_ANDROID)
        list(APPEND _qarg_OPTIONS "-DANDROID_SDK_ROOT=${ANDROID_SDK_ROOT}")
    endif()

    if(NOT PORT MATCHES "qtbase")
        list(APPEND _qarg_OPTIONS "-DQT_MKSPECS_DIR:PATH=${CURRENT_HOST_INSTALLED_DIR}/share/Qt6/mkspecs")
    endif()

    if(NOT DEFINED VCPKG_OSX_DEPLOYMENT_TARGET)
        list(APPEND _qarg_OPTIONS "-DCMAKE_OSX_DEPLOYMENT_TARGET=14")
    endif()

    if (VCPKG_CMAKE_SYSTEM_PROCESSOR STREQUAL "wasm32") 
        vcpkg_cmake_configure(
            SOURCE_PATH "${SOURCE_PATH}"
            ${ninja_option}
            ${disable_parallel}
            OPTIONS
                -DQT_USE_DEFAULT_CMAKE_OPTIMIZATION_FLAGS:BOOL=ON # We don't want Qt to screw with users toolchain settings.
                -DCMAKE_FIND_PACKAGE_TARGETS_GLOBAL=ON # Because Qt doesn't correctly scope find_package calls.
                #-DQT_HOST_PATH=<somepath> # For crosscompiling
                #-DQT_PLATFORM_DEFINITION_DIR=mkspecs/win32-msvc
                -DQT_QMAKE_TARGET_MKSPEC=linux-clang-libc++-32
                #-DQT_USE_CCACHE
                -DBUILD_SHARED_LIBS:BOOL=OFF
                -DQT_BUILD_EXAMPLE:BOOL=OFF
                -DQT_BUILD_TESTS:BOOL=OFF
                -DQT_BUILD_BENCHMARKS:BOOL=OFF
                -DUNIX:BOOL=ON
                -DWASM:BOOL=ON
                ${PERL_OPTION}
                -DINSTALL_BINDIR:STRING=bin
                -DINSTALL_LIBEXECDIR:STRING=bin
                -DINSTALL_PLUGINSDIR:STRING=${qt_plugindir}
                -DINSTALL_QMLDIR:STRING=${qt_qmldir}
                ${_qarg_OPTIONS}
                -DQT_FEATURE_accessibility_atspi_bridge=OFF
                -DQT_FEATURE_accessibility=OFF
                -DQT_FEATURE_action=OFF
                -DQT_FEATURE_aesni=OFF
                -DQT_FEATURE_android_style_assets=OFF
                -DQT_FEATURE_androiddeployqt=OFF
                -DQT_FEATURE_animation=OFF
                -DQT_FEATURE_appstore_compliant=OFF
                -DQT_FEATURE_arm_crc32=OFF
                -DQT_FEATURE_arm_crypto=OFF
                -DQT_FEATURE_avx=OFF
                -DQT_FEATURE_avx2=OFF
                -DQT_FEATURE_avx512bw=OFF
                -DQT_FEATURE_avx512cd=OFF
                -DQT_FEATURE_avx512dq=OFF
                -DQT_FEATURE_avx512er=OFF
                -DQT_FEATURE_avx512f=OFF
                -DQT_FEATURE_avx512ifma=OFF
                -DQT_FEATURE_avx512pf=OFF
                -DQT_FEATURE_avx512vbmi=OFF
                -DQT_FEATURE_avx512vbmi2=OFF
                -DQT_FEATURE_avx512vl=OFF
                -DQT_FEATURE_backtrace=OFF
                -DQT_FEATURE_cborstreamreader=ON
                -DQT_FEATURE_cborstreamwriter=ON
                -DQT_FEATURE_clipboard=OFF
                -DQT_FEATURE_clock_gettime=OFF
                -DQT_FEATURE_clock_monotonic=OFF
                -DQT_FEATURE_close_range=OFF
                -DQT_FEATURE_colornames=OFF
                -DQT_FEATURE_commandlineparser=ON
                -DQT_FEATURE_concatenatetablesproxymodel=ON
                -DQT_FEATURE_concurrent=OFF
                -DQT_FEATURE_cpp_winrt=OFF
                -DQT_FEATURE_cross_compile=ON
                -DQT_FEATURE_cssparser=ON
                -DQT_FEATURE_ctf=OFF
                -DQT_FEATURE_cursor=ON
                -DQT_FEATURE_cxx11_future=OFF
                -DQT_FEATURE_cxx17_filesystem=OFF
                -DQT_FEATURE_cxx20=OFF
                -DQT_FEATURE_cxx2a=OFF
                -DQT_FEATURE_cxx2b=OFF
                -DQT_FEATURE_datestring=ON
                -DQT_FEATURE_datetimeparser=ON
                -DQT_FEATURE_dbus_linked=OFF
                -DQT_FEATURE_dbus=OFF
                -DQT_FEATURE_debug_and_release=OFF
                -DQT_FEATURE_debug=OFF
                -DQT_FEATURE_desktopservices=ON
                -DQT_FEATURE_developer_build=OFF
                -DQT_FEATURE_direct2d=OFF
                -DQT_FEATURE_direct2d1_1=OFF
                -DQT_FEATURE_directfb=OFF
                -DQT_FEATURE_directwrite=OFF
                -DQT_FEATURE_directwrite3=OFF
                -DQT_FEATURE_dladdr=OFF
                -DQT_FEATURE_dlopen=OFF
                -DQT_FEATURE_dom=ON
                -DQT_FEATURE_doubleconversion=ON
                -DQT_FEATURE_draganddrop=OFF
                -DQT_FEATURE_drm_atomic=OFF
                -DQT_FEATURE_dynamicgl=OFF
                -DQT_FEATURE_easingcurve=ON
                -DQT_FEATURE_egl_x11=OFF
                -DQT_FEATURE_egl=OFF
                -DQT_FEATURE_eglfs_brcm=OFF
                -DQT_FEATURE_eglfs_egldevice=OFF
                -DQT_FEATURE_eglfs_gbm=OFF
                -DQT_FEATURE_eglfs_mali=OFF
                -DQT_FEATURE_eglfs_openwfd=OFF
                -DQT_FEATURE_eglfs_rcar=OFF
                -DQT_FEATURE_eglfs_viv_wl=OFF
                -DQT_FEATURE_eglfs_viv=OFF
                -DQT_FEATURE_eglfs_vsp2=OFF
                -DQT_FEATURE_eglfs_x11=OFF
                -DQT_FEATURE_eglfs=OFF
                -DQT_FEATURE_etw=OFF
                -DQT_FEATURE_evdev=OFF
                -DQT_FEATURE_eventfd=OFF
                -DQT_FEATURE_f16c=OFF
                -DQT_FEATURE_filesystemiterator=OFF
                -DQT_FEATURE_filesystemmodel=OFF
                -DQT_FEATURE_filesystemwatcher=OFF
                -DQT_FEATURE_fontconfig=OFF
                -DQT_FEATURE_force_asserts=OFF
                -DQT_FEATURE_force_debug_info=OFF
                -DQT_FEATURE_forkfd_pidfd=OFF
                -DQT_FEATURE_framework=OFF
                -DQT_FEATURE_freetype=ON
                -DQT_FEATURE_futimens=ON
                -DQT_FEATURE_future=OFF
                -DQT_FEATURE_gc_binaries=ON
                -DQT_FEATURE_gestures=OFF
                -DQT_FEATURE_getauxval=OFF
                -DQT_FEATURE_getentropy=OFF
                -DQT_FEATURE_gif=OFF
                -DQT_FEATURE_glib=OFF
                -DQT_FEATURE_glibc=OFF
                -DQT_FEATURE_gui=ON
                -DQT_FEATURE_harfbuzz=OFF
                -DQT_FEATURE_highdpiscaling=ON
                -DQT_FEATURE_hijricalendar=ON
                -DQT_FEATURE_ico=OFF
                -DQT_FEATURE_icu=OFF
                -DQT_FEATURE_identityproxymodel=ON
                -DQT_FEATURE_im=OFF
                -DQT_FEATURE_image_heuristic_mask=ON
                -DQT_FEATURE_image_text=ON
                -DQT_FEATURE_imageformat_bmp=ON
                -DQT_FEATURE_imageformat_jpeg=ON
                -DQT_FEATURE_imageformat_png=ON
                -DQT_FEATURE_imageformat_ppm=ON
                -DQT_FEATURE_imageformat_xbm=ON
                -DQT_FEATURE_imageformat_xpm=ON
                -DQT_FEATURE_imageformatplugin=ON
                -DQT_FEATURE_imageio_text_loading=ON
                -DQT_FEATURE_inotify=OFF
                -DQT_FEATURE_integrityfb=OFF
                -DQT_FEATURE_integrityhid=OFF
                -DQT_FEATURE_intelcet=OFF
                -DQT_FEATURE_islamiccivilcalendar=ON
                -DQT_FEATURE_itemmodel=ON
                -DQT_FEATURE_jalalicalendar=ON
                -DQT_FEATURE_journald=OFF
                -DQT_FEATURE_jpeg=OFF
                -DQT_FEATURE_kms=OFF
                -DQT_FEATURE_largefile=OFF
                -DQT_FEATURE_libinput_axis_api=OFF
                -DQT_FEATURE_libinput_hires_wheel_support=OFF
                -DQT_FEATURE_libinput=OFF
                -DQT_FEATURE_library=OFF
                -DQT_FEATURE_libudev=OFF
                -DQT_FEATURE_linkat=OFF
                -DQT_FEATURE_linuxfb=OFF
                -DQT_FEATURE_lttng=OFF
                -DQT_FEATURE_mimetype_database=ON
                -DQT_FEATURE_mimetype=ON
                -DQT_FEATURE_mips_dsp=OFF
                -DQT_FEATURE_mips_dspr2=OFF
                -DQT_FEATURE_movie=OFF
                -DQT_FEATURE_mtdev=OFF
                -DQT_FEATURE_multiprocess=OFF
                -DQT_FEATURE_neon=OFF
                -DQT_FEATURE_network=OFF
                -DQT_FEATURE_no_direct_extern_access=OFF
                -DQT_FEATURE_opengl=OFF
                -DQT_FEATURE_opengles2=ON
                -DQT_FEATURE_opengles3=OFF
                -DQT_FEATURE_opengles31=OFF
                -DQT_FEATURE_opengles32=OFF
                -DQT_FEATURE_openssl_hash=OFF
                -DQT_FEATURE_openssl_linked=OFF
                -DQT_FEATURE_openssl=OFF
                -DQT_FEATURE_opensslv11=OFF
                -DQT_FEATURE_opensslv30=OFF
                -DQT_FEATURE_openvg=OFF
                -DQT_FEATURE_pcre2=ON
                -DQT_FEATURE_pdf=OFF
                -DQT_FEATURE_permissions=OFF
                -DQT_FEATURE_picture=ON
                -DQT_FEATURE_pkg_config=OFF
                -DQT_FEATURE_png=ON
                -DQT_FEATURE_poll_exit_on_error=OFF
                -DQT_FEATURE_poll_poll=ON
                -DQT_FEATURE_poll_pollts=OFF
                -DQT_FEATURE_poll_ppoll=OFF
                -DQT_FEATURE_poll_select=OFF
                -DQT_FEATURE_posix_fallocate=ON
                -DQT_FEATURE_posix_sem=OFF
                -DQT_FEATURE_posix_shm=OFF
                -DQT_FEATURE_precompile_header=ON
                -DQT_FEATURE_printsupport=OFF
                -DQT_FEATURE_private_tests=OFF
                -DQT_FEATURE_process=OFF
                -DQT_FEATURE_processenvironment=OFF
                -DQT_FEATURE_proxymodel=ON
                -DQT_FEATURE_qqnx_imf=OFF
                -DQT_FEATURE_qqnx_pps=OFF
                -DQT_FEATURE_raster_64bit=ON
                -DQT_FEATURE_raster_fp=ON
                -DQT_FEATURE_rdrnd=OFF
                -DQT_FEATURE_rdseed=OFF
                -DQT_FEATURE_reduce_exports=ON
                -DQT_FEATURE_reduce_relocations=OFF
                -DQT_FEATURE_regularexpression=ON
                -DQT_FEATURE_relocatable=ON
                -DQT_FEATURE_renameat2=OFF
                -DQT_FEATURE_rpath=OFF
                -DQT_FEATURE_separate_debug_info=OFF
                -DQT_FEATURE_sessionmanager=OFF
                -DQT_FEATURE_settings=OFF
                -DQT_FEATURE_sha3_fast=ON
                -DQT_FEATURE_shani=OFF
                -DQT_FEATURE_shared=OFF
                -DQT_FEATURE_sharedmemory=OFF
                -DQT_FEATURE_shortcut=ON
                -DQT_FEATURE_signaling_nan=ON
                -DQT_FEATURE_simulator_and_device=OFF
                -DQT_FEATURE_slog2=OFF
                -DQT_FEATURE_sortfilterproxymodel=ON
                -DQT_FEATURE_sql=OFF
                -DQT_FEATURE_sse2=OFF
                -DQT_FEATURE_sse3=OFF
                -DQT_FEATURE_sse4_1=OFF
                -DQT_FEATURE_sse4_2=OFF
                -DQT_FEATURE_ssse3=OFF
                -DQT_FEATURE_stack_protector_strong=OFF
                -DQT_FEATURE_standarditemmodel=ON
                -DQT_FEATURE_static=ON
                -DQT_FEATURE_statx=OFF
                -DQT_FEATURE_std_atomic64=ON
                -DQT_FEATURE_stdlib_libcpp=OFF
                -DQT_FEATURE_stringlistmodel=ON
                -DQT_FEATURE_syslog=OFF
                -DQT_FEATURE_system_doubleconversion=OFF
                -DQT_FEATURE_system_freetype=OFF
                -DQT_FEATURE_system_harfbuzz=OFF
                -DQT_FEATURE_system_jpeg=OFF
                -DQT_FEATURE_system_libb2=OFF
                -DQT_FEATURE_system_pcre2=OFF
                -DQT_FEATURE_system_png=OFF
                -DQT_FEATURE_system_textmarkdownreader=OFF
                -DQT_FEATURE_system_xcb_xinput=OFF
                -DQT_FEATURE_system_zlib=OFF
                -DQT_FEATURE_systemsemaphore=OFF
                -DQT_FEATURE_systemtrayicon=OFF
                -DQT_FEATURE_sysv_sem=OFF
                -DQT_FEATURE_sysv_shm=OFF
                -DQT_FEATURE_tabletevent=OFF
                -DQT_FEATURE_temporaryfile=ON
                -DQT_FEATURE_testlib=OFF
                -DQT_FEATURE_textdate=ON
                -DQT_FEATURE_texthtmlparser=ON
                -DQT_FEATURE_textmarkdownreader=ON
                -DQT_FEATURE_textmarkdownwriter=ON
                -DQT_FEATURE_textodfwriter=ON
                -DQT_FEATURE_thread=OFF
                -DQT_FEATURE_timezone=OFF
                -DQT_FEATURE_translation=OFF
                -DQT_FEATURE_transposeproxymodel=OFF
                -DQT_FEATURE_tslib=OFF
                -DQT_FEATURE_tuiotouch=OFF
                -DQT_FEATURE_undocommand=ON
                -DQT_FEATURE_undogroup=ON
                -DQT_FEATURE_undostack=ON
                -DQT_FEATURE_use_bfd_linker=OFF
                -DQT_FEATURE_use_gold_linker=OFF
                -DQT_FEATURE_use_lld_linker=OFF
                -DQT_FEATURE_use_mold_linker=OFF
                -DQT_FEATURE_vaes=OFF
                -DQT_FEATURE_validator=ON
                -DQT_FEATURE_vkgen=OFF
                -DQT_FEATURE_vkkhrdisplay=OFF
                -DQT_FEATURE_vnc=OFF
                -DQT_FEATURE_vsp2=OFF
                -DQT_FEATURE_vulkan=OFF
                -DQT_FEATURE_wasm_exceptions=OFF
                -DQT_FEATURE_wasm_simd128=OFF
                -DQT_FEATURE_whatsthis=OFF
                -DQT_FEATURE_wheelevent=OFF
                -DQT_FEATURE_widgets=OFF
                -DQT_FEATURE_x86intrin=ON
                -DQT_FEATURE_xcb_egl_plugin=OFF
                -DQT_FEATURE_xcb_glx_plugin=OFF
                -DQT_FEATURE_xcb_glx=OFF
                -DQT_FEATURE_xcb_native_painting=OFF
                -DQT_FEATURE_xcb_sm=OFF
                -DQT_FEATURE_xcb_xlib=OFF
                -DQT_FEATURE_xcb=OFF
                -DQT_FEATURE_xkbcommon_x11=OFF
                -DQT_FEATURE_xkbcommon=OFF
                -DQT_FEATURE_xlib=OFF
                -DQT_FEATURE_xml=ON
                -DQT_FEATURE_xmlstream=ON
                -DQT_FEATURE_xmlstreamreader=ON
                -DQT_FEATURE_xmlstreamwriter=ON
                -DQT_FEATURE_xrender=OFF
                -DQT_FEATURE_zstd=OFF
                -DQT_USE_BUNDLED_BundledFreetype=ON
                -DQT_USE_BUNDLED_BundledLibpng=ON
                -DQT_USE_BUNDLED_BundledPcre2=ON
                -DQT_USE_BUNDLED_BundledZLIB=ON
            OPTIONS_RELEASE
                ${_qarg_OPTIONS_RELEASE}
                -DINSTALL_DOCDIR:STRING=doc/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_INCLUDEDIR:STRING=include/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_DESCRIPTIONSDIR:STRING=share/Qt6/modules
                -DINSTALL_MKSPECSDIR:STRING=share/Qt6/mkspecs
                -DINSTALL_TRANSLATIONSDIR:STRING=translations/${QT6_DIRECTORY_PREFIX}
            OPTIONS_DEBUG
                # -DFEATURE_debug:BOOL=ON only needed by qtbase and auto detected?
                -DINSTALL_DOCDIR:STRING=../doc/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_INCLUDEDIR:STRING=../include/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_TRANSLATIONSDIR:STRING=../translations/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_DESCRIPTIONSDIR:STRING=../share/Qt6/modules
                -DINSTALL_MKSPECSDIR:STRING=../share/Qt6/mkspecs
                ${_qarg_OPTIONS_DEBUG}
            MAYBE_UNUSED_VARIABLES
                INSTALL_BINDIR
                INSTALL_DOCDIR
                INSTALL_LIBEXECDIR
                INSTALL_QMLDIR  # No qml files
                INSTALL_TRANSLATIONSDIR # No translations
                INSTALL_PLUGINSDIR # No plugins
                INSTALL_DESCRIPTIONSDIR
                INSTALL_INCLUDEDIR
                HOST_PERL
                QT_SYNCQT
                QT_NO_FORCE_SET_CMAKE_BUILD_TYPE
                ${_qarg_OPTIONS_MAYBE_UNUSED}
                INPUT_bundled_xcb_xinput
                INPUT_freetype
                INPUT_harfbuzz
                INPUT_libjpeg
                INPUT_libmd4c
                INPUT_libpng
                INPUT_opengl
                INPUT_openssl
                INPUT_xcb
                INPUT_xkbcommon
        )
    else()
        vcpkg_cmake_configure(
            SOURCE_PATH "${SOURCE_PATH}"
            ${ninja_option}
            ${disable_parallel}
            OPTIONS
                -DQT_FORCE_WARN_APPLE_SDK_AND_XCODE_CHECK=ON
                -DQT_NO_FORCE_SET_CMAKE_BUILD_TYPE:BOOL=ON
                -DQT_USE_DEFAULT_CMAKE_OPTIMIZATION_FLAGS:BOOL=ON # We don't want Qt to mess with users toolchain settings.
                -DCMAKE_FIND_PACKAGE_TARGETS_GLOBAL=ON # Because Qt doesn't correctly scope find_package calls. 
                #-DQT_HOST_PATH=<somepath> # For crosscompiling
                #-DQT_PLATFORM_DEFINITION_DIR=mkspecs/win32-msvc
                #-DQT_QMAKE_TARGET_MKSPEC=win32-msvc
                #-DQT_USE_CCACHE
                -DQT_BUILD_EXAMPLES:BOOL=OFF
                -DQT_BUILD_TESTS:BOOL=OFF
                -DQT_BUILD_BENCHMARKS:BOOL=OFF
                ${PERL_OPTION}
                -DINSTALL_BINDIR:STRING=bin
                -DINSTALL_LIBEXECDIR:STRING=bin
                -DINSTALL_PLUGINSDIR:STRING=${qt_plugindir}
                -DINSTALL_QMLDIR:STRING=${qt_qmldir}
                ${_qarg_OPTIONS}
            OPTIONS_RELEASE
                ${_qarg_OPTIONS_RELEASE}
                -DINSTALL_DOCDIR:STRING=doc/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_INCLUDEDIR:STRING=include/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_DESCRIPTIONSDIR:STRING=share/Qt6/modules
                -DINSTALL_MKSPECSDIR:STRING=share/Qt6/mkspecs
                -DINSTALL_TRANSLATIONSDIR:STRING=translations/${QT6_DIRECTORY_PREFIX}
            OPTIONS_DEBUG
                # -DFEATURE_debug:BOOL=ON only needed by qtbase and auto detected?
                -DINSTALL_DOCDIR:STRING=../doc/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_INCLUDEDIR:STRING=../include/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_TRANSLATIONSDIR:STRING=../translations/${QT6_DIRECTORY_PREFIX}
                -DINSTALL_DESCRIPTIONSDIR:STRING=../share/Qt6/modules
                -DINSTALL_MKSPECSDIR:STRING=../share/Qt6/mkspecs
                ${_qarg_OPTIONS_DEBUG}
            MAYBE_UNUSED_VARIABLES
                INSTALL_BINDIR
                INSTALL_DOCDIR
                INSTALL_LIBEXECDIR
                INSTALL_QMLDIR  # No qml files
                INSTALL_TRANSLATIONSDIR # No translations
                INSTALL_PLUGINSDIR # No plugins
                INSTALL_DESCRIPTIONSDIR
                INSTALL_INCLUDEDIR
                HOST_PERL
                QT_SYNCQT
                QT_NO_FORCE_SET_CMAKE_BUILD_TYPE
                QT_FORCE_WARN_APPLE_SDK_AND_XCODE_CHECK
                ${_qarg_OPTIONS_MAYBE_UNUSED}
                INPUT_bundled_xcb_xinput
                INPUT_freetype
                INPUT_harfbuzz
                INPUT_libjpeg
                INPUT_libmd4c
                INPUT_libpng
                INPUT_opengl
                INPUT_openssl
                INPUT_xcb
                INPUT_xkbcommon
        )
    endif()
    foreach(suffix IN ITEMS dbg rel)
        if(EXISTS "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${suffix}/config.summary")
            file(COPY_FILE
                "${CURRENT_BUILDTREES_DIR}/${TARGET_TRIPLET}-${suffix}/config.summary"
                "${CURRENT_BUILDTREES_DIR}/config.summary-${TARGET_TRIPLET}-${suffix}.log"
            )
        endif()
    endforeach()
endfunction()

function(qt_fix_prl_files)
    file(TO_CMAKE_PATH "${CURRENT_PACKAGES_DIR}/lib" package_dir)
    file(TO_CMAKE_PATH "${package_dir}/lib" lib_path)
    file(TO_CMAKE_PATH "${package_dir}/include/Qt6" include_path)
    file(TO_CMAKE_PATH "${CURRENT_INSTALLED_DIR}" install_prefix)
    file(GLOB_RECURSE prl_files "${CURRENT_PACKAGES_DIR}/*.prl" "${CURRENT_PACKAGES_DIR}/*.pri")
    foreach(prl_file IN LISTS prl_files)
        file(READ "${prl_file}" _contents)
        string(REPLACE "${lib_path}" "\$\$[QT_INSTALL_LIBS]" _contents "${_contents}")
        string(REPLACE "${include_path}" "\$\$[QT_INSTALL_HEADERS]" _contents "${_contents}")
        string(REPLACE "${install_prefix}" "\$\$[QT_INSTALL_PREFIX]" _contents "${_contents}")
        string(REPLACE "[QT_INSTALL_PREFIX]/lib/objects-Debug" "[QT_INSTALL_LIBS]/objects-Debug" _contents "${_contents}")
        string(REPLACE "[QT_INSTALL_PREFIX]/Qt6/qml" "[QT_INSTALL_QML]" _contents "${_contents}")
        #Note: This only works without an extra if case since QT_INSTALL_PREFIX is the same for debug and release
        file(WRITE "${prl_file}" "${_contents}")
    endforeach()
endfunction()

function(qt_fixup_and_cleanup)
        cmake_parse_arguments(PARSE_ARGV 0 "_qarg" ""
                      ""
                      "TOOL_NAMES")
    vcpkg_copy_pdbs()

    ## Handle PRL files
    qt_fix_prl_files()

    ## Handle CMake files.
    set(COMPONENTS)
    file(GLOB COMPONENTS_OR_FILES LIST_DIRECTORIES true "${CURRENT_PACKAGES_DIR}/share/Qt6*")
    list(REMOVE_ITEM COMPONENTS_OR_FILES "${CURRENT_PACKAGES_DIR}/share/Qt6")
    foreach(_glob IN LISTS COMPONENTS_OR_FILES)
        if(IS_DIRECTORY "${_glob}")
            string(REPLACE "${CURRENT_PACKAGES_DIR}/share/Qt6" "" _component "${_glob}")
            debug_message("Adding cmake component: '${_component}'")
            list(APPEND COMPONENTS ${_component})
        endif()
    endforeach()

    foreach(_comp IN LISTS COMPONENTS)
        if(EXISTS "${CURRENT_PACKAGES_DIR}/share/Qt6${_comp}")
            vcpkg_cmake_config_fixup(PACKAGE_NAME "Qt6${_comp}" CONFIG_PATH "share/Qt6${_comp}" TOOLS_PATH "tools/Qt6/bin")
            # Would rather put it into share/cmake as before but the import_prefix correction in vcpkg_cmake_config_fixup is working against that.
        else()
            message(STATUS "WARNING: Qt component ${_comp} not found/built!")
        endif()
    endforeach()
    #fix debug plugin paths (should probably be fixed in vcpkg_cmake_config_fixup)
    file(GLOB_RECURSE DEBUG_CMAKE_TARGETS "${CURRENT_PACKAGES_DIR}/share/**/*Targets-debug.cmake")
    debug_message("DEBUG_CMAKE_TARGETS:${DEBUG_CMAKE_TARGETS}")
    foreach(_debug_target IN LISTS DEBUG_CMAKE_TARGETS)
        vcpkg_replace_string("${_debug_target}" "{_IMPORT_PREFIX}/${qt_plugindir}" "{_IMPORT_PREFIX}/debug/${qt_plugindir}" IGNORE_UNCHANGED)
        vcpkg_replace_string("${_debug_target}" "{_IMPORT_PREFIX}/${qt_qmldir}" "{_IMPORT_PREFIX}/debug/${qt_qmldir}" IGNORE_UNCHANGED)
    endforeach()

    file(GLOB_RECURSE STATIC_CMAKE_TARGETS "${CURRENT_PACKAGES_DIR}/share/Qt6Qml/QmlPlugins/*.cmake")
    foreach(_plugin_target IN LISTS STATIC_CMAKE_TARGETS)
        # restore a single get_filename_component which was remove by vcpkg_cmake_config_fixup
        vcpkg_replace_string("${_plugin_target}"
                             [[get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)]]
                             "get_filename_component(_IMPORT_PREFIX \"\${CMAKE_CURRENT_LIST_FILE}\" PATH)\nget_filename_component(_IMPORT_PREFIX \"\${_IMPORT_PREFIX}\" PATH)"
                             IGNORE_UNCHANGED)
    endforeach()

    set(qt_tooldest "${CURRENT_PACKAGES_DIR}/tools/Qt6/bin")
    set(qt_searchdir "${CURRENT_PACKAGES_DIR}/bin")
    ## Handle Tools
    foreach(_tool IN LISTS _qarg_TOOL_NAMES)
        if(NOT EXISTS "${CURRENT_PACKAGES_DIR}/bin/${_tool}${VCPKG_TARGET_EXECUTABLE_SUFFIX}")
            debug_message("Removed '${_tool}' from copy tools list since it was not found!")
            list(REMOVE_ITEM _qarg_TOOL_NAMES ${_tool})
        endif()
    endforeach()
    if(_qarg_TOOL_NAMES)
        set(tool_names ${_qarg_TOOL_NAMES})
        vcpkg_copy_tools(TOOL_NAMES ${tool_names} SEARCH_DIR "${qt_searchdir}" DESTINATION "${qt_tooldest}" AUTO_CLEAN)
    endif()

    if(VCPKG_TARGET_IS_WINDOWS AND VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        if(EXISTS "${CURRENT_PACKAGES_DIR}/bin/")
            file(COPY "${CURRENT_PACKAGES_DIR}/bin/" DESTINATION "${CURRENT_PACKAGES_DIR}/tools/Qt6/bin")
        endif()
        file(GLOB_RECURSE _installed_dll_files RELATIVE "${CURRENT_INSTALLED_DIR}/tools/Qt6/bin" "${CURRENT_INSTALLED_DIR}/tools/Qt6/bin/*.dll")
        foreach(_dll_to_remove IN LISTS _installed_dll_files)
            file(GLOB_RECURSE _packaged_dll_file "${CURRENT_PACKAGES_DIR}/tools/Qt6/bin/${_dll_to_remove}")
            if(EXISTS "${_packaged_dll_file}")
                file(REMOVE "${_packaged_dll_file}")
            endif()
        endforeach()
        file(GLOB_RECURSE _folders LIST_DIRECTORIES true "${CURRENT_PACKAGES_DIR}/tools/Qt6/bin/**/")
        file(GLOB_RECURSE _files "${CURRENT_PACKAGES_DIR}/tools/Qt6/bin/**/")
        if(_files)
            list(REMOVE_ITEM _folders ${_files})
        endif()
        foreach(_dir IN LISTS _folders)
            if(NOT "${_remaining_dll_files}" MATCHES "${_dir}")
                file(REMOVE_RECURSE "${_dir}")
            endif()
        endforeach()
    endif()
    file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/lib/cmake/"
                        "${CURRENT_PACKAGES_DIR}/debug/share"
                        "${CURRENT_PACKAGES_DIR}/lib/cmake/"
                        "${CURRENT_PACKAGES_DIR}/debug/include"
                        )

    if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
        file(GLOB_RECURSE _bin_files "${CURRENT_PACKAGES_DIR}/bin/*")
        if(NOT _bin_files STREQUAL "")
            message(STATUS "Remaining files in bin: '${_bin_files}'")
        else() # Only clean if empty otherwise let vcpkg throw and error.
            file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin/" "${CURRENT_PACKAGES_DIR}/debug/bin/")
        endif()
    endif()

    vcpkg_fixup_pkgconfig()
endfunction()

function(qt_install_submodule)
    cmake_parse_arguments(PARSE_ARGV 0 "_qis" "DISABLE_NINJA"
                          ""
                          "PATCHES;TOOL_NAMES;CONFIGURE_OPTIONS;CONFIGURE_OPTIONS_DEBUG;CONFIGURE_OPTIONS_RELEASE;CONFIGURE_OPTIONS_MAYBE_UNUSED")

    set(qt_plugindir ${QT6_DIRECTORY_PREFIX}plugins)
    set(qt_qmldir ${QT6_DIRECTORY_PREFIX}qml)

    qt_download_submodule(PATCHES ${_qis_PATCHES})

    if(VCPKG_TARGET_IS_ANDROID)
        # Qt only supports dynamic linkage on Android,
        # https://bugreports.qt.io/browse/QTBUG-32618.
        # It requires libc++_shared, cf. <qtbase>/cmake/QtPlatformAndroid.cmake
        # and https://developer.android.com/ndk/guides/cpp-support#sr
        vcpkg_check_linkage(ONLY_DYNAMIC_LIBRARY)
    endif()

    if(_qis_DISABLE_NINJA)
        set(_opt DISABLE_NINJA)
    endif()
    qt_cmake_configure(${_opt}
                       OPTIONS ${_qis_CONFIGURE_OPTIONS}
                       OPTIONS_DEBUG ${_qis_CONFIGURE_OPTIONS_DEBUG}
                       OPTIONS_RELEASE ${_qis_CONFIGURE_OPTIONS_RELEASE}
                       OPTIONS_MAYBE_UNUSED ${_qis_CONFIGURE_OPTIONS_MAYBE_UNUSED}
                       )

    vcpkg_cmake_install(ADD_BIN_TO_PATH)

    qt_fixup_and_cleanup(TOOL_NAMES ${_qis_TOOL_NAMES})

    qt_install_copyright("${SOURCE_PATH}")
    set(SOURCE_PATH "${SOURCE_PATH}" PARENT_SCOPE)
endfunction()

include("${CMAKE_CURRENT_LIST_DIR}/qt_port_details.cmake")
