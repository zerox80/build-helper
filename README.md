# Build Instructions for OpenCloud Desktop

This script automates the entire build process for the OpenCloud Desktop Client (github.com/opencloud-eu/desktop).

**Prerequisites:**
*   Visual Studio Build Tools 2022 (C++ Workload)
*   CMake & Git
*   Python 3

**Usage:**
1.  Open a terminal in this directory.
2.  Start the build:
    ```bash
    python build.py
    ```

The script handles everything automatically:
*   Checks the environment (MSVC, tools).
*   Downloads and installs dependencies (Qt 6.8, Zlib, SQLite, etc.).
*   Compiles the project.
*   Creates a ready-to-run ZIP package in the `build` folder.
