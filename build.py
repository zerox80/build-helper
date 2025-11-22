import os
import sys
import subprocess
import shutil
import urllib.request
import zipfile
import platform

# --- Configuration ---
QT_VERSION = "6.8.0"
QT_MODULES = ["qt5compat", "qtimageformats", "qtshadertools", "qtsvg", "qttools", "qtwebsockets"] 
# Note: 'qtbase' is implied. Added common modules. 
# User's CMakeLists mentions: Core Concurrent Network Widgets Xml Quick QuickWidgets QuickControls2 DBus
# These are mostly in qtbase and qtdeclarative.
# Let's add 'qtdeclarative' explicitly if aqt doesn't include it by default (it usually does in base, but let's be safe).
# Actually, aqt installs 'qtbase' by default. We need 'qtdeclarative' for Quick.
QT_ARCH = "win64_msvc2022_64"
QT_HOST = "windows"
QT_TARGET = "desktop"

DEPS_DIR = os.path.abspath("deps")
BUILD_DIR = os.path.abspath("build")
INSTALL_DIR = os.path.abspath("install")

# URLs
ZLIB_URL = "https://www.zlib.net/zlib-1.3.1.tar.gz"
SQLITE_URL = "https://www.sqlite.org/2024/sqlite-amalgamation-3450100.zip" # Example version
ECM_REPO = "https://invent.kde.org/frameworks/extra-cmake-modules.git"
KEYCHAIN_REPO = "https://github.com/frankosterfeld/qtkeychain.git"
LIBREGRAPH_REPO = "https://github.com/owncloud/libre-graph-api-cpp-qt-client.git"

