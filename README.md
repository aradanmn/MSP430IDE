# MSP430 IDE

A native macOS IDE for the Texas Instruments MSP430 microcontroller family. Built in SwiftUI / AppKit, no Electron.

Status: early. Editor + build + flash work for C and assembly projects. Debugger and serial monitor are next.

## Requirements

- macOS 13+
- Swift toolchain (Command Line Tools is enough — full Xcode not required)
- [msp430-elf-gcc](https://www.ti.com/tool/MSP430-GCC-OPENSOURCE) (TI's tarball or Homebrew)
- [mspdebug](https://dlbeer.co.nz/mspdebug/) (`brew install mspdebug`)

The IDE auto-detects toolchains in `~/.local/msp430-gcc/bin`, `~/ti/msp430-gcc/bin`, `/opt/homebrew/bin`, and `/usr/local/bin`.

## Build & run

```sh
make run       # builds MSP430IDE.app and opens it
make app       # just build the .app
make clean
```

## Project format

Each project has an `msp430.toml` at its root. Two modes:

- `native` — the IDE drives `msp430-elf-gcc` / `mspdebug` directly using `[defaults]` + `[configs.*]`.
- `external` — the IDE shells out to user-provided commands (`make`, `make flash`, etc.). Use this for existing Makefile-based projects.

Workspace state (open files, active config) lives in `.msp430ide/workspace.json` and is gitignored by the template.

## Layout

```
Sources/MSP430IDE/
  MSP430IDEApp.swift       @main, scene + commands
  Models/                  ProjectModel, AppState, Toolchain, WorkspaceState
  Views/                   SwiftUI views (MainView, FileTree, CodeEditor, Console, Toolbar)
  Services/                Builder, ExternalBuilder, Flasher, ProcessRunner
  Syntax/                  C highlighter (assembly highlighter coming)
  TOML/                    Hand-rolled TOML parser (no external deps)
  Util/                    GlobMatcher
```

## CLI smoke tests

```sh
MSP430IDE_VALIDATE=path/to/project ./.build/release/MSP430IDE
MSP430IDE_BUILD=path/to/project MSP430IDE_CONFIG=Release ./.build/release/MSP430IDE
```
