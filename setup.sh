#!/bin/sh
#
# setup.sh — Configuration and build script for Swift N-body integrator
# Create @make_libswift and @make_drivers from templates with paths and
# compiler options, then optionally build libswift.a and/or driver executables.
#
# Usage:
#   ./setup.sh [options]
#
# Options:
#   --compiler=COMPILER    Fortran compiler (default: auto-detect)
#   --fflags=FLAGS         Compiler flags for both library and drivers
#   --fflags-lib=FLAGS     Compiler flags for library only (overrides --fflags)
#   --fflags-drivers=FLAGS Compiler flags for drivers only (overrides --fflags)
#   --cppflags=FLAGS       Preprocessor flags (default: '-D_OPEN_POSITION -D_RECUR_SUB')
#   --precomp=PATH         Preprocessor path (default: auto-detect cpp)
#   --swift-dir=PATH       Swift root directory (default: ./swift_pirates)
#   --build                Build library and drivers
#   --build-lib            Build library only
#   --build-drivers        Build drivers only
#   --clean                Remove libswift.a, .o files, and driver executables before building
#   --help                 Show this help message
#

# ============================================================
# Default values
# ============================================================
SWIFT_DIR=""
FORTRAN=""
FFLAGS=""
FFLAGS_LIB=""
FFLAGS_DRIVERS=""
FFLAGS_LIB_USER=""
FFLAGS_DRIVERS_USER=""
CPPFLAGS="-D_OPEN_POSITION -D_RECUR_SUB"
PRECOMP=""
DO_BUILD_LIB=0
DO_BUILD_DRIVERS=0
DO_CLEAN=0
OS=""

# ============================================================
# Parse command-line arguments
# ============================================================
print_help() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \{0,1\}//'
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                           # Auto-detect everything"
    echo "  ./setup.sh --compiler=gfortran       # Use gfortran as Fortran compiler"
    echo "  ./setup.sh --build                   # Build library and drivers"
    echo "  ./setup.sh --build-lib               # Build library only"
    echo "  ./setup.sh --build-drivers           # Build drivers only"
    echo "  ./setup.sh --clean --build           # Clean and rebuild everything"
    echo "  ./setup.sh --fflags='-O2'            # Custom flags for both"
    echo "  ./setup.sh --fflags-drivers='-O2 -g' # Custom driver flags only"
}

for arg in "$@"; do
    case "$arg" in
        --compiler=*)
            FORTRAN="${arg#*=}"
            ;;
        --fflags=*)
            FFLAGS="${arg#*=}"
            ;;
        --fflags-lib=*)
            FFLAGS_LIB_USER="${arg#*=}"
            ;;
        --fflags-drivers=*)
            FFLAGS_DRIVERS_USER="${arg#*=}"
            ;;
        --cppflags=*)
            CPPFLAGS="${arg#*=}"
            ;;
        --precomp=*)
            PRECOMP="${arg#*=}"
            ;;
        --swift-dir=*)
            SWIFT_DIR="${arg#*=}"
            ;;
        --build)
            DO_BUILD_LIB=1
            DO_BUILD_DRIVERS=1
            ;;
        --build-lib)
            DO_BUILD_LIB=1
            ;;
        --build-drivers)
            DO_BUILD_DRIVERS=1
            ;;
        --clean)
            DO_CLEAN=1
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $arg"
            print_help
            exit 1
            ;;
    esac
done

# ============================================================
# Utility functions
# ============================================================
info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# ============================================================
# Detect operating system
# ============================================================
detect_os() {
    case "$(uname -s)" in
        Linux*)  OS="linux"  ;;
        Darwin*) OS="macos"  ;;
        *)       OS="unknown" ;;
    esac
    info "Detected OS: $OS"
}

