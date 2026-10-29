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

    [ -z "${NVM_DIR+x}" ]
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
    NVM_DIR="$test_root/custom-nvm"
    PATH="$NVM_DIR/versions/node/v24/bin:/usr/bin:/bin"
    MAVEN_ARGS="-B -Dmaven.repo.local=$test_root/custom-maven"
    _JAVA_OPTIONS="-Xmx1g -Djava.util.prefs.userRoot=$test_root/custom-java"
    export HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME PATH
    export NVM_DIR MAVEN_ARGS _JAVA_OPTIONS

    . "$repo_dir/dot_config/shell/toolchains.sh"

    [ -z "${NVM_DIR+x}" ]
    case "$PATH" in *"$test_root/custom-nvm"*) exit 1 ;; esac
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
                expected_paseo="$HOME/.local/share/paseo"
                case "$HOME_CASE" in
                    empty) DSH_HOME=""; PASEO_HOME="" ;;
                    xdg)
                        XDG_DATA_HOME="$TEST_ROOT/custom data"
                        expected="$XDG_DATA_HOME/dsh"
                        expected_paseo="$XDG_DATA_HOME/paseo"
                        ;;
                    override)
                        DSH_HOME="$TEST_ROOT/custom dsh"
                        expected="$DSH_HOME"
                        PASEO_HOME="$TEST_ROOT/custom paseo"
                        expected_paseo="$PASEO_HOME"
                        ;;
                esac
                . "$ENTRYPOINT"
                [ "$DSH_HOME" = "$expected" ] || exit 1
                [ "$PASEO_HOME" = "$expected_paseo" ] || exit 1
                sh -c '"'"'[ "$DSH_HOME" = "$1" ]'"'"' sh "$expected" || exit 1
                sh -c '"'"'[ "$PASEO_HOME" = "$1" ]'"'"' sh "$expected_paseo" || exit 1
                . "$ENTRYPOINT"
                [ "$PASEO_HOME" = "$expected_paseo" ] || exit 1
                [ "$DSH_HOME" = "$expected" ]
            '
    done
done

for helper_case in absent nonexecutable executable; do
    askpass_home="$test_root/askpass-$helper_case"
    mkdir -p "$askpass_home/.local/bin"
    if [ "$helper_case" != absent ]; then
        : >"$askpass_home/.local/bin/sudo-askpass"
        chmod 0644 "$askpass_home/.local/bin/sudo-askpass"
        if [ "$helper_case" = executable ]; then
            chmod 0755 "$askpass_home/.local/bin/sudo-askpass"
        fi
    fi
    for interpreter in sh bash zsh; do
        for value_case in unset empty custom; do
            env -i HOME="$askpass_home" XDG_CONFIG_HOME="$fake_config" \
                PATH="/usr/bin:/bin" ENTRYPOINT="$repo_dir/dot_config/shell/profile.sh" \
                HELPER_CASE="$helper_case" VALUE_CASE="$value_case" \
                "$interpreter" -c '
                    case "$VALUE_CASE" in
                        unset) unset SUDO_ASKPASS ;;
                        empty) SUDO_ASKPASS="" ;;
                        custom) SUDO_ASKPASS="$HOME/custom askpass" ;;
                    esac
                    for source_count in 1 2; do
                        . "$ENTRYPOINT"
                        if [ "$HELPER_CASE" = executable ]; then
                            expected="$HOME/.local/bin/sudo-askpass"
                            if [ "$VALUE_CASE" = custom ]; then
                                expected="$HOME/custom askpass"
                            fi
                            [ "$SUDO_ASKPASS" = "$expected" ] || exit 1
                            sh -c '"'"'[ "$SUDO_ASKPASS" = "$1" ]'"'"' sh "$expected" || exit 1
                        else
                            case "$VALUE_CASE" in
                                unset) [ -z "${SUDO_ASKPASS+x}" ] || exit 1 ;;
                                empty) [ "${SUDO_ASKPASS+x}" = x ] && [ -z "$SUDO_ASKPASS" ] || exit 1 ;;
                                custom) [ "$SUDO_ASKPASS" = "$HOME/custom askpass" ] || exit 1 ;;
                            esac
                        fi
                        if [ "$source_count" = 1 ]; then
                            original_path=$PATH
                        else
                            [ "$PATH" = "$original_path" ] || exit 1
                        fi
                    done
                '
        done
    done
