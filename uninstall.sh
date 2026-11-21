#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only

# Removes only what install.sh recorded in its manifest.
# Anything that existed before installation is left untouched.

set -u

STATE_DIR="$HOME/.local/state/screen-spawner"
MANIFEST="$STATE_DIR/installed.list"
BACKUP_DIR="$STATE_DIR/backup"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_PATCH="$SCRIPT_DIR/patches/evdi-fix.patch"

echo "=== Screen Spawner uninstall ==="

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
KEPT_IN_USE=()

keep() {
    REMAINING+=("$1"$'\t'"$2")
    FAILED=1
}

# ------------------------------------------------------------
# 1. Read manifest (newest entries first)
# ------------------------------------------------------------

APT_ENTRIES=()
SYS_ENTRIES=()     # Fedora (dnf) and Arch Linux (pacman) packages
SYS_PM=
OTHER_ENTRIES=()

while IFS=$'\t' read -r type value; do
    [ -z "$type" ] && continue

    case "$type" in
        apt) APT_ENTRIES+=("$value") ;;
        dnf|pacman) SYS_ENTRIES+=("$value"); SYS_PM="$type" ;;
        *)   OTHER_ENTRIES+=("$type"$'\t'"$value") ;;
    esac
done < <(tac "$MANIFEST")

# ------------------------------------------------------------
# 2. Confirm
# ------------------------------------------------------------

# install.sh cannot know whether its tools were used for other work
# later, so show the ones people commonly use and let them decide.
TOOLS=()
for pkg in "${APT_ENTRIES[@]}" "${SYS_ENTRIES[@]}"; do
    case "${pkg%%:*}" in
        gcc-13|g++-13|git|curl|wget|ninja-build|vainfo|libva-utils|base-devel) TOOLS+=("${pkg%%:*}") ;;
    esac
done

echo
echo "This removes everything install.sh installed:"
if [ -n "$SYS_PM" ]; then
    echo "  ${#SYS_ENTRIES[@]} $SYS_PM packages${TOOLS[*]:+, including ${TOOLS[*]}}"
else
    echo "  ${#APT_ENTRIES[@]} apt packages${TOOLS[*]:+, including ${TOOLS[*]}}"
fi
for entry in "${OTHER_ENTRIES[@]}"; do
    value="${entry#*$'\t'}"
    case "${entry%%$'\t'*}" in
        snap) echo "  $value (snap)" ;;
        ppa)  echo "  repository ppa:$value" ;;
        node) echo "  Node.js $value (kept if it has your own global npm packages)" ;;
        nvm)  echo "  NVM in $value (kept if it has other Node.js versions)" ;;
        dir)  echo "  $value" ;;
    esac
done
echo
echo "If you use any of these for your own work, answer N and remove"
echo "the rest by hand."

ANSWER=""
if ! read -r -p "Continue? [Y/n] " ANSWER; then
    echo
    echo "Nothing was removed."
    exit 0
fi

case "$ANSWER" in
    ""|y|Y|yes|YES) ;;
    *) echo "Nothing was removed."; exit 0 ;;
esac

# ------------------------------------------------------------
# 3. Stop Hermes
# ------------------------------------------------------------

echo
echo "=== Stopping Hermes ==="

# The Screen Spawner app first: on SIGTERM it stops Hermes properly and quits.
# Matched by its installed path only, as the command it runs under.
APP_BIN="$HOME/.local/share/screen-spawner/app/screen-spawner"
if pkill -TERM -u "$USER" -f "^python3 $APP_BIN( |$)" 2>/dev/null; then
    for _ in $(seq 1 20); do
        pgrep -u "$USER" -f "^python3 $APP_BIN( |$)" >/dev/null 2>&1 || break
        sleep 0.5
    done
fi

# The app's "open at login" entry, made by the app itself, not by install.sh.
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/autostart/screen-spawner.desktop"

# Anchored to the start of the command line, so it matches only the
# Hermes binary itself, not shells or editors that mention its path.
pkill -TERM -f '^([^ ]*/)?(build/)?sunshine(-[0-9][[:alnum:]_.+~-]*)?( |$)' 2>/dev/null || true
sleep 1

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
# 4a. Remove Fedora (dnf) or Arch Linux (pacman) packages
# ------------------------------------------------------------
# Only the packages install.sh asked for are recorded; dnf and pacman remove
# the dependencies they pulled in with them, when nothing else needs those.
# A package that something not installed by install.sh still needs stays.