# ============================================================
# Set SWIFT_DIR
# ============================================================
set_swift_dir() {
    if [ -z "$SWIFT_DIR" ]; then
        # setup.sh is at the project root; swift_pirates/ is a subdirectory
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        SWIFT_DIR="${SCRIPT_DIR}/swift_pirates"
    fi

    if [ ! -f "$SWIFT_DIR/@makeall_libswift" ]; then
        error "Cannot find @makeall_libswift in $SWIFT_DIR — is the swift_pirates/ folder present?"
    fi

    info "SWIFT_DIR: $SWIFT_DIR"
}

# ============================================================
# Detect Fortran compiler
# ============================================================
detect_compiler() {
    if [ -n "$FORTRAN" ]; then
        # User specified a compiler — verify it exists
        if ! command -v "$FORTRAN" > /dev/null 2>&1; then
            error "Specified compiler '$FORTRAN' not found in PATH"
        fi
        # Verify it actually runs
        if ! "$FORTRAN" --version > /dev/null 2>&1; then
            error "Specified compiler '$FORTRAN' found in PATH but not functional. For Intel compilers, ensure you have sourced /opt/intel/oneapi/setvars.sh"
        fi
        info "Using user-specified compiler: $FORTRAN"
        return
    fi

    # Auto-detect: prefer gfortran, then ifort, then ifx
    for candidate in gfortran ifort ifx; do
        if command -v "$candidate" > /dev/null 2>&1; then
            # Verify the compiler actually runs
            if "$candidate" --version > /dev/null 2>&1; then
                FORTRAN="$candidate"
                info "Auto-detected compiler: $FORTRAN"
                return
            else
                warn "'$candidate' found in PATH but not functional — skipping"
            fi
        fi
    done

    error "No Fortran compiler found. Install gfortran or use --compiler=<path>"
}

# ============================================================
# Detect compiler version (for logging/diagnostics)
# ============================================================
detect_compiler_version() {
    case "$FORTRAN" in
        gfortran*|ifort*|ifx*)
            COMPILER_VERSION=$("$FORTRAN" --version 2>&1 | head -1)
            ;;
        *)
            COMPILER_VERSION="unknown"
            ;;
    esac
    info "Compiler version: $COMPILER_VERSION"
}

# ============================================================
# Set compiler flags
# The -c flag compiles without linking (library only).
#
# Priority:
#   --fflags-lib / --fflags-drivers override --fflags for their target.
#   --fflags sets a common base for both.
#   If none specified, defaults are chosen per compiler.
# ============================================================
set_fflags() {
    # Determine base flags (used when specific flags are not provided)
    BASE_FFLAGS=""
    if [ -n "$FFLAGS" ]; then
        BASE_FFLAGS="$FFLAGS"
    else
        case "$FORTRAN" in
            gfortran*)
                BASE_FFLAGS="-O3"
                ;;
            ifort*)
                BASE_FFLAGS="-O3"
                ;;
            ifx*)
                BASE_FFLAGS="-O3"
                ;;
            *)
                warn "Unknown compiler '$FORTRAN' — using generic flags"
                BASE_FFLAGS="-O3"
                ;;
        esac
    fi

    # Set library flags: user-specific override, or base + "-c"
    if [ -n "$FFLAGS_LIB_USER" ]; then
        FFLAGS_LIB="$FFLAGS_LIB_USER"
    else
        FFLAGS_LIB="${BASE_FFLAGS} -c"
    fi

    # Set driver flags: user-specific override, or base (no -c)
    if [ -n "$FFLAGS_DRIVERS_USER" ]; then
        FFLAGS_DRIVERS="$FFLAGS_DRIVERS_USER"
    else
        FFLAGS_DRIVERS="$BASE_FFLAGS"
    fi

    info "FFLAGS_LIB: $FFLAGS_LIB"
    info "FFLAGS_DRIVERS: $FFLAGS_DRIVERS"
}

