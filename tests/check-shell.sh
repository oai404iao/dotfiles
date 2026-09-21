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

for interpreter in sh bash zsh; do
    for home_case in default empty xdg override; do
        env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
            PATH="/usr/bin:/bin" ENTRYPOINT="$repo_dir/dot_config/shell/profile.sh" \
            HOME_CASE="$home_case" TEST_ROOT="$test_root" \
            "$interpreter" -c '
                expected="$HOME/.local/share/dsh"
                case "$HOME_CASE" in
                    empty) DSH_HOME="" ;;
                    xdg)
                        XDG_DATA_HOME="$TEST_ROOT/custom data"
                        expected="$XDG_DATA_HOME/dsh"
                        ;;
                    override)
                        DSH_HOME="$TEST_ROOT/custom dsh"
                        expected="$DSH_HOME"
                        ;;
                esac
                . "$ENTRYPOINT"
                [ "$DSH_HOME" = "$expected" ] || exit 1
                sh -c '"'"'[ "$DSH_HOME" = "$1" ]'"'"' sh "$expected" || exit 1
                . "$ENTRYPOINT"
                [ "$DSH_HOME" = "$expected" ]
            '
    done
done

grep -qxF '.local/share/dsh/' "$repo_dir/.chezmoiignore"
grep -qxF '.dsh/' "$repo_dir/.chezmoiignore"

mkdir -p "$fake_data/nvm"
cat >"$fake_data/nvm/nvm.sh" <<'EOF'
NVM_ALIAS_LINE=stable
NVM_ALIAS_LINE="${NVM_ALIAS_LINE%%#*}"
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

env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
    XDG_DATA_HOME="$fake_data" XDG_STATE_HOME="$fake_state" \
    NVM_DIR="$fake_data/nvm" \
    PATH="/usr/bin:/bin" \
    OPTIONS="$repo_dir/dot_config/zsh/rc.d/10-options.zsh" \
    NVM_PROFILE="$repo_dir/dot_config/shell/nvm.sh" \
    zsh -f -c '
        source "$OPTIONS"
        source "$NVM_PROFILE"
        [[ $NVM_TEST_LOADED = 1 ]]
    '

for old_loader in bash/rc.d/50-node.bash zsh/rc.d/50-node.zsh; do
    [ ! -e "$repo_dir/dot_config/$old_loader" ]
    grep -qxF ".config/$old_loader" "$repo_dir/.chezmoiremove"
done
if grep -rF 'shell/nvm.sh' "$repo_dir/dot_config/bash" "$repo_dir/dot_config/zsh"; then
    printf '%s\n' "nvm must not be loaded automatically" >&2
    exit 1
fi

mkdir -p "$fake_data/pnpm/bin" "$fake_data/nvm/versions/node/v24/bin"
for tool_dir in "$fake_data/pnpm/bin" "$fake_data/nvm/versions/node/v24/bin"; do
    printf '#!/bin/sh\nexit 0\n' >"$tool_dir/node"
    chmod +x "$tool_dir/node"
done
for interpreter in sh bash zsh; do
    env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
        XDG_DATA_HOME="$fake_data" XDG_STATE_HOME="$fake_state" \
        NVM_DIR="$fake_data/nvm" NVM_BIN="$fake_data/nvm/versions/node/v24/bin" \
        NVM_INC="$fake_data/nvm/versions/node/v24/include/node" \
        PATH="$fake_data/nvm/versions/node/v24/bin:$fake_data/pnpm/bin:/usr/bin:/bin:" \
        TOOLCHAINS="$repo_dir/dot_config/shell/toolchains.sh" \
        "$interpreter" -c '
            . "$TOOLCHAINS"
            [ "$(command -v node)" = "$PNPM_HOME/bin/node" ] || exit 1
            [ -z "${NVM_BIN+x}${NVM_INC+x}" ] || exit 1
            case "$PATH" in *"$NVM_DIR"*) exit 1 ;; esac
            case "$PATH" in *:) ;; *) exit 1 ;; esac
            original_path=$PATH
            . "$TOOLCHAINS"
            [ "$PATH" = "$original_path" ]
        '
done

mkdir -p "$fake_config/zsh"
cp "$repo_dir/dot_zshenv" "$fake_home/.zshenv"
cp "$repo_dir/dot_config/zsh/dot_zshenv" "$fake_config/zsh/.zshenv"
cp "$repo_dir/dot_config/shell/toolchains.sh" "$fake_config/shell/toolchains.sh"
for zsh_mode in -c -ic; do
    env -i HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" \
        XDG_DATA_HOME="$fake_data" XDG_STATE_HOME="$fake_state" \
        ZDOTDIR="$fake_config/zsh" NVM_DIR="$fake_data/nvm" \
        PATH="$fake_data/nvm/versions/node/v24/bin:$fake_data/pnpm/bin:/usr/bin:/bin" \
        zsh "$zsh_mode" '
            [[ "$(command -v node)" = "$PNPM_HOME/bin/node" ]] || exit 1
            [[ "$PATH" != *"$NVM_DIR"* ]] || exit 1
            export EXPECTED_PATH=$PATH
            exec zsh -c '"'"'
                [[ "$(command -v node)" = "$PNPM_HOME/bin/node" ]] || exit 1
                [[ "$PATH" = "$EXPECTED_PATH" ]]
            '"'"'
        '
done

printf '%s\n' "shell toolchain config passed"
