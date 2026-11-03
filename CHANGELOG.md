# Changelog

All notable changes to this maintained fork of
[zmscode/sdl3-zig](https://github.com/zmscode/sdl3-zig)
will be documented in this file.

This project uses Semantic Versioning for its Zig bindings.
The Zig package version is independent of the bundled SDL version.

## [Unreleased]

### Added
- Cross-platform CI for Windows and Linux.
- Separate macOS compatibility workflow.
- Path-based CI execution filters.

### Changed
- Updated bundled SDL from 3.4.14 to 3.4.18.
- Updated minimum supported Zig version to 0.17.0.
- Updated README and SKILL.md for the maintained fork.

### Fixed
- Fixed Windows command-line argument parsing in examples
  for Zig 0.17.
- Avoided fullscreen mode enumeration crashes with the SDL
  dummy video driver.

## Release policy

- Patch releases (`0.x.Y`) contain bug fixes and compatible
  improvements.
- Minor releases (`0.X.0`) may introduce new features or API
  changes while the library is pre-1.0.
- Prerelease versions (`-dev.N`, `-rc.N`) are used for
  development and release testing.
- Every published release documents its tested Zig and SDL
  versions.