# ============================================================
# Detect C preprocessor
# ============================================================
detect_precomp() {
    if [ -n "$PRECOMP" ]; then
        if ! command -v "$PRECOMP" > /dev/null 2>&1; then
            error "Specified preprocessor '$PRECOMP' not found"
        fi
        info "Using user-specified preprocessor: $PRECOMP"
        return
    fi

    # Auto-detect cpp location
    for candidate in /usr/bin/cpp /usr/local/bin/cpp cpp; do
        if command -v "$candidate" > /dev/null 2>&1; then
            PRECOMP="$candidate"
            info "Auto-detected preprocessor: $PRECOMP"
            return
        fi
    done

    warn "No C preprocessor found. .F files may not build correctly."
    PRECOMP="cpp"
}

# ============================================================
# Backup existing @make files
# ============================================================
backup_make() {
    for makefile in "$SWIFT_DIR/@make_libswift" "$SWIFT_DIR/@make_drivers"; do
        if [ -f "$makefile" ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            date_str=$(date)
            backup="${makefile}.backup.${timestamp}"

            # Build the backup file explicitly using a temporary file
            tmpfile=$(mktemp)

            # Write shebang
            head -1 "$makefile" > "$tmpfile"

            # Write empty line after shebang
            echo "" >> "$tmpfile"

            # Write backup header
            echo "# Backup of $(basename "$makefile"), generated on ${date_str}." >> "$tmpfile"
            echo "#" >> "$tmpfile"
            echo "# Original $(basename "$makefile") content below:" >> "$tmpfile"
            echo "# --------------------------------" >> "$tmpfile"

            # Write the rest of the original file (skip the shebang line)
            tail -n +2 "$makefile" >> "$tmpfile"

            mv "$tmpfile" "$backup"
            info "Backed up $(basename "$makefile") to $backup"
        fi
    done
}

# ============================================================
# Generate @make_libswift from template
# ============================================================
generate_make_libswift() {
    template="$SWIFT_DIR/@make_libswift.template"
    target="$SWIFT_DIR/@make_libswift"

    if [ ! -f "$template" ]; then
        error "Template file not found: $template"
    fi

    date_str=$(date)

    # Generate @make_libswift from template with placeholder replacement
    sed \
        -e "s|__SWIFT_DIR__|${SWIFT_DIR}|g" \
        -e "s|__FORTRAN__|${FORTRAN}|g" \
        -e "s|__FFLAGS__|${FFLAGS_LIB}|g" \
        -e "s|__PRECOMP__|${PRECOMP}|g" \
        -e "s|__CPPFLAGS__|${CPPFLAGS}|g" \
        "$template" > "$target"

    # Replace the template comment with generated-file comments
    if [ "$OS" = "macos" ]; then
        sed -i '' \
            -e "s|^# @make_libswift template — used internally by setup.sh to generate @make_libswift|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    else
        sed -i \
            -e "s|^# @make_libswift template — used internally by setup.sh to generate @make_libswift|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    fi

    chmod +x "$target"
    info "Generated @make_libswift from template"
}

# ============================================================
# Generate @make_drivers from template
# ============================================================
generate_make_drivers() {
    template="$SWIFT_DIR/@make_drivers.template"
    target="$SWIFT_DIR/@make_drivers"

    if [ ! -f "$template" ]; then
        error "Template file not found: $template"
    fi

    date_str=$(date)

    # Generate @make_drivers from template with placeholder replacement
    sed \
        -e "s|__SWIFT_DIR__|${SWIFT_DIR}|g" \
        -e "s|__FORTRAN__|${FORTRAN}|g" \
        -e "s|__FFLAGS__|${FFLAGS_DRIVERS}|g" \
        "$template" > "$target"

    # Replace the template comment with generated-file comments
    if [ "$OS" = "macos" ]; then
        sed -i '' \
            -e "s|^# @make_drivers template — used internally by setup.sh to generate @make_drivers|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    else
        sed -i \
            -e "s|^# @make_drivers template — used internally by setup.sh to generate @make_drivers|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    fi

    chmod +x "$target"
    info "Generated @make_drivers from template"
}

# ============================================================
# Clean (optional)
# ============================================================
do_clean() {
    if [ "$DO_CLEAN" -eq 1 ]; then
        info "Cleaning..."
        rm -f "$SWIFT_DIR/libswift.a"
        find "$SWIFT_DIR" -name "*.o" -delete
        find "$SWIFT_DIR" -name "*CPP.f" -delete
        # Remove driver executables
        if [ -d "$SWIFT_DIR/main" ]; then
            for f in "$SWIFT_DIR"/main/swift_*; do
                case "$f" in
                    *.f|*.F|*.o) ;;
                    *) [ -f "$f" ] && [ -x "$f" ] && rm -f "$f" ;;
                esac
            done
        fi
        info "Clean complete"
    fi
}