done

fake_zenity="$test_root/fake-zenity"
cat >"$fake_zenity" <<'EOF'
#!/bin/sh
set -eu
[ "$#" = 3 ]
[ "$1" = --password ]
[ "$2" = '--title=sudo authentication' ]
[ "$3" = "--text=$EXPECTED_PROMPT" ]
if [ "$ZENITY_EXIT" != 0 ]; then
    exit "$ZENITY_EXIT"
fi
printf '%s\n' 'fake sudo password'
EOF
chmod 0755 "$fake_zenity"
askpass_copy="$test_root/sudo-askpass"
python3 - "$repo_dir/dot_local/bin/executable_sudo-askpass" "$askpass_copy" "$fake_zenity" <<'PY'
from pathlib import Path
import shlex
import sys

source, destination, zenity = sys.argv[1:]
helper = Path(source).read_text()
assert helper.count("/usr/bin/zenity") == 1
Path(destination).write_text(helper.replace("/usr/bin/zenity", shlex.quote(zenity)))
PY
chmod 0755 "$askpass_copy"
printf '%s\n' 'fake sudo password' >"$test_root/expected-password"
for prompt_case in default custom; do
    if [ "$prompt_case" = default ]; then
        prompt='Enter your login password'
        set --
    else
        prompt='Enter a fake password: "quoted" $value'
        set -- "$prompt"
    fi
    env -i EXPECTED_PROMPT="$prompt" ZENITY_EXIT=0 \
        "$askpass_copy" "$@" >"$test_root/askpass-output" 2>"$test_root/askpass-error"
    cmp "$test_root/expected-password" "$test_root/askpass-output"
    [ ! -s "$test_root/askpass-error" ]
    for zenity_exit in 1 7; do
        if env -i EXPECTED_PROMPT="$prompt" ZENITY_EXIT="$zenity_exit" \
            "$askpass_copy" "$@" >"$test_root/askpass-output" 2>"$test_root/askpass-error"; then
            printf '%s\n' "sudo-askpass must preserve zenity failure" >&2
            exit 1
        else
            [ "$?" = "$zenity_exit" ]
        fi
        [ ! -s "$test_root/askpass-output" ]
        [ ! -s "$test_root/askpass-error" ]
    done
done

grep -qxF '.local/share/dsh/' "$repo_dir/.chezmoiignore"
grep -qxF '.dsh/' "$repo_dir/.chezmoiignore"

python3 - "$repo_dir" <<'PY'
from pathlib import Path
import sys
import tomllib

root = Path(sys.argv[1])
config = tomllib.loads((root / "dot_config/herdr/config.toml").read_text())
assert config["theme"]["name"] == "catppuccin"
keys = config["keys"]
assert keys["prefix"] == "ctrl+a"
assert keys["split_vertical"] == "prefix+|"
assert keys["split_horizontal"] == "prefix+minus"
assert keys["reload_config"] == "prefix+r"
assert keys["resize_mode"] == "prefix+shift+r"
ignore = set((root / ".chezmoiignore").read_text().splitlines())
assert {".config/herdr/*", "!.config/herdr/config.toml",
        ".local/state/herdr/", ".local/share/herdr/", ".herdr/"} <= ignore
PY
if command -v herdr >/dev/null 2>&1; then
    HOME="$fake_home" XDG_CONFIG_HOME="$fake_config" XDG_STATE_HOME="$fake_state" \
        HERDR_CONFIG_PATH="$repo_dir/dot_config/herdr/config.toml" herdr config check
else
    printf '%s\n' 'SKIP: Herdr config validation (herdr unavailable)'
fi

if command -v chezmoi >/dev/null 2>&1; then
    python3 - "$repo_dir" <<'PY'
import json
from pathlib import Path
import subprocess
import sys