if [ ${#SYS_ENTRIES[@]} -gt 0 ]; then
    echo
    echo "=== Removing $SYS_PM packages installed by install.sh ==="
    PKGS=()
    for pkg in "${SYS_ENTRIES[@]}"; do
        if [ "$SYS_PM" = dnf ]; then
            rpm -q "$pkg" >/dev/null 2>&1 && PKGS+=("$pkg")
        else
            pacman -Q "$pkg" >/dev/null 2>&1 && PKGS+=("$pkg")
        fi
    done
    if [ ${#PKGS[@]} -eq 0 ]; then
        echo "No recorded $SYS_PM packages are installed."
    else
        echo "Packages to remove:"
        printf '  %s\n' "${PKGS[@]}"
        # Leave out what other installed packages still need, repeating until
        # the rest can go together.
        while [ ${#PKGS[@]} -gt 0 ]; do
            HELD=()
            if [ "$SYS_PM" = dnf ]; then
                CHECK="$(rpm -e --test "${PKGS[@]}" 2>&1)" || true
                while IFS= read -r cap; do
                    [ -n "$cap" ] || continue
                    HELD+=("$(rpm -q --qf '%{NAME}\n' --whatprovides "$cap" 2>/dev/null | head -n 1)")
                done < <(printf '%s\n' "$CHECK" | sed -n 's/^[[:space:]]*\(.*\) is needed by (installed) .*/\1/p' | sort -u)
            else
                CHECK="$(pacman -Rs --print "${PKGS[@]}" 2>&1)" || true
                mapfile -t HELD < <(printf '%s\n' "$CHECK" | sed -n 's/.*removing \([^ ]*\) breaks dependency.*/\1/p' | sort -u)
            fi
            [ ${#HELD[@]} -gt 0 ] || break
            REST=()
            for pkg in "${PKGS[@]}"; do
                if printf '%s\n' "${HELD[@]}" | grep -qxF "$pkg"; then
                    echo "Keeping $pkg: other installed packages need it."
                    KEPT_IN_USE+=("$pkg")
                else
                    REST+=("$pkg")
                fi
            done
            # Nothing left out: stop rather than loop; removal then reports why.
            [ ${#REST[@]} -lt ${#PKGS[@]} ] || break
            PKGS=("${REST[@]}")
        done
        if [ ${#PKGS[@]} -gt 0 ]; then
            if [ "$SYS_PM" = dnf ]; then
                sudo dnf remove -y "${PKGS[@]}" && REMOVED=1 || REMOVED=0
            else
                sudo pacman -Rns --noconfirm "${PKGS[@]}" && REMOVED=1 || REMOVED=0
            fi
            if [ "$REMOVED" -eq 1 ]; then
                echo "$SYS_PM packages removed."
            else
                echo "$SYS_PM packages were NOT removed. They stay in the manifest."
                for pkg in "${PKGS[@]}"; do keep "$SYS_PM" "$pkg"; done
            fi
        fi
    fi
fi

# ------------------------------------------------------------
# 4. Remove apt packages
# ------------------------------------------------------------

KEPT_SYSTEM=()
if [ ${#APT_ENTRIES[@]} -gt 0 ]; then
echo
echo "=== Removing apt packages installed by install.sh ==="

ARCH="$(dpkg --print-architecture)"

# libfoo:amd64 -> libfoo (native architecture only)
normalize() {
    sed "s/:$ARCH\$//"
}

# A dependency transaction can introduce a package marked Essential or Protected (for
# example systemd-sysv on minimal Debian 13). Never purge those packages or
# anything they require, even when they appear in an older install manifest.
mapfile -t ESSENTIAL < <(
    dpkg-query -W -f='${db:Status-Abbrev} ${binary:Package} ${Essential} ${Protected}\n' 2>/dev/null \
        | awk '$1 ~ /^ii/ && ($3 == "yes" || $4 == "yes") { print $2 }'
)
PROTECTED="$(
    if [ ${#ESSENTIAL[@]} -gt 0 ]; then
        apt-cache depends --recurse --installed \
            --no-recommends --no-suggests --no-conflicts \
            --no-breaks --no-replaces --no-enhances \
            "${ESSENTIAL[@]}" 2>/dev/null \
            | awk '/^[^[:space:]<]/ {print $1}'
        printf '%s\n' "${ESSENTIAL[@]}"
    fi
)"
PROTECTED="$(printf '%s\n' "$PROTECTED" | normalize | sort -u)"
PKGS=()

for pkg in "${APT_ENTRIES[@]}"; do
    if dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null | grep -q '^ii'; then
        if printf '%s\n' "$PROTECTED" | grep -qxF "$(printf '%s\n' "$pkg" | normalize)"; then
            echo "Keeping a system requirement: $pkg"
            KEPT_SYSTEM+=("$pkg")
        else
            PKGS+=("$pkg")
        fi
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
fi # apt packages

# ------------------------------------------------------------
# 5. Remove everything else (newest first)
# ------------------------------------------------------------

echo
echo "=== Removing files, snaps, repositories and Node.js ==="

PPA_REMOVED=0
KEEP_NVM=0

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

        # Node.js and NVM that were used for other work since are no
        # longer ours: they are left in place and dropped from the manifest.
        node)
            OWN_GLOBALS="$(ls "$HOME/.nvm/versions/node/v$value".*/lib/node_modules 2>/dev/null |
                grep -vxE 'npm|corepack|' | tr '\n' ' ')"
            if [ -n "$OWN_GLOBALS" ]; then
                echo "Keeping Node.js $value: it has global npm packages installed later: $OWN_GLOBALS"
                KEEP_NVM=1
                KEPT_IN_USE+=("Node.js $value")
            elif [ -s "$HOME/.nvm/nvm.sh" ]; then
                echo "Removing Node.js $value from NVM"
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
            OTHER_NODES="$(ls "$value/versions/node" 2>/dev/null | tr '\n' ' ')"
            if [ "$KEEP_NVM" -eq 1 ] || [ -n "$OTHER_NODES" ]; then
                echo "Keeping NVM: it still has Node.js versions in use: ${OTHER_NODES:-$value}"
                KEPT_IN_USE+=("NVM")
            elif [ "$value" = "$HOME/.nvm" ]; then
                echo "Removing NVM: $value"
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
                ""|"/"|"$HOME"|"$HOME/"|"$HOME/.config"|"$HOME/.config/"|\
                "$HOME/.config/hermes"|"$HOME/.config/hermes/")
                    # Hermes settings and paired devices always stay, even if
                    # an early installer recorded their folder.
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

        rpmkey)
            # The signing key of a repository install.sh added (Fedora)
            if rpm -q "$value" >/dev/null 2>&1; then
                echo "Removing repository key: $value"
                # Newer rpm deletes keys by fingerprint; the package name holds it.
                fingerprint="${value#gpg-pubkey-}"
                fingerprint="${fingerprint%-*}"
                if rpmkeys --help 2>/dev/null | grep -q -- '--delete'; then
                    sudo rpmkeys --delete "$fingerprint" || keep "$type" "$value"
                else
                    sudo rpm -e "$value" || keep "$type" "$value"
                fi
            fi
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

# Another program may have made an icon cache in ~/.local/share/icons while
# the app's icons were there. Left as it is, it still lists the removed
# icons, and a Screen Spawner installed later as a package shows an empty
# icon. Rebuild it without them.
USER_ICON_CACHE="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/icon-theme.cache"
if [ -f "$USER_ICON_CACHE" ] && command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -q -t "$(dirname "$USER_ICON_CACHE")" || true
fi

# ------------------------------------------------------------
# 6. Update manifest
# ------------------------------------------------------------

echo

if [ ${#REMAINING[@]} -eq 0 ]; then
    rm -f "$MANIFEST"
    rm -rf "$BACKUP_DIR"
    # The app's own journal (see app/screen-spawner, log())
    rm -f "$STATE_DIR/app.log" "$STATE_DIR/app.log.old"
    rmdir "$STATE_DIR" 2>/dev/null || true

    echo "=== Uninstall completed ==="
    echo "All recorded items were removed or retained as system requirements."
    if [ ${#KEPT_SYSTEM[@]} -gt 0 ]; then
        echo "Kept for essential/protected system packages: ${KEPT_SYSTEM[*]}"
    fi
    if [ ${#KEPT_IN_USE[@]} -gt 0 ]; then
        echo "Kept because you use them: ${KEPT_IN_USE[*]}"
    fi
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