# ============================================================
# Build library
# ============================================================
do_build_lib() {
    if [ "$DO_BUILD_LIB" -eq 1 ]; then
        info "Building library..."
        cd "$SWIFT_DIR" || error "Cannot cd to $SWIFT_DIR"

        if ! command -v csh > /dev/null 2>&1; then
            error "csh is not installed."
        fi

        csh -f "@makeall_libswift"
        status=$?

        if [ $status -eq 0 ]; then
            if [ -f "$SWIFT_DIR/libswift.a" ]; then
                info "Library created: $SWIFT_DIR/libswift.a"
                ls -lh "$SWIFT_DIR/libswift.a"
            else
                warn "Build finished but libswift.a was not created"
            fi
        else
            error "Library build failed with exit code $status"
        fi
    fi
}

# ============================================================
# Build drivers
# ============================================================
do_build_drivers() {
    if [ "$DO_BUILD_DRIVERS" -eq 1 ]; then
        info "Building drivers..."

        if [ ! -f "$SWIFT_DIR/libswift.a" ]; then
            error "libswift.a not found. Build the library first (--build-lib or --build)"
        fi

        cd "$SWIFT_DIR/main" || error "Cannot cd to $SWIFT_DIR/main"

        if ! command -v csh > /dev/null 2>&1; then
            error "csh is not installed."
        fi

        csh -f "$SWIFT_DIR/@make_drivers"
        status=$?

        if [ $status -eq 0 ]; then
            info "Drivers built successfully"
        else
            error "Driver build failed with exit code $status"
        fi
    fi
}

# ============================================================
# Print summary
# ============================================================
print_summary() {
    echo ""
    echo "========================================"
    echo "  Swift N-body Integrator Configuration"
    echo "========================================"
    echo "  OS:              $OS"
    echo "  SWIFT_DIR:       $SWIFT_DIR"
    echo "  FORTRAN:         $FORTRAN"
    echo "  FFLAGS_LIB:      $FFLAGS_LIB"
    echo "  FFLAGS_DRIVERS:  $FFLAGS_DRIVERS"
    echo "  PRECOMP:         $PRECOMP"
    echo "  CPPFLAGS:        $CPPFLAGS"
    echo "========================================"
    echo ""
    if [ "$DO_BUILD_LIB" -eq 0 ] && [ "$DO_BUILD_DRIVERS" -eq 0 ]; then
        echo "To build all:      ./setup.sh --build"
        echo "To build library:  ./setup.sh --build-lib"
        echo "To build drivers:  ./setup.sh --build-drivers"
        echo ""
        echo "Or manually:"
        echo "  cd $SWIFT_DIR && csh -f @makeall_libswift"
        echo "  cd $SWIFT_DIR/main && csh -f $SWIFT_DIR/@make_drivers"
    fi
}

# ============================================================
# Main
# ============================================================
main() {
    echo "========================================"
    echo "  setup.sh — Swift Build Configuration"
    echo "========================================"
    echo ""

    detect_os
    set_swift_dir
    detect_compiler
    detect_compiler_version
    set_fflags
    detect_precomp

    backup_make
    generate_make_libswift
    generate_make_drivers

    do_clean
    do_build_lib
    do_build_drivers

    print_summary
}

main "$@"
