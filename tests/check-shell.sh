#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/chezmoi-shell-test.XXXXXX)
marker="$test_root/.shell-test-root"
: >"$marker"

cleanup() {
    if [ "${test_root-}" != "${test_root#/tmp/chezmoi-shell-test.}" ] &&
        [ -f "$marker" ]
    then
        /usr/bin/rm -rf -- "$test_root"
    else
        printf 'refusing unsafe shell test cleanup: %s\n' "${test_root-}" >&2
        return 1
    fi
}
trap cleanup EXIT

fake_home="$test_root/home"
fake_config="$fake_home/.config"
fake_cache="$fake_home/.cache"
fake_data="$fake_home/.local/share"
fake_state="$fake_home/.local/state"
fake_jvm="$test_root/jvm"

mkdir -p \
    "$fake_config/maven" "$fake_cache" "$fake_data" "$fake_state" \
    "$fake_jvm/bin"
: >"$fake_config/maven/settings.xml"

(
    HOME="$fake_home"
    XDG_CONFIG_HOME="$fake_config"
    XDG_CACHE_HOME="$fake_cache"
    XDG_DATA_HOME="$fake_data"
    XDG_STATE_HOME="$fake_state"
    PATH="/usr/bin:/bin"
    JAVA_HOME="$fake_jvm"
    export HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
    export JAVA_HOME PATH

    unset NVM_DIR NPM_CONFIG_CACHE NPM_CONFIG_USERCONFIG NODE_REPL_HISTORY
    unset PNPM_HOME CARGO_HOME RUSTUP_HOME GOPATH GOMODCACHE GOCACHE
    unset GRADLE_USER_HOME _JAVA_OPTIONS MAVEN_ARGS DOCKER_CONFIG
    unset DOTNET_CLI_HOME DOTNET_BUNDLE_EXTRACT_BASE_DIR NUGET_PACKAGES
    unset NUGET_HTTP_CACHE_PATH
    unset NUGET_PLUGINS_CACHE_PATH

    . "$repo_dir/dot_config/shell/toolchains.sh"

    [ "$NVM_DIR" = "$fake_data/nvm" ]
    [ "$NPM_CONFIG_CACHE" = "$fake_cache/npm" ]
    [ "$NPM_CONFIG_USERCONFIG" = "$fake_config/npm/npmrc" ]
    [ "$NODE_REPL_HISTORY" = "$fake_state/node_repl_history" ]
    [ "$PNPM_HOME" = "$fake_data/pnpm" ]
    [ "$CARGO_HOME" = "$fake_data/cargo" ]
    [ "$RUSTUP_HOME" = "$fake_data/rustup" ]
    [ "$GOPATH" = "$fake_data/go" ]
    [ "$GOMODCACHE" = "$fake_data/go/pkg/mod" ]
    [ "$GOCACHE" = "$fake_cache/go-build" ]
    [ "$JAVA_HOME" = "$fake_jvm" ]
    [ "$GRADLE_USER_HOME" = "$fake_data/gradle" ]
    [ "$_JAVA_OPTIONS" = "-Djava.util.prefs.userRoot=$fake_config/java" ]
    [ "$MAVEN_ARGS" = "-Dmaven.repo.local=$fake_cache/maven/repository --settings $fake_config/maven/settings.xml" ]
    [ "$DOCKER_CONFIG" = "$fake_config/docker" ]
    [ "$DOTNET_CLI_HOME" = "$fake_data/dotnet" ]
    [ "$DOTNET_BUNDLE_EXTRACT_BASE_DIR" = "$fake_cache/dotnet/bundle-extract" ]
    [ "$NUGET_PACKAGES" = "$fake_cache/nuget/packages" ]
    [ "$NUGET_HTTP_CACHE_PATH" = "$fake_cache/nuget/http-cache" ]
    [ "$NUGET_PLUGINS_CACHE_PATH" = "$fake_cache/nuget/plugins-cache" ]

    expected_path="$fake_data/cargo/bin:$fake_data/go/bin"
    expected_path="$expected_path:$fake_data/pnpm/bin:$fake_data/pnpm"
    expected_path="$expected_path:$fake_jvm/bin:/usr/bin:/bin"
    [ "$PATH" = "$expected_path" ]

    original_path=$PATH
    original_maven_args=$MAVEN_ARGS
    original_java_options=$_JAVA_OPTIONS
    . "$repo_dir/dot_config/shell/toolchains.sh"
    [ "$PATH" = "$original_path" ]
    [ "$MAVEN_ARGS" = "$original_maven_args" ]
    [ "$_JAVA_OPTIONS" = "$original_java_options" ]
)

