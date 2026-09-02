#!/bin/sh

set -eu
umask 077

repo_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
source_root="$repo_root/AppleCompanionHelper"
default_root="$HOME/Library/Application Support/com.shinycomputers.media-control-relay/AppleCompanionHelper"
root="$default_root"
lock_directory=""
staging=""

cleanup() {
	[ -z "$staging" ] || rm -rf "$staging"
	if [ -n "$lock_directory" ]; then
		rm -f "$lock_directory/pid"
		rmdir "$lock_directory" 2>/dev/null || true
	fi
}
trap cleanup EXIT HUP INT TERM

usage() {
	printf 'Usage: %s <digest|status|install|update|prune|remove> [--root PATH]\n' "$0" >&2
	exit 64
}

[ "$#" -ge 1 ] || usage
command_name="$1"
shift
while [ "$#" -gt 0 ]; do
	case "$1" in
	--root)
		[ "$#" -ge 2 ] || usage
		root="$2"
		shift 2
		;;
	*) usage ;;
	esac
done

content_files="helper.py pyproject.toml uv.lock .python-version"
root_marker=".media-control-relay-apple-companion-helper"

calculate_digest() {
	content_root="$1"
	for file_name in $content_files; do
		[ -f "$content_root/$file_name" ] || return 1
	done
	for file_name in $content_files; do
		file_digest="$(shasum -a 256 "$content_root/$file_name" | awk '{ print $1 }')"
		printf '%s:%s\n' "$file_name" "$file_digest"
	done | shasum -a 256 | awk '{ print $1 }'
}

secure_directory() {
	path="$1"
	[ -d "$path" ] || return 1
	[ ! -L "$path" ] || return 1
	[ "$(stat -f '%u' "$path")" -eq "$(id -u)" ] || return 1
	[ "$(stat -f '%Lp' "$path")" = 700 ]
}

secure_file() {
	path="$1"
	[ -f "$path" ] || return 1
	[ ! -L "$path" ] || return 1
	[ "$(stat -f '%u' "$path")" -eq "$(id -u)" ] || return 1
	permissions="$(stat -f '%Lp' "$path")"
	case "$permissions" in
	600 | 700) return 0 ;;
	*) return 1 ;;
	esac
}

acquire_lock() {
	if [ ! -e "$root" ]; then
		mkdir -p "$root"
		chmod 700 "$root"
	fi
	secure_directory "$root" || {
		printf 'Refusing to lock an unsafe helper root\n' >&2
		exit 2
	}
	lock_candidate="$root/.operation-lock"
	if ! mkdir "$lock_candidate" 2>/dev/null; then
		secure_directory "$lock_candidate" || {
			printf 'Apple Companion helper lock is unsafe\n' >&2
			exit 2
		}
		lock_pid="$(cat "$lock_candidate/pid" 2>/dev/null || true)"
		case "$lock_pid" in
		'' | *[!0-9]*) lock_pid="" ;;
		esac
		if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
			printf 'Another Apple Companion helper operation is active\n' >&2
			exit 75
		fi
		rm -rf "$lock_candidate"
		mkdir "$lock_candidate"
	fi
	lock_directory="$lock_candidate"
	chmod 700 "$lock_directory"
	printf '%s\n' "$$" >"$lock_directory/pid"
	chmod 600 "$lock_directory/pid"
}

resolve_current() {
	[ -L "$root/current" ] || return 1
	target="$(readlink "$root/current")"
	digest="${target#versions/}"
	[ "$target" = "versions/$digest" ] || return 1
	[ "${#digest}" -eq 64 ] || return 1
	case "$digest" in
	*[!0-9a-f]*) return 1 ;;
	esac
	resolved="$root/$target"
	secure_directory "$resolved" || return 1
	printf '%s\n' "$resolved"
}

