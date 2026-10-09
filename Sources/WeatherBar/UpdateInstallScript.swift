import Foundation

/// Builds the detached install/relaunch script used to swap the app bundle while
/// the running instance has exited. The script is fully self-contained and
/// cleans up its own staging directory.
///
/// Contract (validated by UpdateInstallScriptTests):
/// - waits for the old app PID to exit before touching the bundle
/// - stages the new bundle at `TARGET.new` and leaves the installed app
///   untouched if the copy fails (then relaunches the old app)
/// - swaps via a `TARGET.old` backup, rolling back if the swap fails
/// - removes the staging directory and relaunches the new app on success
enum UpdateInstallScript {
    /// - Parameters:
    ///   - openCommand: path to the relaunch command; overridable so tests can
    ///     substitute `/usr/bin/true` instead of launching Finder-registered apps.
    static func body(openCommand: String = "/usr/bin/open") -> String {
        """
        #!/bin/bash
        set -euo pipefail
        PID="$1"
        TARGET="$2"
        SOURCE="$3"
        STAGING="$4"
        OPEN_CMD="\(openCommand)"
        BACKUP="$TARGET.old.$$"
        SCRIPT_PATH="$0"

        # Wait for the running app to exit before touching its bundle.
        while kill -0 "$PID" 2>/dev/null; do
          sleep 0.2
        done

        # Stage the new bundle first: if the copy fails, the installed app stays
        # untouched and the old app is relaunched so the user is not stranded.
        if ! /usr/bin/ditto "$SOURCE" "$TARGET.new"; then
          rm -rf "$STAGING" "$TARGET.new" 2>/dev/null || true
          "$OPEN_CMD" "$TARGET" 2>/dev/null || true
          exit 1
        fi

        # Swap with a backup so a failed move can be rolled back.
        mv "$TARGET" "$BACKUP" 2>/dev/null || true
        if ! mv "$TARGET.new" "$TARGET"; then
          rm -rf "$TARGET" 2>/dev/null || true
          mv "$BACKUP" "$TARGET" 2>/dev/null || true
        fi
        rm -rf "$BACKUP" "$STAGING" 2>/dev/null || true

        "$OPEN_CMD" "$TARGET" 2>/dev/null || true
        rm -f "$SCRIPT_PATH"
        """
    }
}