(
    HOME="$fake_home"
    XDG_CONFIG_HOME="$fake_config"
    XDG_CACHE_HOME="$fake_cache"
    XDG_DATA_HOME="$fake_data"
    XDG_STATE_HOME="$fake_state"
    PATH="/usr/bin:/bin"
    NVM_DIR="$test_root/custom-nvm"
    MAVEN_ARGS="-B -Dmaven.repo.local=$test_root/custom-maven"
    _JAVA_OPTIONS="-Xmx1g -Djava.util.prefs.userRoot=$test_root/custom-java"
    export HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PATH
    export NVM_DIR MAVEN_ARGS _JAVA_OPTIONS

    . "$repo_dir/dot_config/shell/toolchains.sh"

    [ "$NVM_DIR" = "$test_root/custom-nvm" ]
    [ "$MAVEN_ARGS" = "-B -Dmaven.repo.local=$test_root/custom-maven --settings $fake_config/maven/settings.xml" ]
    [ "$_JAVA_OPTIONS" = "-Xmx1g -Djava.util.prefs.userRoot=$test_root/custom-java" ]
)

mkdir -p "$fake_config/shell"
cat >"$fake_config/shell/toolchains.sh" <<'EOF'
TOOLCHAINS_ENTRYPOINT_LOADED=1
export TOOLCHAINS_ENTRYPOINT_LOADED
EOF

for shell_entrypoint in \
    "$repo_dir/dot_config/shell/profile.sh" \
    "$repo_dir/dot_zshenv" \
    "$repo_dir/dot_bashrc"
do
    case "$shell_entrypoint" in
        *dot_zshenv)
            env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
                PATH="/usr/bin:/bin" ENTRYPOINT="$shell_entrypoint" \
                zsh -f -c 'source "$ENTRYPOINT"; [[ $TOOLCHAINS_ENTRYPOINT_LOADED = 1 ]]'
            ;;
        *dot_bashrc)
            env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
                PATH="/usr/bin:/bin" ENTRYPOINT="$shell_entrypoint" \
                bash --noprofile --norc -c '. "$ENTRYPOINT"; [ "$TOOLCHAINS_ENTRYPOINT_LOADED" = 1 ]'
            ;;
        *)
            env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
                PATH="/usr/bin:/bin" ENTRYPOINT="$shell_entrypoint" \
                sh -c '. "$ENTRYPOINT"; [ "$TOOLCHAINS_ENTRYPOINT_LOADED" = 1 ]'
            ;;
    esac
done

mkdir -p "$fake_data/nvm"
cat >"$fake_data/nvm/nvm.sh" <<'EOF'
NVM_TEST_LOADED=1
export NVM_TEST_LOADED
EOF

(
    HOME="$fake_home"
    XDG_DATA_HOME="$fake_data"
    NVM_DIR="$fake_data/nvm"
    export HOME XDG_DATA_HOME NVM_DIR

    . "$repo_dir/dot_config/shell/nvm.sh"
    [ "$NVM_TEST_LOADED" = 1 ]
)

grep -qF 'shell/nvm.sh' "$repo_dir/dot_config/bash/rc.d/50-node.bash"
grep -qF 'shell/nvm.sh' "$repo_dir/dot_config/zsh/rc.d/50-node.zsh"

printf '%s\n' "shell toolchain config passed"