validate_runtime_version() {
	candidate_root="$1"
	expected_digest="$2"
	secure_directory "$candidate_root" || return 1
	for file_name in $content_files; do
		secure_file "$candidate_root/$file_name" || return 1
	done
	computed_digest="$(calculate_digest "$candidate_root")" || return 1
	[ "$computed_digest" = "$expected_digest" ] || return 1
	[ "$(basename "$candidate_root")" = "$expected_digest" ] || return 1
	secure_file "$candidate_root/manifest.json" || return 1
	secure_file "$candidate_root/bin/apple-companion-helper" || return 1
	python_executable="$candidate_root/venv/bin/python3"
	[ -x "$python_executable" ] || return 1
	resolved_python="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$python_executable" 2>/dev/null)" || return 1
	resolved_root="$(ruby -e 'puts File.realpath(ARGV.fetch(0))' "$root" 2>/dev/null)" || return 1
	case "$resolved_python" in
	"$resolved_root"/*) ;;
	*) return 1 ;;
	esac
	ruby -rjson -e '
		manifest = JSON.parse(File.read(ARGV.fetch(0)))
		exit 1 unless manifest == {
		  "schema" => 1,
		  "digest" => ARGV.fetch(1),
		  "pythonVersion" => ARGV.fetch(2)
		}
	' "$candidate_root/manifest.json" "$expected_digest" "$(cat "$candidate_root/.python-version")"
}

status_runtime() {
	if [ ! -e "$root" ]; then
		printf 'not-installed\n'
		return 1
	fi
	secure_directory "$root" || {
		printf 'damaged\n'
		return 2
	}
	secure_directory "$root/versions" || {
		printf 'damaged\n'
		return 2
	}
	secure_directory "$root/python" || {
		printf 'damaged\n'
		return 2
	}
	secure_file "$root/$root_marker" || {
		printf 'damaged\n'
		return 2
	}
	resolved="$(resolve_current)" || {
		printf 'damaged\n'
		return 2
	}
	digest="$(basename "$resolved")"
	validate_runtime_version "$resolved" "$digest" || {
		printf 'damaged\n'
		return 2
	}
	printf 'installed %s\n' "$digest"
}

ensure_root() {
	if [ -L "$root" ]; then
		printf 'Refusing to use a symlinked helper root\n' >&2
		exit 2
	fi
	mkdir -p "$root/versions" "$root/python"
	chmod 700 "$root" "$root/versions" "$root/python"
	if [ ! -e "$root/$root_marker" ]; then
		printf 'media-control-relay-apple-companion-helper-v1\n' >"$root/$root_marker"
		chmod 600 "$root/$root_marker"
	fi
	secure_directory "$root"
	secure_directory "$root/versions"
}

activate_version() {
	digest="$1"
	temporary_link="$root/.current.$$"
	rm -f "$temporary_link"
	ln -s "versions/$digest" "$temporary_link"
	mv -fh "$temporary_link" "$root/current" || {
		rm -f "$temporary_link"
		return 1
	}
}

install_runtime() {
	command -v uv >/dev/null 2>&1 || {
		printf 'uv is required to install the local Apple Companion helper\n' >&2
		exit 69
	}
	ensure_root
	digest="$(calculate_digest "$source_root")"
	version_root="$root/versions/$digest"
	if [ -d "$version_root" ]; then
		validate_runtime_version "$version_root" "$digest" || {
			printf 'Existing helper version is damaged; remove and reinstall it\n' >&2
			exit 2
		}
		activate_version "$digest"
		status_runtime
		return
	fi

	staging="$root/versions/.staging.$$"
	rm -rf "$staging"
	mkdir -p "$staging/bin"
	for file_name in $content_files; do
		install -m 600 "$source_root/$file_name" "$staging/$file_name"
	done
	python_version="$(cat "$staging/.python-version")"
	UV_PYTHON_INSTALL_DIR="$root/python" \
		uv python install "$python_version" --no-bin --no-progress
	python_executable="$(
		UV_PYTHON_INSTALL_DIR="$root/python" \
			uv python find "$python_version" --managed-python --resolve-links
	)"
	uv venv \
		--relocatable \
		--link-mode copy \
		--python "$python_executable" \
		"$staging/venv"
	UV_PROJECT_ENVIRONMENT="$staging/venv" \
		UV_PYTHON_INSTALL_DIR="$root/python" \
		uv sync \
		--locked \
		--no-dev \
		--project "$staging" \
		--python "$python_executable" \
		--link-mode copy \
		--no-progress

	cat >"$staging/bin/apple-companion-helper" <<'EOF'
#!/bin/sh
set -eu
runtime_root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)"
exec "$runtime_root/venv/bin/python3" -I "$runtime_root/helper.py"
EOF
	chmod 700 "$staging/bin/apple-companion-helper"
	printf '{"schema":1,"digest":"%s","pythonVersion":"%s"}\n' \
		"$digest" "$python_version" >"$staging/manifest.json"
	chmod 600 "$staging/manifest.json"
	chmod -R go-rwx "$staging"
	mv "$staging" "$version_root"
	staging=""
	activate_version "$digest"
	status_runtime
}

prune_runtime() {
	resolved="$(resolve_current)" || {
		printf 'not-installed\n' >&2
		exit 1
	}
	current_digest="$(basename "$resolved")"
	for candidate in "$root/versions"/*; do
		[ -d "$candidate" ] || continue
		[ "$(basename "$candidate")" = "$current_digest" ] || rm -rf "$candidate"
	done
}

remove_runtime() {
	if [ ! -e "$root" ]; then
		printf 'not-installed\n'
		return
	fi
	secure_directory "$root" || {
		printf 'Refusing to remove an unsafe helper root\n' >&2
		exit 2
	}
	secure_file "$root/$root_marker" || {
		printf 'Refusing to remove a directory without the helper marker\n' >&2
		exit 2
	}
	rm -rf "$root"
	printf 'removed\n'
	printf 'Keychain credentials were preserved; remove them through the app when desired.\n'
}

case "$command_name" in
digest) calculate_digest "$source_root" ;;
status) status_runtime ;;
install | update)
	acquire_lock
	install_runtime
	;;
prune)
	[ ! -e "$root" ] || acquire_lock
	prune_runtime
	;;
remove)
	[ ! -e "$root" ] || acquire_lock
	remove_runtime
	;;
*) usage ;;
esac
