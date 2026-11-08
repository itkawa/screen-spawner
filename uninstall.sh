#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

# Removes only what install.sh recorded in its manifest.
# Anything that existed before installation is left untouched.

set -u

STATE_DIR="$HOME/.local/state/smart-device-display"
MANIFEST="$STATE_DIR/installed.list"
BACKUP_DIR="$STATE_DIR/backup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PATCH="$SCRIPT_DIR/patches/evdi-fix.patch"

echo "=== SmartDeviceDisplay uninstall ==="

if [ ! -s "$MANIFEST" ]; then
    echo "Install manifest not found or empty:"
    echo "$MANIFEST"
    echo
    echo "Nothing was removed."
    exit 0
fi

echo "Install manifest: $MANIFEST"

# Entries that could not be removed stay in the manifest
REMAINING=()
FAILED=0

keep() {
    REMAINING+=("$1"$'\t'"$2")
    FAILED=1
}

# ------------------------------------------------------------
# 1. Stop Hermes
# ------------------------------------------------------------

echo
echo "=== Stopping Hermes ==="

# Anchored to the start of the command line, so it matches only the
# Hermes binary itself, not shells or editors that mention its path.
pkill -TERM -f '^([^ ]*/)?build/sunshine(-[0-9.]+)?( |$)' 2>/dev/null || true
sleep 1

# ------------------------------------------------------------
# 2. Read manifest (newest entries first)
# ------------------------------------------------------------

APT_ENTRIES=()
OTHER_ENTRIES=()

while IFS=$'\t' read -r type value; do
    [ -z "$type" ] && continue

    case "$type" in
        apt) APT_ENTRIES+=("$value") ;;
        *)   OTHER_ENTRIES+=("$type"$'\t'"$value") ;;
    esac
done < <(tac "$MANIFEST")

# ------------------------------------------------------------
# 3. Unload kernel modules loaded by install.sh
# ------------------------------------------------------------

for entry in "${OTHER_ENTRIES[@]}"; do
    type="${entry%%$'\t'*}"
    value="${entry#*$'\t'}"

    if [ "$type" = "module" ]; then
        echo "Unloading kernel module: $value"
        sudo modprobe -r "$value" 2>/dev/null || true
    fi
done

# ------------------------------------------------------------
# 4. Remove apt packages
# ------------------------------------------------------------

echo
echo "=== Removing apt packages installed by install.sh ==="

ARCH="$(dpkg --print-architecture)"

# libfoo:amd64 -> libfoo (native architecture only)
normalize() {
    sed "s/:$ARCH\$//"
}

PKGS=()

for pkg in "${APT_ENTRIES[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
        PKGS+=("$pkg")
    fi
done

if [ ${#PKGS[@]} -eq 0 ]; then
    echo "No recorded apt packages are installed."
else
    echo "Packages to remove:"
    printf '  %s\n' "${PKGS[@]}"

    # Simulate first: if removing these packages would also remove
    # something that was NOT installed by install.sh, ask before continuing.
    SIMULATION="$(apt-get -s purge "${PKGS[@]}" 2>&1)"
    SIM_STATUS=$?

    EXTRA="$(
        comm -13 \
            <(printf '%s\n' "${PKGS[@]}" | normalize | sort -u) \
            <(printf '%s\n' "$SIMULATION" | awk '$1 == "Purg" || $1 == "Remv" { print $2 }' | normalize | sort -u)
    )"

    PROCEED=1

    if [ $SIM_STATUS -ne 0 ]; then
        echo
        echo "ERROR: apt simulation failed:"
        printf '%s\n' "$SIMULATION" | tail -5
        PROCEED=0

    elif [ -n "$EXTRA" ]; then
        echo
        echo "WARNING: removing these packages would ALSO remove packages"
        echo "that were NOT installed by install.sh:"
        printf '  %s\n' $EXTRA
        echo

        ANSWER=""
        if [ -t 0 ]; then
            read -r -p "Remove them too? [y/N] " ANSWER
        fi

        case "$ANSWER" in
            y|Y|yes|YES) ;;
            *) PROCEED=0 ;;
        esac
    fi

    if [ $PROCEED -eq 1 ] && sudo apt purge -y "${PKGS[@]}"; then
        echo "apt packages removed."
    else
        echo "apt packages were NOT removed. They stay in the manifest."
        for pkg in "${PKGS[@]}"; do
            keep apt "$pkg"
        done
    fi
fi

# ------------------------------------------------------------
# 5. Remove everything else (newest first)
# ------------------------------------------------------------

echo
echo "=== Removing files, snaps, repositories and Node.js ==="

PPA_REMOVED=0

