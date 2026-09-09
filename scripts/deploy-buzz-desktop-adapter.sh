#!/usr/bin/env bash
set -Eeuo pipefail

readonly expected_user='tobiasschluter'
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
readonly source_root
readonly buzz_app='/Applications/Buzz.app'
readonly buzz_root='/Users/tobiasschluter/Library/Application Support/Buzz'
readonly node_tools="$buzz_root/node-tools"
readonly package_root="$node_tools/lib/node_modules/@agentclientprotocol"
readonly installed_package="$package_root/codex-acp"
readonly backup_root="$buzz_root/adapter-backups/codex-acp"

operation="${1:-}"
deploy_tree="${DEPLOY_TREE:-}"
requested_backup="${BACKUP_NAME:-}"
staging_root="${STAGING_ROOT:-}"
source_sha="${SOURCE_SHA:-}"
automatic_rollback=''
backup_name=''
node_bin=''

fail() {
    echo "error: $*" >&2
    return 1
}

resolve_runtime() {
    node_bin="$(find "$buzz_root/runtimes/node" -type f -path '*/darwin-arm64/bin/node' -perm -111 -print | sort | tail -n 1)"
    [[ -n "$node_bin" && -x "$node_bin" ]] || fail 'Buzz Node runtime not found'
}

acp_processes_running() {
    local pattern

    for pattern in \
        "$buzz_app/Contents/MacOS/buzz-acp( |$)" \
        "$node_tools/bin/codex-acp( |$)" \
        "$installed_package/dist/index.js( |$)"; do
        pgrep -f "$pattern" >/dev/null 2>&1 && return 0
    done
    return 1
}

backup_current_installation() {
    local reason="$1"
    local timestamp

    [[ -d "$installed_package" && -f "$installed_package/package.json" ]] || fail 'installed codex-acp package is missing'
    mkdir -p "$backup_root"
    timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
    backup_name="codex-acp-${reason}-${timestamp}-${source_sha:0:12}"
    [[ ! -e "$backup_root/$backup_name" ]] || fail 'rollback directory already exists'
    mv "$installed_package" "$backup_root/$backup_name"
    automatic_rollback="$backup_root/$backup_name"
}

validate_deploy_tree() {
    [[ -n "$deploy_tree" && -d "$deploy_tree" && ! -L "$deploy_tree" ]] || fail 'deployment runtime tree is missing or symlinked'
    deploy_tree="$(cd "$deploy_tree" && pwd -P)"
    case "$deploy_tree" in
        "$staging_root"/*) ;;
        *) fail 'deployment runtime tree must be inside the selected staging directory' ;;
    esac
    [[ -f "$deploy_tree/package.json" ]] || fail 'deployment package metadata is missing'
    [[ -f "$deploy_tree/dist/index.js" ]] || fail 'deployment bundle is missing'
    [[ -f "$deploy_tree/node_modules/@openai/codex/package.json" ]] || fail 'deployment Codex runtime is missing'
}

prepare_rollback_tree() {
    local source_backup

    [[ "$requested_backup" =~ ^[A-Za-z0-9._-]+$ ]] || fail 'rollback backup name is invalid'
    source_backup="$backup_root/$requested_backup"
    [[ -d "$source_backup" ]] || fail 'requested rollback backup does not exist'
    deploy_tree="$staging_root/codex-acp-rollback"
    [[ ! -e "$deploy_tree" ]] || fail 'rollback staging directory already exists'
    ditto "$source_backup" "$deploy_tree"
    validate_deploy_tree
}

install_tree() {
    local expected_sha
    local installed_sha

    expected_sha="$(shasum -a 256 "$deploy_tree/dist/index.js" | awk '{print $1}')"
    [[ -n "$expected_sha" ]] || fail 'deployment bundle hash is empty'
    [[ ! -e "$installed_package" ]] || fail 'installed package target was not moved to backup'
    mv "$deploy_tree" "$installed_package"

    [[ -x "$node_tools/bin/codex-acp" ]] || fail 'codex-acp executable was not installed'
    [[ -f "$installed_package/dist/index.js" ]] || fail 'installed codex-acp bundle is missing'
    "$node_bin" --check "$installed_package/dist/index.js"
    grep -aq 'sessionTitle' "$installed_package/dist/index.js" || fail 'installed bundle lacks session title support'
    installed_sha="$(shasum -a 256 "$installed_package/dist/index.js" | awk '{print $1}')"
    [[ "$installed_sha" == "$expected_sha" ]] || fail 'installed bundle hash does not match the deployment tarball'

    installed_version="$("$node_bin" -e 'const fs=require("node:fs"); const p=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(p.version)' "$installed_package/package.json")"
    [[ -n "$installed_version" ]] || fail 'installed package version is empty'

    echo "installed_version=$installed_version"
    echo "installed_sha256=$installed_sha"
}

restore_automatically() {
    local exit_code=$?
    local failed_tree
    trap - ERR
    set +e
    if [[ -n "$automatic_rollback" && -d "$automatic_rollback" ]]; then
        echo 'deployment failed; restoring the pre-deploy package' >&2
        failed_tree="$staging_root/codex-acp-failed"
        if [[ -d "$installed_package" && ! -e "$failed_tree" ]]; then
            mv "$installed_package" "$failed_tree"
        fi
        if [[ ! -e "$installed_package" ]]; then
            mv "$automatic_rollback" "$installed_package"
        fi
    fi
    exit "$exit_code"
}

[[ "$(id -un)" == "$expected_user" ]] || fail 'run as the Studio owner'
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || fail 'SOURCE_SHA must select a full commit'
[[ "$(git -C "$source_root" rev-parse HEAD)" == "$source_sha" ]] || fail 'selected source commit does not match this checkout'
git -C "$source_root" diff --quiet HEAD -- || fail 'tracked source changes are not committed'
[[ -n "$staging_root" && -d "$staging_root" && ! -L "$staging_root" ]] || fail 'STAGING_ROOT must select a real staging directory'
staging_root="$(cd "$staging_root" && pwd -P)"
[[ "$(uname -s)" == 'Darwin' && "$(uname -m)" == 'arm64' ]] || fail 'deployment requires macOS arm64'
[[ -d "$buzz_app" && -d "$buzz_root" ]] || fail 'Buzz installation is missing'
case "$operation" in
    deploy|rollback) ;;
    *) fail 'operation must be deploy or rollback' ;;
esac

resolve_runtime
if pgrep -f "$buzz_app/Contents/MacOS" >/dev/null 2>&1 || acp_processes_running; then
    fail 'quit Buzz and finish its ACP sessions before changing the adapter'
fi
trap restore_automatically ERR

if [[ "$operation" == 'deploy' ]]; then
    validate_deploy_tree
    for member in package.json package-lock.json dist/index.js; do
        cmp -s "$source_root/$member" "$deploy_tree/$member" || fail "runtime differs from the selected build: $member"
    done
    backup_current_installation pre-deploy
else
    prepare_rollback_tree
    backup_current_installation pre-rollback
fi

echo "backup_name=$backup_name"

install_tree
automatic_rollback=''
trap - ERR
echo 'installation verified; Buzz can now be opened by the operator'