def run_command(cmd, cwd=None, fail_exit=True):
    print(f">> Running: {' '.join(cmd)}")
    try:
        subprocess.run(cmd, cwd=cwd, check=True, shell=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running command: {e}")
        if fail_exit:
            sys.exit(1)

def find_msvc_env():
    # Try to find vswhere
    vswhere = os.path.expandvars(r"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe")
    if not os.path.exists(vswhere):
        return None
    
    try:
        # Find latest VS 2022 installation
        output = subprocess.check_output([vswhere, "-latest", "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], encoding="utf-8").strip()
        if not output:
            return None
        
        vcvars = os.path.join(output, "VC", "Auxiliary", "Build", "vcvars64.bat")
        if not os.path.exists(vcvars):
            return None
            
        print(f"Found MSVC environment: {vcvars}")
        return vcvars
    except Exception as e:
        print(f"Error finding MSVC: {e}")
        return None

def load_msvc_env(vcvars_path):
    print("Loading MSVC environment variables...")
    # Run vcvars and dump env
    cmd = f'"{vcvars_path}" && set'
    try:
        output = subprocess.check_output(cmd, shell=True, encoding="utf-8", errors="ignore")
        for line in output.splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                os.environ[key] = value
                
        # Update PATH in current process explicitly just in case
        os.environ["PATH"] = os.environ.get("PATH", "")
    except subprocess.CalledProcessError as e:
        print(f"Failed to load MSVC environment: {e}")
        sys.exit(1)

def check_env():
    print("Checking environment...")
    
    # Check for MSVC (cl.exe)
    if not shutil.which("cl"):
        print("cl.exe not found in PATH. Attempting to auto-locate Visual Studio...")
        vcvars = find_msvc_env()
        if vcvars:
            load_msvc_env(vcvars)
            if not shutil.which("cl"):
                print("Error: Loaded vcvars64.bat but cl.exe is still not found.")
                sys.exit(1)
        else:
            print("Error: cl.exe (MSVC) not found and could not auto-locate Visual Studio.")
            print("Please install Visual Studio Build Tools 2022 with C++ workload.")
            sys.exit(1)

    if not shutil.which("cmake"):
        print("Error: cmake not found in PATH.")
        sys.exit(1)
    if not shutil.which("git"):
        print("Error: git not found in PATH.")
        sys.exit(1)
    
    # Check for pip/aqtinstall
    try:
        import aqt
    except ImportError:
        print("aqtinstall not found. Installing...")
        run_command([sys.executable, "-m", "pip", "install", "aqtinstall"])

def setup_dirs():
    if not os.path.exists(DEPS_DIR):
        os.makedirs(DEPS_DIR)
    if not os.path.exists(INSTALL_DIR):
        os.makedirs(INSTALL_DIR)

def install_qt():
    qt_dir = os.path.join(DEPS_DIR, "Qt", QT_VERSION, "msvc2022_64")
    if os.path.exists(qt_dir):
        print(f"Qt {QT_VERSION} already installed.")
        return qt_dir

    print(f"Installing Qt {QT_VERSION}...")
    # aqt install-qt windows desktop 6.8.0 win64_msvc2022_64 -m qt5compat qtimageformats qtshadertools qtwebsockets
    cmd = [sys.executable, "-m", "aqt", "install-qt", QT_HOST, QT_TARGET, QT_VERSION, QT_ARCH, "--outputdir", os.path.join(DEPS_DIR, "Qt"), "-m", "qt5compat", "qtimageformats", "qtshadertools", "qtwebsockets"]
    run_command(cmd)
    return qt_dir

def install_ecm():
    ecm_dir = os.path.join(DEPS_DIR, "extra-cmake-modules")
    if not os.path.exists(ecm_dir):
        print("Cloning extra-cmake-modules...")
        run_command(["git", "clone", "--depth", "1", ECM_REPO, ecm_dir])
    
    # Build/Install ECM
    build_dir = os.path.join(ecm_dir, "build")
    if not os.path.exists(build_dir):
        os.makedirs(build_dir)
        run_command(["cmake", "-S", "..", "-B", ".", "-G", "Ninja" if shutil.which("ninja") else "NMake Makefiles", f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}"], cwd=build_dir)
        run_command(["cmake", "--build", ".", "--target", "install"], cwd=build_dir)

def install_zlib():
    zlib_dir = os.path.join(DEPS_DIR, "zlib")
    if not os.path.exists(zlib_dir):
        print("Downloading zlib...")
        # For simplicity, let's assume we can just clone a mirror or download tarball. 
        # Using a github mirror for easier cloning
        run_command(["git", "clone", "--depth", "1", "https://github.com/madler/zlib.git", zlib_dir])

    build_dir = os.path.join(zlib_dir, "build")
    if not os.path.exists(build_dir):
        os.makedirs(build_dir)
        run_command(["cmake", "-S", "..", "-B", ".", f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}"], cwd=build_dir)
        run_command(["cmake", "--build", ".", "--config", "Release", "--target", "install"], cwd=build_dir)

def install_sqlite():
    sqlite_dir = os.path.join(DEPS_DIR, "sqlite3")
    if os.path.exists(os.path.join(INSTALL_DIR, "include", "sqlite3.h")):
        print("SQLite3 already installed.")
        return

    print("Downloading SQLite3...")
    # Download official amalgamation
    zip_path = os.path.join(DEPS_DIR, "sqlite3.zip")
    urllib.request.urlretrieve(SQLITE_URL, zip_path)
    
    with zipfile.ZipFile(zip_path, 'r') as zip_ref:
        zip_ref.extractall(DEPS_DIR)
    
    # Rename extracted folder (usually sqlite-amalgamation-3450100) to sqlite3
    # Find the folder starting with sqlite-amalgamation
    extracted_folder = None
    for item in os.listdir(DEPS_DIR):
        if item.startswith("sqlite-amalgamation"):
            extracted_folder = os.path.join(DEPS_DIR, item)
            break
    
    if extracted_folder:
        os.rename(extracted_folder, sqlite_dir)
    os.remove(zip_path)

    # Create CMakeLists.txt
    cmake_content = """
cmake_minimum_required(VERSION 3.10)
project(SQLite3 C)

add_library(SQLite3 SHARED sqlite3.c)
target_include_directories(SQLite3 PUBLIC 
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>
)

install(TARGETS SQLite3 EXPORT SQLite3Targets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
    INCLUDES DESTINATION include
)
install(FILES sqlite3.h sqlite3ext.h DESTINATION include)

include(CMakePackageConfigHelpers)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/SQLite3ConfigVersion.cmake"
    VERSION 3.45.1
    COMPATIBILITY AnyNewerVersion
)

export(EXPORT SQLite3Targets
    FILE "${CMAKE_CURRENT_BINARY_DIR}/SQLite3Targets.cmake"
    NAMESPACE SQLite::
)

configure_file(SQLite3Config.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/SQLite3Config.cmake"
    @ONLY
)

install(EXPORT SQLite3Targets
    FILE SQLite3Targets.cmake
    NAMESPACE SQLite::
    DESTINATION lib/cmake/SQLite3
)
install(FILES
    "${CMAKE_CURRENT_BINARY_DIR}/SQLite3Config.cmake"
    "${CMAKE_CURRENT_BINARY_DIR}/SQLite3ConfigVersion.cmake"
    DESTINATION lib/cmake/SQLite3
)
"""
    with open(os.path.join(sqlite_dir, "CMakeLists.txt"), "w") as f:
        f.write(cmake_content)

    # Create Config.cmake.in
    config_in_content = """
@PACKAGE_INIT@
include("${CMAKE_CURRENT_LIST_DIR}/SQLite3Targets.cmake")
check_required_components(SQLite3)
"""
    with open(os.path.join(sqlite_dir, "SQLite3Config.cmake.in"), "w") as f:
        f.write(config_in_content)

    # Build
    build_dir = os.path.join(sqlite_dir, "build")
    if not os.path.exists(build_dir):
        os.makedirs(build_dir)
        run_command(["cmake", "-S", "..", "-B", ".", f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}"], cwd=build_dir)
        run_command(["cmake", "--build", ".", "--config", "Release", "--target", "install"], cwd=build_dir)


def install_qtkeychain(qt_dir):
    keychain_dir = os.path.join(DEPS_DIR, "qtkeychain")
    if not os.path.exists(keychain_dir):
        print("Cloning qtkeychain...")
        run_command(["git", "clone", "--depth", "1", KEYCHAIN_REPO, keychain_dir])
    
    build_dir = os.path.join(keychain_dir, "build")
    if not os.path.exists(build_dir):
        os.makedirs(build_dir)
        # Needs Qt
        run_command(["cmake", "-S", "..", "-B", ".", f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}", f"-DCMAKE_PREFIX_PATH={qt_dir}", "-DBUILD_WITH_QT6=ON"], cwd=build_dir)
        run_command(["cmake", "--build", ".", "--config", "Release", "--target", "install"], cwd=build_dir)

def install_libregraph(qt_dir):
    libregraph_dir = os.path.join(DEPS_DIR, "libre-graph-api-cpp-qt-client")
    if not os.path.exists(libregraph_dir):
        print("Cloning libre-graph-api-cpp-qt-client...")
        run_command(["git", "clone", "--depth", "1", LIBREGRAPH_REPO, libregraph_dir])
    
    # Check if already installed
    # It usually installs to lib/cmake/LibreGraphAPI
    if os.path.exists(os.path.join(INSTALL_DIR, "lib", "cmake", "LibreGraphAPI")) or \
       os.path.exists(os.path.join(INSTALL_DIR, "lib", "cmake", "libregraphapi")):
        print("LibreGraphAPI already installed.")
        return

    print("Building LibreGraphAPI...")
    build_dir = os.path.join(libregraph_dir, "build")
    if os.path.exists(build_dir):
        # If build dir exists but not installed, it might be a failed build. Clean it.
        shutil.rmtree(build_dir)
    
    os.makedirs(build_dir)
    # CMakeLists.txt is in the 'client' subdirectory
    source_dir = os.path.join(libregraph_dir, "client")
    run_command(["cmake", "-S", source_dir, "-B", ".", f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}", f"-DCMAKE_PREFIX_PATH={qt_dir}"], cwd=build_dir)
    run_command(["cmake", "--build", ".", "--config", "Release", "--target", "install"], cwd=build_dir)

def build_opencloud(qt_dir):
    print("Building OpenCloud Desktop...")
    if not os.path.exists(BUILD_DIR):
        os.makedirs(BUILD_DIR)
    
    # We need to point CMake to our local install dir for deps
    cmake_prefix_path = f"{qt_dir};{INSTALL_DIR}"
    
    # Explicitly tell CMake where to find SQLite3 because the default FindSQLite3.cmake might fail with our custom build
    sqlite_include = os.path.join(INSTALL_DIR, "include")
    sqlite_lib = os.path.join(INSTALL_DIR, "lib", "SQLite3.lib")

    cmd = [
        "cmake", "-S", ".", "-B", BUILD_DIR,
        f"-DCMAKE_PREFIX_PATH={cmake_prefix_path}",
        f"-DCMAKE_INSTALL_PREFIX={INSTALL_DIR}",
        "-DBUILD_TESTING=OFF",
        f"-DSQLite3_INCLUDE_DIR={sqlite_include}",
        f"-DSQLite3_LIBRARY={sqlite_lib}"
    ]
    run_command(cmd)
    run_command(["cmake", "--build", BUILD_DIR, "--config", "Release"])
    
    # Package
    print("Packaging...")
    run_command(["cpack", "-C", "Release"], cwd=BUILD_DIR)

def main():
    check_env()
    setup_dirs()
    
    qt_dir = install_qt()
    install_ecm()
    install_zlib()
    install_sqlite()
    install_qtkeychain(qt_dir)
    install_libregraph(qt_dir)
    
    build_opencloud(qt_dir)
    print("Done! Check the build directory for the installer.")

if __name__ == "__main__":
    main()
