alias d="aria2c -x12 -s12"
alias icat="kitten icat"
alias nv="nvim"
alias vim="nvim"

c() {
    if (( $# < 1 )); then
        print -u2 "usage: c <file-or-directory>... [archive.zip]"
        return 2
    fi

    local output="archive.zip"
    local -a inputs=("$@")

    if (( $# > 1 )) && [[ "${inputs[-1]}" == *.zip ]]; then
        output="${inputs[-1]}"
        inputs[-1]=()
    fi

    local input
    for input in "${inputs[@]}"; do
        if [[ ! -e "$input" ]]; then
            print -u2 "not found: $input"
            return 1
        fi
    done

    command zip -r -- "$output" "${inputs[@]}"
}
