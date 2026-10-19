import hashlib
import io
import json
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile
import tomllib


repo = Path(__file__).resolve().parents[1]
externals = tomllib.loads((repo / ".chezmoiexternal.toml").read_text())
dependencies = {
    ".oh-my-zsh": ("ohmyzsh/ohmyzsh", "oh-my-zsh.sh"),
    ".oh-my-zsh/custom/themes/powerlevel10k": (
        "romkatv/powerlevel10k", "powerlevel10k.zsh-theme",
    ),
    ".oh-my-zsh/custom/plugins/zsh-autosuggestions": (
        "zsh-users/zsh-autosuggestions", "zsh-autosuggestions.plugin.zsh",
    ),
    ".oh-my-zsh/custom/plugins/zsh-syntax-highlighting": (
        "zsh-users/zsh-syntax-highlighting", "zsh-syntax-highlighting.plugin.zsh",
    ),
}
assert set(externals) == {*dependencies, ".config/pi/agent/AGENTS.md"}
for target, (upstream, _) in dependencies.items():
    entry = externals[target]
    assert re.fullmatch(
        rf"https://github\.com/{re.escape(upstream)}/archive/[0-9a-f]{{40}}\.tar\.gz",
        entry["url"],
    ), (target, entry["url"])

scratch = Path.home() / ".local/state/agents/tmp"
scratch.mkdir(parents=True, exist_ok=True)
task = Path(tempfile.mkdtemp(prefix="check-zsh-externals.", dir=scratch))
home = task / "home"
home.mkdir()
env = {
    "HOME": str(home),
    "XDG_CONFIG_HOME": str(home / ".config"),
    "XDG_CACHE_HOME": str(home / ".cache"),
    "XDG_DATA_HOME": str(home / ".local/share"),
    "XDG_STATE_HOME": str(home / ".local/state"),
    "PATH": "/usr/bin:/bin",
    "TMPDIR": str(task),
}


def run(args, **kwargs):
    result = subprocess.run(
        args, env=env, capture_output=True, text=True, **kwargs
    )
    assert result.returncode == 0, (args, result.stdout, result.stderr)
    return result.stdout


framework = repo / "dot_config/zsh/rc.d/20-framework.zsh"
zsh = shutil.which("zsh")
if zsh:
    run([zsh, "-f", "-c", '''
        source "$1" || exit 1
        [[ -n ${functions[_main_complete]} ]] || exit 1
        [[ -f $ZSH_COMPDUMP ]] || exit 1
        zstyle -s ':completion:*' menu value || exit 1
        [[ $value = select ]]
    ''', "zsh-fallback", str(framework)])
    stub = home / ".oh-my-zsh/oh-my-zsh.sh"
    stub.parent.mkdir()
    stub.write_text(
        "zstyle -s ':omz:update' mode update_mode || exit 1\n"
        "[[ $update_mode = disabled ]] || exit 1\n"
        "OMZ_STUB_LOADED=1\n"
    )
    run([zsh, "-f", "-c", '''
        source "$1" || exit 1
        [[ $OMZ_STUB_LOADED = 1 ]] || exit 1
        [[ $ZSH_THEME = powerlevel10k/powerlevel10k ]] || exit 1
        [[ ${plugins[(Ie)zsh-autosuggestions]} -gt 0 ]] || exit 1
        [[ ${plugins[(Ie)zsh-syntax-highlighting]} -gt 0 ]]
    ''', "zsh-framework", str(framework)])
else:
    print("zsh framework runtime checks skipped: zsh unavailable")

chezmoi = shutil.which("chezmoi")
if not chezmoi:
    print(f"zsh archive checks skipped: chezmoi unavailable (fixtures: {task})")
    raise SystemExit(0)

source = task / "source"
source.mkdir()
shutil.copyfile(repo / ".chezmoiignore", source / ".chezmoiignore")
config = task / "chezmoi.toml"
config.write_text('mode = "file"\n[data]\ngraphical = false\nniri = false\n')
destination = task / "destination"
destination.mkdir()
command = [
    chezmoi, "--config", str(config), "--source", str(source),
    "--destination", str(destination), "--cache", str(task / "chezmoi-cache"),
    "--persistent-state", str(task / "chezmoi-state.boltdb"), "--no-tty",
]

