#!/bin/sh

set -eu
umask 077

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
helper="$repo_root/scripts/apple-companion-helper.sh"
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/media-control-relay-helper-check.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT HUP INT TERM

expect_status() {
	expected="$1"
	shift
	if "$@" >/dev/null 2>&1; then
		actual=0
	else
		actual="$?"
	fi
	[ "$actual" -eq "$expected" ] || {
		printf 'Expected status %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
		exit 1
	}
}

unsafe_root="$temporary_root/unsafe-remove"
mkdir -m 700 "$unsafe_root"
touch "$unsafe_root/preserve"
expect_status 2 "$helper" remove --root "$unsafe_root"
[ -f "$unsafe_root/preserve" ]

safe_root="$temporary_root/safe-remove"
mkdir -m 700 "$safe_root"
printf 'media-control-relay-apple-companion-helper-v1\n' \
	>"$safe_root/.media-control-relay-apple-companion-helper"
chmod 600 "$safe_root/.media-control-relay-apple-companion-helper"
"$helper" remove --root "$safe_root" >/dev/null
[ ! -e "$safe_root" ]

stale_lock_root="$temporary_root/stale-lock"
mkdir -m 700 "$stale_lock_root" "$stale_lock_root/.operation-lock"
printf '999999\n' >"$stale_lock_root/.operation-lock/pid"
chmod 600 "$stale_lock_root/.operation-lock/pid"
expect_status 1 "$helper" prune --root "$stale_lock_root"
[ ! -e "$stale_lock_root/.operation-lock" ]

active_lock_root="$temporary_root/active-lock"
mkdir -m 700 "$active_lock_root" "$active_lock_root/.operation-lock"
printf '%s\n' "$$" >"$active_lock_root/.operation-lock/pid"
chmod 600 "$active_lock_root/.operation-lock/pid"
expect_status 75 "$helper" prune --root "$active_lock_root"
[ -d "$active_lock_root/.operation-lock" ]

absent_prune_root="$temporary_root/absent-prune"
expect_status 1 "$helper" prune --root "$absent_prune_root"
[ ! -e "$absent_prune_root" ]

traversal_root="$temporary_root/traversal"
mkdir \
	"$traversal_root" \
	"$traversal_root/versions" \
	"$traversal_root/python" \
	"$temporary_root/outside"
chmod 700 \
	"$traversal_root" \
	"$traversal_root/versions" \
	"$traversal_root/python" \
	"$temporary_root/outside"
printf 'media-control-relay-apple-companion-helper-v1\n' \
	>"$traversal_root/.media-control-relay-apple-companion-helper"
chmod 600 "$traversal_root/.media-control-relay-apple-companion-helper"
ln -s 'versions/../../outside' "$traversal_root/current"
expect_status 2 "$helper" status --root "$traversal_root"

damaged_root="$temporary_root/damaged"
digest="$($helper digest)"
version_root="$damaged_root/versions/$digest"
mkdir -p "$version_root/bin" "$damaged_root/python"
chmod 700 "$damaged_root" "$damaged_root/versions" "$damaged_root/python" "$version_root"
for file_name in helper.py pyproject.toml uv.lock .python-version; do
	install -m 600 "$repo_root/AppleCompanionHelper/$file_name" "$version_root/$file_name"
done
printf '#!/bin/sh\nexit 0\n' >"$version_root/bin/apple-companion-helper"
chmod 700 "$version_root/bin/apple-companion-helper"
printf '{"schema":1,"digest":"%s","pythonVersion":"3.13.7"}\n' "$digest" \
	>"$version_root/manifest.json"
chmod 600 "$version_root/manifest.json"
printf 'media-control-relay-apple-companion-helper-v1\n' \
	>"$damaged_root/.media-control-relay-apple-companion-helper"
chmod 600 "$damaged_root/.media-control-relay-apple-companion-helper"
ln -s "versions/$digest" "$damaged_root/current"
expect_status 2 "$helper" status --root "$damaged_root"

fixture_repo="$temporary_root/update-fixture"
fixture_helper="$fixture_repo/scripts/apple-companion-helper.sh"
fixture_source="$fixture_repo/AppleCompanionHelper"
fixture_runtime="$temporary_root/update-runtime"
stub_directory="$temporary_root/bin"
mkdir -p "$fixture_repo/scripts" "$fixture_source" "$stub_directory"
install -m 700 "$helper" "$fixture_helper"
for file_name in helper.py pyproject.toml uv.lock .python-version; do
	install -m 600 "$repo_root/AppleCompanionHelper/$file_name" "$fixture_source/$file_name"
done
cp "$fixture_source/helper.py" "$temporary_root/helper-v1.py"

cat >"$stub_directory/uv" <<'EOF'
#!/bin/sh
set -eu
command_name="$1"
shift
case "$command_name" in
python)
	subcommand="$1"
	shift
	version="$1"
	python_executable="$UV_PYTHON_INSTALL_DIR/cpython-$version/bin/python3"
	case "$subcommand" in
	install)
		mkdir -p "$(dirname "$python_executable")"
		printf '#!/bin/sh\nexit 0\n' >"$python_executable"
		chmod 700 "$python_executable"
		;;
	find) printf '%s\n' "$python_executable" ;;
	*) exit 64 ;;
	esac
	;;
venv)
	python_executable=""
	environment=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		--python)
			python_executable="$2"
			shift 2
			;;
		--link-mode)
			shift 2
			;;
		--relocatable) shift ;;
		*)
			environment="$1"
			shift
			;;
		esac
	done
	[ -n "$python_executable" ]
	[ -n "$environment" ]
	mkdir -p "$environment/bin"
	install -m 700 "$python_executable" "$environment/bin/python3"
	;;
sync) ;;
*) exit 64 ;;
esac
EOF
chmod 700 "$stub_directory/uv"

PATH="$stub_directory:$PATH" "$fixture_helper" install --root "$fixture_runtime" >/dev/null
digest_v1="$(PATH="$stub_directory:$PATH" "$fixture_helper" digest)"
[ "$(readlink "$fixture_runtime/current")" = "versions/$digest_v1" ]

printf '\n# update activation fixture\n' >>"$fixture_source/helper.py"
digest_v2="$(PATH="$stub_directory:$PATH" "$fixture_helper" digest)"
[ "$digest_v1" != "$digest_v2" ]
PATH="$stub_directory:$PATH" "$fixture_helper" update --root "$fixture_runtime" >/dev/null
[ "$(readlink "$fixture_runtime/current")" = "versions/$digest_v2" ]
PATH="$stub_directory:$PATH" "$fixture_helper" status --root "$fixture_runtime" |
	grep -q "^installed $digest_v2$"
[ -z "$(find "$fixture_runtime/versions/$digest_v1" -name '.current.*' -print -quit)" ]

cp "$temporary_root/helper-v1.py" "$fixture_source/helper.py"
printf '\n# damaged existing version\n' >>"$fixture_runtime/versions/$digest_v1/helper.py"
expect_status 2 env PATH="$stub_directory:$PATH" \
	"$fixture_helper" update --root "$fixture_runtime"
[ "$(readlink "$fixture_runtime/current")" = "versions/$digest_v2" ]

outside_python="$temporary_root/outside-python"
printf '#!/bin/sh\nexit 0\n' >"$outside_python"
chmod 700 "$outside_python"
rm "$fixture_runtime/current/venv/bin/python3"
ln -s "$outside_python" "$fixture_runtime/current/venv/bin/python3"
expect_status 2 "$fixture_helper" status --root "$fixture_runtime"
