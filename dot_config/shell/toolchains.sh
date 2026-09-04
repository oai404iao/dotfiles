# Shared development-tool locations. Keep this file fast and secret-free.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

export XDG_CONFIG_HOME
export XDG_CACHE_HOME
export XDG_DATA_HOME
export XDG_STATE_HOME

: "${NVM_DIR:=$XDG_DATA_HOME/nvm}"
: "${NPM_CONFIG_CACHE:=$XDG_CACHE_HOME/npm}"
: "${NPM_CONFIG_USERCONFIG:=$XDG_CONFIG_HOME/npm/npmrc}"
: "${NODE_REPL_HISTORY:=$XDG_STATE_HOME/node_repl_history}"
: "${PNPM_HOME:=$XDG_DATA_HOME/pnpm}"

: "${CARGO_HOME:=$XDG_DATA_HOME/cargo}"
: "${RUSTUP_HOME:=$XDG_DATA_HOME/rustup}"

: "${GOPATH:=$XDG_DATA_HOME/go}"
: "${GOMODCACHE:=$GOPATH/pkg/mod}"
: "${GOCACHE:=$XDG_CACHE_HOME/go-build}"

if [ -z "${JAVA_HOME-}" ] && [ -d /usr/lib/jvm/default ]; then
    JAVA_HOME="/usr/lib/jvm/default"
fi
: "${GRADLE_USER_HOME:=$XDG_DATA_HOME/gradle}"

java_preferences_option="-Djava.util.prefs.userRoot=$XDG_CONFIG_HOME/java"
case " ${_JAVA_OPTIONS-} " in
    *" -Djava.util.prefs.userRoot="*) ;;
    *) _JAVA_OPTIONS="${_JAVA_OPTIONS:+$_JAVA_OPTIONS }$java_preferences_option" ;;
esac
unset java_preferences_option

# Maven 3 has no user-home override, so redirect its regenerable repository
# and use an XDG settings file only when the machine provides one.
maven_repository_option="-Dmaven.repo.local=$XDG_CACHE_HOME/maven/repository"
case " ${MAVEN_ARGS-} " in
    *" -Dmaven.repo.local="*) ;;
    *) MAVEN_ARGS="${MAVEN_ARGS:+$MAVEN_ARGS }$maven_repository_option" ;;
esac
unset maven_repository_option

if [ -r "$XDG_CONFIG_HOME/maven/settings.xml" ]; then
    case " ${MAVEN_ARGS-} " in
        *" --settings "* | *" --settings="* | *" -s "*) ;;
        *) MAVEN_ARGS="${MAVEN_ARGS:+$MAVEN_ARGS }--settings $XDG_CONFIG_HOME/maven/settings.xml" ;;
    esac
fi

: "${DOCKER_CONFIG:=$XDG_CONFIG_HOME/docker}"

: "${DOTNET_CLI_HOME:=$XDG_DATA_HOME/dotnet}"
: "${DOTNET_BUNDLE_EXTRACT_BASE_DIR:=$XDG_CACHE_HOME/dotnet/bundle-extract}"
: "${NUGET_PACKAGES:=$XDG_CACHE_HOME/nuget/packages}"
: "${NUGET_HTTP_CACHE_PATH:=$XDG_CACHE_HOME/nuget/http-cache}"
: "${NUGET_PLUGINS_CACHE_PATH:=$XDG_CACHE_HOME/nuget/plugins-cache}"

export NVM_DIR
export NPM_CONFIG_CACHE
export NPM_CONFIG_USERCONFIG
export NODE_REPL_HISTORY
export PNPM_HOME
export CARGO_HOME
export RUSTUP_HOME
export GOPATH
export GOMODCACHE
export GOCACHE
export GRADLE_USER_HOME
export _JAVA_OPTIONS
export MAVEN_ARGS
export DOCKER_CONFIG
export DOTNET_CLI_HOME
export DOTNET_BUNDLE_EXTRACT_BASE_DIR
export NUGET_PACKAGES
export NUGET_HTTP_CACHE_PATH
export NUGET_PLUGINS_CACHE_PATH

if [ -n "${JAVA_HOME-}" ]; then
    export JAVA_HOME
fi

for tool_bin in \
    "${JAVA_HOME:+$JAVA_HOME/bin}" \
    "$PNPM_HOME" \
    "$PNPM_HOME/bin" \
    "$GOPATH/bin" \
    "$CARGO_HOME/bin"
do
    [ -n "$tool_bin" ] || continue
    case ":${PATH-}:" in
        *":$tool_bin:"*) ;;
        *) PATH="$tool_bin${PATH:+:$PATH}" ;;
    esac
done
unset tool_bin
export PATH
