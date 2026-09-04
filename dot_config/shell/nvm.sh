# nvm is a shell function and must be loaded only by interactive shells.

: "${NVM_DIR:=${XDG_DATA_HOME:-$HOME/.local/share}/nvm}"
export NVM_DIR

nvm_script="$NVM_DIR/nvm.sh"
if [ -s "$nvm_script" ]; then
    . "$nvm_script"
elif [ -s /usr/share/nvm/init-nvm.sh ]; then
    . /usr/share/nvm/init-nvm.sh
fi
unset nvm_script
