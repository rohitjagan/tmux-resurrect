#!/usr/bin/env bash
# Regression test: panes with an empty title must keep their directory through
# save and restore. Runs against a private tmux server (-L) and a temp
# resurrect dir, so it never touches the user's tmux. Needs only tmux and bash.
#
# Usage: tests/test_empty_pane_title.sh

set -u

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SOCKET="resurrect-empty-title-$$"
WORK_DIR="$(mktemp -d)"
failures=0

t() { tmux -L "$SOCKET" "$@"; }

cleanup() {
	t kill-server 2>/dev/null
	rm -rf "$WORK_DIR"
}
trap cleanup EXIT

check() {
	local description="$1" expected="$2" actual="$3"
	if [ "$expected" == "$actual" ]; then
		echo "ok   - $description"
	else
		echo "FAIL - $description"
		echo "       expected: $expected"
		echo "       actual:   $actual"
		failures=$((failures + 1))
	fi
}

pane_dirs() {
	t list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{pane_current_path} [#{pane_title}]' | sort
}

mkdir -p "$WORK_DIR/resurrect" "$WORK_DIR/dir one" "$WORK_DIR/dir two" "$WORK_DIR/dir three"
DIR_EMPTY="$(cd "$WORK_DIR/dir one" && pwd -P)"
DIR_TITLED="$(cd "$WORK_DIR/dir two" && pwd -P)"
DIR_SPACE_TITLE="$(cd "$WORK_DIR/dir three" && pwd -P)"

export HOME="$WORK_DIR"
t -f /dev/null new-session -d -s one -c "$DIR_EMPTY" "sleep 600"
t set-option -g @resurrect-dir "$WORK_DIR/resurrect"
t new-window -t one -c "$DIR_TITLED" "sleep 600"
t new-window -t one -c "$DIR_SPACE_TITLE" "sleep 600"
t select-pane -t one:0 -T ''
t select-pane -t one:1 -T 'my title'
t select-pane -t one:2 -T '  spaced  title'

before="$(pane_dirs)"
t run-shell "$ROOT_DIR/scripts/save.sh quiet"
save_file="$WORK_DIR/resurrect/last"

echo "# save"
check "save: every pane line has 11 tab-separated fields" "11 11 11" \
	"$(awk -F'\t' '/^pane/ { printf "%s%s", sep, NF; sep=" " }' "$save_file")"
check "save: directory is field 8 for the empty-title pane" ":${DIR_EMPTY// /\\ }" \
	"$(awk -F'\t' '/^pane/ && $3 == 0 { print $8 }' "$save_file")"
check "save: empty title stays empty (field 7)" "" \
	"$(awk -F'\t' '/^pane/ && $3 == 0 { print $7 }' "$save_file")"
check "save: pane_active is field 9" "1" \
	"$(awk -F'\t' '/^pane/ && $3 == 0 { print $9 }' "$save_file")"

echo "# restore"
t kill-server
t -f /dev/null new-session -d -s scratch
t set-option -g @resurrect-dir "$WORK_DIR/resurrect"
t run-shell "$ROOT_DIR/scripts/restore.sh"
sleep 1
after="$(pane_dirs | grep -v '^scratch')"
check "restore: panes come back in their saved directories and titles" "$before" "$after"

if [ "$failures" -ne 0 ]; then
	echo "$failures check(s) failed"
	exit 1
fi
echo "all checks passed"
