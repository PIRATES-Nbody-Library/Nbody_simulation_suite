#!/bin/bash
#
# setup.sh — Configuration and build script for Swift N-body integrator
# Create @make from @make.template with paths and compiler options, then
# optionally runs @makeall to build libswift.a archive.
#
# Usage:
#   ./setup.sh [options]
#
# Options:
#   --compiler=COMPILER    Fortran compiler (default: auto-detect)
#   --fflags=FLAGS         Compiler flags (default: set per compiler)
#   --cppflags=FLAGS       Preprocessor flags (default: '-D_OPEN_POSITION -D_RECUR_SUB')
#   --precomp=PATH         Preprocessor path (default: auto-detect cpp)
#   --swift-dir=PATH       Swift root directory (default: ./swift_pirates)
#   --build                Run @makeall after configuration
#   --clean                Remove libswift.a and all .o files before building
#   --help                 Show this help message
#

# ============================================================
# Default values
# ============================================================
SWIFT_DIR=""
FORTRAN=""
FFLAGS=""
CPPFLAGS="-D_OPEN_POSITION -D_RECUR_SUB"
PRECOMP=""
DO_BUILD=0
DO_CLEAN=0
OS=""

# ============================================================
# Parse command-line arguments
# ============================================================
print_help() {
    sed -n '/^# Usage:/,/^#$/p' "$0" | sed 's/^# \?//'
    echo ""
    echo "Examples:"
    echo "  ./setup.sh                           # Auto-detect everything"
    echo "  ./setup.sh --compiler=gfortran       # Use gfortran as Fortran compiler"
    echo "  ./setup.sh --compiler=ifort --build  # Use ifort as Fortran compiler and build"
    echo "  ./setup.sh --fflags='-O2 -g -c'      # Custom compiler flags"
}

for arg in "$@"; do
    case "$arg" in
        --compiler=*)
            FORTRAN="${arg#*=}"
            ;;
        --fflags=*)
            FFLAGS="${arg#*=}"
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
            DO_BUILD=1
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
        # setup.sh is at the project root; swift/ is a subdirectory
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        SWIFT_DIR="${SCRIPT_DIR}/swift_pirates"
    fi

    # Verify it looks like a Swift source tree
    if [ ! -f "$SWIFT_DIR/@makeall" ]; then
        error "Cannot find @makeall in $SWIFT_DIR — is the swift/ folder present?"
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
# Set compiler flags (if not specified by user)
# ============================================================
set_fflags() {
    if [ -n "$FFLAGS" ]; then
        info "Using user-specified FFLAGS: $FFLAGS"
        return
    fi

    case "$FORTRAN" in
        gfortran*)
            FFLAGS="-O3 -c"
            ;;
        ifort*)
            FFLAGS="-O3 -c"
            ;;
        ifx*)
            FFLAGS="-O3 -c"
            ;;
        *)
            warn "Unknown compiler '$FORTRAN' — using generic flags"
            FFLAGS="-O3 -c"
            ;;
    esac
    info "FFLAGS: $FFLAGS"
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
# Backup existing @make
# ============================================================
backup_make() {
    local makefile="$SWIFT_DIR/@make"
    if [ -f "$makefile" ]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local date_str
        date_str=$(date)
        local backup="${makefile}.backup.${timestamp}"

        # Build the backup file explicitly using a temporary file
        local tmpfile
        tmpfile=$(mktemp)

        # Write shebang
        head -1 "$makefile" > "$tmpfile"
        # Write empty line after shebang
        echo "" >> "$tmpfile"
        # Write backup header
        echo "# Backup of @make, generated on ${date_str}." >> "$tmpfile"
        echo "#" >> "$tmpfile"
        echo "# Original @make content below:" >> "$tmpfile"
        echo "# --------------------------------" >> "$tmpfile"
        # Write the rest of the original file (skip the shebang line)
        tail -n +2 "$makefile" >> "$tmpfile"

        mv "$tmpfile" "$backup"
        info "Backed up @make to $backup"
    fi
}

# ============================================================
# Generate @make from template
# ============================================================
generate_make() {
    local template="$SWIFT_DIR/@make.template"
    local target="$SWIFT_DIR/@make"

    if [ ! -f "$template" ]; then
        error "Template file not found: $template"
    fi

    local date_str
    date_str=$(date)

    # Generate @make from template with placeholder replacement
    sed \
        -e "s|__SWIFT_DIR__|${SWIFT_DIR}|g" \
        -e "s|__FORTRAN__|${FORTRAN}|g" \
        -e "s|__FFLAGS__|${FFLAGS}|g" \
        -e "s|__PRECOMP__|${PRECOMP}|g" \
        -e "s|__CPPFLAGS__|${CPPFLAGS}|g" \
        "$template" > "$target"

    # Replace the template comment with generated-file comments
    if [ "$OS" = "macos" ]; then
        sed -i '' \
            -e "s|^# @make template — used internally by setup.sh to generate @make|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    else
        sed -i \
            -e "s|^# @make template — used internally by setup.sh to generate @make|# Generated by ../setup.sh.\n# Generated on: ${date_str}|" \
            "$target"
    fi

    chmod +x "$target"
    info "Generated @make from template"
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
        info "Clean complete"
    fi
}

# ============================================================
# Build (optional)
# ============================================================
do_build() {
    if [ "$DO_BUILD" -eq 1 ]; then
        info "Starting build..."
        cd "$SWIFT_DIR" || error "Cannot cd to $SWIFT_DIR"

        if ! command -v csh > /dev/null 2>&1; then
            error "csh is not installed."
        fi

        csh -f "@makeall"
        local status=$?

        if [ $status -eq 0 ]; then
            info "Build complete"
            if [ -f "$SWIFT_DIR/libswift.a" ]; then
                info "Library created: $SWIFT_DIR/libswift.a"
                ls -lh "$SWIFT_DIR/libswift.a"
            else
                warn "Build finished but libswift.a was not created"
            fi
        else
            error "Build failed with exit code $status"
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
    echo "  OS:          $OS"
    echo "  SWIFT_DIR:   $SWIFT_DIR"
    echo "  FORTRAN:     $FORTRAN"
    echo "  FFLAGS:      $FFLAGS"
    echo "  PRECOMP:     $PRECOMP"
    echo "  CPPFLAGS:    $CPPFLAGS"
    echo "========================================"
    echo ""
    if [ "$DO_BUILD" -eq 0 ]; then
        echo "To build, run:  ./setup.sh --build"
        echo "Or manually:    cd $SWIFT_DIR && csh -f @makeall"
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
    generate_make

    do_clean
    do_build

    print_summary
}

main "$@"