for entry in "${OTHER_ENTRIES[@]}"; do
    type="${entry%%$'\t'*}"
    value="${entry#*$'\t'}"

    case "$type" in

        module)
            # Already handled in step 3
            ;;

        snap)
            echo "Removing snap: $value"
            if snap list "$value" >/dev/null 2>&1; then
                sudo snap remove "$value" || keep "$type" "$value"
            fi
            ;;

        ppa)
            echo "Removing PPA: $value"
            if sudo add-apt-repository --remove -y "ppa:$value"; then
                PPA_REMOVED=1
            else
                keep "$type" "$value"
            fi
            ;;

        node)
            echo "Removing Node.js $value from NVM"
            if [ -s "$HOME/.nvm/nvm.sh" ]; then
                (
                    set +u
                    export NVM_DIR="$HOME/.nvm"
                    . "$NVM_DIR/nvm.sh"
                    nvm deactivate >/dev/null 2>&1
                    nvm uninstall "$value"
                ) || keep "$type" "$value"
            fi
            ;;

        nvm)
            echo "Removing NVM: $value"
            if [ "$value" = "$HOME/.nvm" ]; then
                rm -rf "$value"

                if [ -f "$HOME/.bashrc" ]; then
                    sed -i '/NVM_DIR.*\.nvm/d' "$HOME/.bashrc"
                    sed -i '/nvm\.sh/d' "$HOME/.bashrc"
                    sed -i '/bash_completion.*nvm/d' "$HOME/.bashrc"
                fi
            else
                echo "  Unexpected NVM path, skipped."
                keep "$type" "$value"
            fi
            ;;

        dir)
            echo "Removing directory: $value"
            case "$value" in
                ""|"/"|"$HOME"|"$HOME/")
                    echo "  Refusing to remove this path, skipped."
                    keep "$type" "$value"
                    ;;
                *)
                    # install.sh applied the EVDI fix itself, so it is not
                    # local work and must not block the removal below
                    fix_reverted=0
                    if [ -d "$value/.git" ] &&
                       git -C "$value" apply --reverse --check "$HERMES_PATCH" 2>/dev/null &&
                       git -C "$value" apply --reverse "$HERMES_PATCH"; then
                        fix_reverted=1
                    fi

                    # Never delete a git checkout with local work in it
                    if [ -d "$value/.git" ] && {
                        [ -n "$(git -C "$value" status --porcelain 2>/dev/null)" ] ||
                        [ -n "$(git -C "$value" log --oneline '@{u}..' 2>/dev/null)" ] ||
                        [ -n "$(git -C "$value" stash list 2>/dev/null)" ]
                    }; then
                        echo "  Contains uncommitted or unpushed changes, skipped:"
                        git -C "$value" status --short | head -10 | sed 's/^/    /'
                        keep "$type" "$value"

                        # The checkout stays, so leave it as it was
                        if [ $fix_reverted -eq 1 ]; then
                            git -C "$value" apply "$HERMES_PATCH"
                        fi
                    else
                        rm -rf "$value"
                    fi
                    ;;
            esac
            ;;

        file)
            echo "Removing file: $value"
            rm -f "$value"
            ;;

        rootfile)
            echo "Removing file: $value"
            sudo rm -f "$value"
            ;;

        rootdir)
            # Removed only if empty: other software may have put files there
            if [ -d "$value" ]; then
                echo "Removing directory if empty: $value"
                sudo rmdir --ignore-fail-on-non-empty "$value"
            fi
            ;;

        line)
            # value: <file><TAB><exact line that was added>
            target="${value%%$'\t'*}"
            text="${value#*$'\t'}"

            echo "Removing line \"$text\" from $target"
            if [ -f "$target" ] && grep -qxF "$text" "$target"; then
                tmp="$(mktemp)"
                grep -vxF "$text" "$target" > "$tmp"
                sudo cp "$tmp" "$target" || keep "$type" "$value"
                rm -f "$tmp"
            fi
            ;;

        restore)
            echo "Restoring original file: $value"
            if [ -f "$BACKUP_DIR$value" ]; then
                sudo cp -p "$BACKUP_DIR$value" "$value" || keep "$type" "$value"
            else
                echo "  Backup not found, skipped."
                keep "$type" "$value"
            fi
            ;;

        *)
            echo "Unknown manifest entry, skipped: $type $value"
            keep "$type" "$value"
            ;;
    esac
done

if [ $PPA_REMOVED -eq 1 ]; then
    sudo apt update
fi

# ------------------------------------------------------------
# 6. Update manifest
# ------------------------------------------------------------

echo

if [ ${#REMAINING[@]} -eq 0 ]; then
    rm -f "$MANIFEST"
    rm -rf "$BACKUP_DIR"
    rmdir "$STATE_DIR" 2>/dev/null || true

    echo "=== Uninstall completed ==="
    echo "Everything recorded by install.sh was removed."
else
    # REMAINING is newest-first; write it back in original order
    printf '%s\n' "${REMAINING[@]}" | tac > "$MANIFEST"

    echo "=== Uninstall finished with skipped items ==="
    echo "Items that were not removed are still listed in:"
    echo "$MANIFEST"
    echo
    echo "Run uninstall.sh again after resolving the problems above."
fi

[ $FAILED -eq 0 ]
