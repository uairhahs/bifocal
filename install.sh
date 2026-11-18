#!/bin/bash
# install.sh: install or remove bifocal and bifocal-menu for the current user
#
# Usage:
#   ./install.sh                 install to ~/.local/bin (or $XDG_BIN_HOME)
#   ./install.sh --dir DIR       install to DIR instead
#   ./install.sh --uninstall     remove the scripts and the shortcut entry
#
# Installing also adds a "Bifocal" application entry that KDE can bind to a
# key (System Settings, Keyboard, Shortcuts). Nothing here needs root unless
# DIR is a system directory.

# shellcheck disable=SC2312
set -euo pipefail

SRC_DIR="$(dirname "$(readlink -f "$0")")"
BIN_DIR="${XDG_BIN_HOME:-${HOME}/.local/bin}"
APP_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/applications"
DESKTOP_FILE="${APP_DIR}/bifocal-menu.desktop"
SCRIPTS=(bifocal bifocal-menu)
ACTION=install

usage() {
	sed -n '2,11s/^# \{0,1\}//p' "$0"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--dir)
		[[ $# -ge 2 ]] || {
			echo "install.sh: --dir needs a directory" >&2
			exit 2
		}
		BIN_DIR="$2"
		shift 2
		;;
	--dir=*)
		BIN_DIR="${1#--dir=}"
		shift
		;;
	--uninstall)
		ACTION=uninstall
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "install.sh: unknown option: $1" >&2
		usage >&2
		exit 2
		;;
	esac
done

# Resolve to an absolute path (without following symlinks, so a BIN_DIR under
# $HOME keeps its $HOME prefix and the desktop entry can use ~)
if [[ ${ACTION} == install ]]; then
	mkdir -p "${BIN_DIR}"
fi
if [[ -d ${BIN_DIR} ]]; then
	BIN_DIR="$(cd "${BIN_DIR}" && pwd -L)"
fi

refresh_menu_cache() {
	if command -v kbuildsycoca6 >/dev/null 2>&1; then
		kbuildsycoca6 >/dev/null 2>&1 || true
	elif command -v kbuildsycoca5 >/dev/null 2>&1; then
		kbuildsycoca5 >/dev/null 2>&1 || true
	fi
}

# Quote a path for an Exec= key: wrap in double quotes, backslash-escape
# " ` $ \ inside them, then double every backslash for the desktop-entry string
desktop_exec_quote() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//\`/\\\`}"
	s="${s//\$/\\\$}"
	s="\"${s}\""
	printf '%s' "${s//\\/\\\\}"
}

# The Exec= value for a script: ~/... when it sits under $HOME and needs no
# quoting (KDE expands a leading ~), so the entry keeps working if the home
# directory moves; otherwise the quoted absolute path
desktop_exec_path() {
	local path="$1" rel
	if [[ ${path} == "${HOME}"/* ]]; then
		rel="${path#"${HOME}"/}"
		if [[ ${rel} =~ ^[A-Za-z0-9._/+-]+$ ]]; then
			# shellcheck disable=SC2088 # a literal ~ for KDE to expand, not the shell
			printf '~/%s' "${rel}"
			return
		fi
	fi
	desktop_exec_quote "${path}"
}

# Prints the key bound to the Bifocal entry, if any
bound_shortcut() {
	local key=""
	if command -v kreadconfig6 >/dev/null 2>&1; then
		key="$(kreadconfig6 --file kglobalshortcutsrc --group services \
			--group "$(basename "${DESKTOP_FILE}")" --key _launch 2>/dev/null || true)"
	fi
	if [[ -n ${key} && ${key} != none ]]; then
		printf '%s' "${key}"
	fi
}

do_install() {
	local script missing=()

	for script in "${SCRIPTS[@]}"; do
		if [[ ! -f "${SRC_DIR}/${script}" ]]; then
			echo "install.sh: ${SRC_DIR}/${script} not found" >&2
			exit 1
		fi
	done

	# bifocal-menu runs the bifocal next to it, so both go in the same directory
	install -D -m 755 -t "${BIN_DIR}" "${SCRIPTS[@]/#/${SRC_DIR}/}"
	echo "Installed ${SCRIPTS[*]} to ${BIN_DIR}"

	local exec_line old_exec="" key
	exec_line="Exec=$(desktop_exec_path "${BIN_DIR}/bifocal-menu")"
	if [[ -f ${DESKTOP_FILE} ]]; then
		old_exec="$(grep -m 1 '^Exec=' "${DESKTOP_FILE}" || true)"
	fi

	mkdir -p "${APP_DIR}"
	cat >"${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=Bifocal
Comment=Switch between laptop, external and extended display layouts
${exec_line}
Icon=video-display
Categories=Settings;HardwareSettings;
Keywords=display;monitor;screen;dock;
StartupNotify=false
X-KDE-GlobalAccel-CommandShortcut=true
EOF
	refresh_menu_cache
	echo "Wrote ${DESKTOP_FILE} (${exec_line})"

	key="$(bound_shortcut)"
	if [[ -n ${key} && -n ${old_exec} && ${old_exec} != "${exec_line}" ]]; then
		echo
		echo "Note: ${key} is bound to Bifocal and its command changed. KDE caches the"
		echo "old one until you log out and back in, or re-save the shortcut in"
		echo "System Settings."
	fi

	command -v kscreen-doctor >/dev/null 2>&1 || missing+=(kscreen-doctor)
	command -v notify-send >/dev/null 2>&1 || missing+=(notify-send)
	if ! command -v wofi >/dev/null 2>&1 && ! command -v rofi >/dev/null 2>&1; then
		missing+=("wofi (or rofi)")
	fi
	if [[ ${#missing[@]} -gt 0 ]]; then
		echo
		echo "Warning: missing dependencies: ${missing[*]}"
	fi

	case ":${PATH}:" in
	*":${BIN_DIR}:"*) ;;
	*)
		echo
		echo "Note: ${BIN_DIR} is not on your PATH, so 'bifocal' and 'bifocal-menu'"
		echo "will not run by name in a terminal. The shortcut entry still works."
		echo "To fix it, add this line to your shell's startup file (~/.bashrc, ~/.zshrc):"
		echo
		echo "    export PATH=\"${BIN_DIR}:\${PATH}\""
		;;
	esac

	if [[ -z ${key} ]]; then
		echo
		echo "To bind a key: System Settings, Keyboard, Shortcuts, then select"
		echo '"Bifocal" under Commands, choose Add and press the key.'
	fi
}

do_uninstall() {
	local script
	for script in "${SCRIPTS[@]}"; do
		if [[ -e "${BIN_DIR}/${script}" ]]; then
			rm -f "${BIN_DIR}/${script}"
			echo "Removed ${BIN_DIR}/${script}"
		fi
	done
	if [[ -e ${DESKTOP_FILE} ]]; then
		rm -f "${DESKTOP_FILE}"
		refresh_menu_cache
		echo "Removed ${DESKTOP_FILE}"
	fi
}

"do_${ACTION}"