modifier = Path(sys.argv[1]) / "dot_config/pnpm/modify_private_config.yaml"

def modify(value):
    return subprocess.run(["sh", str(modifier)], input=value, text=True,
                          capture_output=True, check=True).stdout

def decode(value):
    result = subprocess.run(
        ["chezmoi", "--config", "/dev/null", "--config-format", "toml",
         "execute-template", "--with-stdin", "{{ .chezmoi.stdin | fromYaml | toJson }}"],
        input=value, text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout)

for settings in ({}, {"globalShims": {"node": "auto"}, "minimumReleaseAge": 2880,
                     "minimumReleaseAgeExclude": ["existing-package"]},
                 {"minimumReleaseAgeExclude": ["@getpaseo/*"]}):
    result = modify(json.dumps(settings))
    expected = dict(settings)
    expected["minimumReleaseAgeExclude"] = list(settings.get("minimumReleaseAgeExclude", []))
    if "@getpaseo/*" not in expected["minimumReleaseAgeExclude"]:
        expected["minimumReleaseAgeExclude"].append("@getpaseo/*")
    assert decode(result) == expected
    assert modify(result) == result
assert decode(modify("")) == {"minimumReleaseAgeExclude": ["@getpaseo/*"]}
for invalid in ("[]", "key: [", "---\n{}\n---\n{}",
                "minimumReleaseAgeExclude: null", "minimumReleaseAgeExclude: value",
                "minimumReleaseAgeExclude: [true]"):
    result = subprocess.run(["sh", str(modifier)], input=invalid, text=True, capture_output=True)
    assert result.returncode != 0 and not result.stdout, invalid
PY
    fixture_source="$test_root/source"
    mkdir -p "$fixture_source/dot_config" "$fixture_source/dot_local/bin"
    cp "$repo_dir/.chezmoiignore" "$repo_dir/.chezmoiremove" \
        "$repo_dir/dot_bash_profile" "$repo_dir/dot_bashrc" \
        "$repo_dir/dot_zshenv" "$fixture_source/"
    cp -R "$repo_dir/dot_config/bash" "$repo_dir/dot_config/zsh" \
        "$repo_dir/dot_config/shell" "$repo_dir/dot_config/pnpm" \
        "$repo_dir/dot_config/herdr" "$fixture_source/dot_config/"
    mkdir -p "$fixture_source/dot_config/herdr/sessions/test"
    printf '%s\n' 'unmanaged fixture' >"$fixture_source/dot_config/herdr/session.json"
    printf '%s\n' 'unmanaged fixture' >"$fixture_source/dot_config/herdr/sessions/test/session.json"
    cp "$repo_dir/dot_local/bin/executable_sudo-askpass" "$fixture_source/dot_local/bin/"
    for shell_choice in bash zsh; do
        for graphical in false true; do
            fixture_name="$shell_choice-$graphical"
            shell_home="$test_root/deploy-$fixture_name"
            mkdir -p "$shell_home/.config/shell" "$shell_home/.local" \
                "$shell_home/.config/bash/rc.d" "$shell_home/.config/zsh/rc.d" \
                "$shell_home/.config/pnpm" "$shell_home/.config/herdr/sessions/test"
            printf '%s\n' 'retained session' >"$shell_home/.config/herdr/session.json"
            printf '%s\n' 'retained session' >"$shell_home/.config/herdr/sessions/test/session.json"
            for old_loader in shell/nvm.sh bash/rc.d/50-node.bash zsh/rc.d/50-node.zsh; do
                : >"$shell_home/.config/$old_loader"
            done
            cat >"$test_root/$fixture_name.toml" <<EOF
