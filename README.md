# N-body simulation suite

This suite contains a modified version of the SWIFT simulation suite, stored
in the folder `swift_pirates`, along with utility scripts for compilation.

## Installation

### Clone from GitHub
```
git clone git@github.com:PIRATES-Nbody-Library/Nbody_simulation_suite.git
```

### Compile the SWIFT library

Requirements:
* A Fortran compiler such as `gfortran`, `ifort`, or `ifx`.
* the `cpp` C preprocessor

Compilation is handled via the `setup.sh` script. Run it via
```
./setup.sh
```
to create makefiles in the location of SWIFT for compilation. The script
autodetects the operating system, Fortran compiler, and C preprocessor, uses
the standard path to the SWIFT library contained in this repository (called
`swift_pirates` to distinguish from the origional SWIFT), and uses the compiler
options `-O3 -frecursive`. All of these settings can be adjusted via options of
`setup.sh`. To display them and some examples for usage, execute
```
./setup.sh --help
```

Compile SWIFT via
```
./setup.sh --build
```
Add the `--debug` option to compile with debug compiler flags or the `--clean`
option (also standalone) to remove existing build products.

## Status

This repository is in early development.

## References

The original SWIFT by [Levison and Duncan 1994](https://www.sciencedirect.com/science/article/pii/S0019103584710396)
can be found [here](https://www2.boulder.swri.edu/~hal/swift.html)
or [here](https://ascl.net/1303.001).