# Archive probes collide with local state, so ignores must prevent both
# inventory ownership and overwrites, not just preserve untracked extras.
ignored = {}
local = {
    ".oh-my-zsh/custom/example.zsh": "local custom example\n",
    ".oh-my-zsh/custom/personal.zsh": "local custom config\n",
    ".oh-my-zsh/cache/session": "local cache\n",
    ".oh-my-zsh/log/update.log": "local update log\n",
}
for target in dependencies:
    for name in (".git/config", "compiled.zwc", "compiled.zwc.old"):
        ignored[f"{target}/{name}"] = "local runtime state\n"
    local[f"{target}/local-extra.zsh"] = "local extra\n"
ignored[
    ".oh-my-zsh/custom/themes/powerlevel10k/gitstatus/usrbin/gitstatusd"
] = "local gitstatus executable\n"
user_cache = {
    ".cache/oh-my-zsh/session": "OMZ user cache\n",
    ".cache/zsh/zcompdump": "zsh user cache\n",
    ".cache/gitstatus/gitstatusd": "gitstatus user cache\n",
    ".cache/p10k-instant-prompt.zsh": "p10k user cache\n",
}
for name in user_cache:
    source_file = source / ("dot_cache/" + name.removeprefix(".cache/"))
    source_file.parent.mkdir(parents=True, exist_ok=True)
    source_file.write_text("must not manage user cache\n")
local.update(ignored)
local.update(user_cache)
for name, content in local.items():
    path = destination / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)

archives = {}
payloads = {}
for version in ("initial", "upgrade"):
    archives[version] = {}
    payloads[version] = {}
    for target, (upstream, entrypoint) in dependencies.items():
        pin = externals[target]["url"].rsplit("/", 1)[1].removesuffix(".tar.gz")
        if version == "upgrade":
            pin = hashlib.sha1(f"{upstream}:{pin}:upgrade".encode()).hexdigest()
        archive = task / "archives" / upstream / f"{pin}.tar.gz"
        archive.parent.mkdir(parents=True, exist_ok=True)
        contents = {
            entrypoint: f"# {upstream} {version}\n",
            "lib/fixture.zsh": f"# {upstream} library {version}\n",
        }
        payloads[version].update({
            f"{target}/{name}": content for name, content in contents.items()
        })
        contents.update({
            name: "must not overwrite local state\n"
            for name in (".git/config", "compiled.zwc", "compiled.zwc.old")
        })
        if target == ".oh-my-zsh":
            contents.update({
                "custom/example.zsh": "upstream custom example\n",
                "custom/upstream-only.zsh": "upstream custom example\n",
                "cache/session": "upstream cache\n",
                "log/update.log": "upstream log\n",
            })
        if upstream == "romkatv/powerlevel10k":
            contents["gitstatus/usrbin/gitstatusd"] = "upstream runtime\n"
        with tarfile.open(archive, "w:gz") as output:
            for name, content in contents.items():
                data = content.encode()
                info = tarfile.TarInfo(f"{upstream.split('/')[-1]}-{pin}/{name}")
                info.size = len(data)
                output.addfile(info, io.BytesIO(data))
        archives[version][target] = archive.as_uri()


def configure(version):
    # Only the scratch copy gets file URLs; the Pi external is never loaded.
    fixture = []
    for target in dependencies:
        entry = {**externals[target], "url": archives[version][target]}
        fixture.append(f"[{json.dumps(target)}]")
        fixture.extend(f"{key} = {json.dumps(value)}" for key, value in entry.items())
    (source / ".chezmoiexternal.toml").write_text("\n".join(fixture) + "\n")


def verify(version):
    for name, content in {**payloads[version], **local}.items():
        assert (destination / name).read_text() == content, (version, name)
    assert not (destination / ".oh-my-zsh/custom/upstream-only.zsh").exists()
    inventory = set(run(command + [
        "managed", "--include=files", "--path-style=relative",
    ]).splitlines())
    assert inventory == set(payloads[version]), (version, inventory)
    assert not run(command + ["status"]), version


for version in ("initial", "upgrade", "initial"):
    configure(version)
    run(command + ["apply"])
    verify(version)
    before = {
        name: (destination / name).stat().st_mtime_ns
        for name in {*payloads[version], *local}
    }
    run(command + ["apply"])
    verify(version)
    assert before == {
        name: (destination / name).stat().st_mtime_ns for name in before
    }, f"{version}: repeat apply rewrote files"

print(f"zsh external checks passed (retained fixtures: {task})")