mode = "file"
[data]
shell = "$shell_choice"
graphical = $graphical
niri = false
EOF
            chezmoi --config "$test_root/$fixture_name.toml" \
                --source "$fixture_source" --destination "$shell_home" \
                --cache "$test_root/chezmoi-cache" \
                --persistent-state "$test_root/$fixture_name-state.boltdb" \
                apply --exclude scripts,encrypted \
                "$shell_home/.bash_profile" "$shell_home/.bashrc" \
                "$shell_home/.zshenv" "$shell_home/.config/bash" \
                "$shell_home/.config/zsh" "$shell_home/.config/shell" \
                "$shell_home/.config/pnpm/config.yaml" \
                "$shell_home/.config/herdr" \
                "$shell_home/.local/bin"
            for target in .bash_profile .bashrc .zshenv \
                .config/bash/rc.d/10-options.bash .config/zsh/.zshrc; do
                [ -f "$shell_home/$target" ]
            done
            for old_loader in shell/nvm.sh bash/rc.d/50-node.bash zsh/rc.d/50-node.zsh; do
                [ ! -e "$shell_home/.config/$old_loader" ]
            done
            grep -qF '@getpaseo/*' "$shell_home/.config/pnpm/config.yaml"
            [ "$(stat -c %a "$shell_home/.config/pnpm/config.yaml")" = 600 ]
            cmp "$repo_dir/dot_config/herdr/config.toml" "$shell_home/.config/herdr/config.toml"
            grep -qxF 'retained session' "$shell_home/.config/herdr/session.json"
            grep -qxF 'retained session' "$shell_home/.config/herdr/sessions/test/session.json"
            herdr_managed=$(chezmoi --config "$test_root/$fixture_name.toml" \
                --source "$fixture_source" --destination "$shell_home" \
                --cache "$test_root/chezmoi-cache" \
                --persistent-state "$test_root/$fixture_name-state.boltdb" \
                managed --include=files "$shell_home/.config/herdr")
            [ "$herdr_managed" = '.config/herdr/config.toml' ]
            if [ "$graphical" = true ]; then
                [ -f "$shell_home/.local/bin/sudo-askpass" ]
                [ "$(stat -c %a "$shell_home/.local/bin/sudo-askpass")" = 755 ]
                cmp "$repo_dir/dot_local/bin/executable_sudo-askpass" \
                    "$shell_home/.local/bin/sudo-askpass"
            else
                [ ! -e "$shell_home/.local/bin/sudo-askpass" ]
            fi
        done
    done
fi

for old_loader in bash/rc.d/50-node.bash zsh/rc.d/50-node.zsh shell/nvm.sh; do
    [ ! -e "$repo_dir/dot_config/$old_loader" ]
done
if grep -rF 'shell/nvm.sh' "$repo_dir/dot_config/bash" "$repo_dir/dot_config/zsh"; then
    printf '%s\n' "nvm must not be loaded automatically" >&2
    exit 1
fi

mkdir -p "$fake_data/pnpm/bin" "$fake_data/nvm/versions/node/v24/bin"
for tool_dir in "$fake_data/pnpm/bin" "$fake_data/nvm/versions/node/v24/bin"; do
    for tool in node npm npx; do
        printf '#!/bin/sh\nexit 0\n' >"$tool_dir/$tool"
        chmod +x "$tool_dir/$tool"
    done
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
            for tool in node npm npx; do
                [ "$(command -v "$tool")" = "$PNPM_HOME/bin/$tool" ] || exit 1
            done
            [ -z "${NVM_DIR+x}${NVM_BIN+x}${NVM_INC+x}" ] || exit 1
            case "$PATH" in *"$XDG_DATA_HOME/nvm"*) exit 1 ;; esac
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
            for tool in node npm npx; do
                [[ "$(command -v "$tool")" = "$PNPM_HOME/bin/$tool" ]] || exit 1
            done
            [[ -z "${NVM_DIR+x}" ]] || exit 1
            [[ "$PATH" != *"$XDG_DATA_HOME/nvm"* ]] || exit 1
            export EXPECTED_PATH=$PATH
            exec zsh -c '"'"'
                for tool in node npm npx; do
                    [[ "$(command -v "$tool")" = "$PNPM_HOME/bin/$tool" ]] || exit 1
                done
                [[ "$PATH" = "$EXPECTED_PATH" ]]
            '"'"'
        '
done

python3 "$repo_dir/tests/check-zsh-externals.py"

printf '%s\n' "shell toolchain config passed"
