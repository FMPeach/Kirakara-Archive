# VS Code repository-Engine examples

The repository intentionally ignores `.vscode/` so each developer can keep
local editor preferences. Merge the configurations in this directory into
the matching files below the repository's `.vscode/` directory.

Every Windows run and build entry calls the root `flutterw` wrapper. The Dart
extension's ordinary launch path must not replace these commands, because it
would bypass the project Engine fingerprint and ABI gates. Start the wrapper
launch first, then use the separate attach configuration when interactive Dart
debugging is required.
