nvm_profile="$XDG_CONFIG_HOME/shell/nvm.sh"
[ -r "$nvm_profile" ] && . "$nvm_profile"
unset nvm_profile

if [ -r "$NVM_DIR/bash_completion" ]; then
    . "$NVM_DIR/bash_completion"
elif [ -r /usr/share/nvm/bash_completion ]; then
    . /usr/share/nvm/bash_completion
fi
