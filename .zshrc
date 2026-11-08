# Interactive Zsh configuration for Ubuntu 26.04 Desktop.
[[ -o interactive ]] || return

# Keep instant prompt near the top; no interactive commands below this block.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

typeset -U path PATH
path=("$HOME/.local/bin" $path)
export ZSH="${ZSH:-$HOME/.oh-my-zsh}"
export ZSH_CUSTOM="${ZSH_CUSTOM:-$ZSH/custom}"
ZSH_THEME=''
[[ ! -r "$ZSH_CUSTOM/themes/powerlevel10k/powerlevel10k.zsh-theme" ]] ||
  ZSH_THEME='powerlevel10k/powerlevel10k'
zstyle ':omz:update' mode reminder

plugins=(z git sudo tmux docker extract command-not-found colored-man-pages)
for plugin in you-should-use zsh-autosuggestions zsh-syntax-highlighting; do
  [[ ! -r "$ZSH_CUSTOM/plugins/$plugin/$plugin.plugin.zsh" ]] || plugins+=($plugin)
done
unset plugin
[[ ! -r "$ZSH/oh-my-zsh.sh" ]] || source "$ZSH/oh-my-zsh.sh"
[[ ! -r "$HOME/.p10k.zsh" ]] || source "$HOME/.p10k.zsh"

# Never force TERM: the terminal emulator and tmux advertise their capabilities.
export BAT_THEME='Dracula'
export MICRO_TRUECOLOR=1
(( ! $+commands[micro] )) || export EDITOR=micro
if (( $+commands[bat] && $+commands[col] )); then
  export MANPAGER="sh -c 'col -bx | bat --language man --plain'"
  export MANROFFOPT='-c'
fi
if (( $+commands[fd] )); then
  export FZF_DEFAULT_COMMAND='fd --type file --color=always'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi
export FZF_DEFAULT_OPTS='--ansi -m --bind ctrl-a:select-all,ctrl-d:deselect-all,ctrl-t:toggle-all'
# fzf key bindings require a live line editor, not just an interactive shell.
if [[ -o zle && -t 0 ]] && (( $+commands[fzf] )); then
  source <(fzf --zsh)
fi

alias ls='ls --color=auto'
alias rm='rm -iv'
alias cp='cp -iv'
alias mv='mv -iv'
alias aria2c='aria2c -x 4 -s 4 --retry-wait=1'

# Prefer native Wayland clipboard access; retain xclip for X11 sessions.
clip() {
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && (( $+commands[wl-copy] )); then
    wl-copy "$@"
  elif [[ -n ${DISPLAY:-} ]] && (( $+commands[xclip] )); then
    xclip -selection clipboard "$@"
  else
    print -u2 'No graphical clipboard available.'
    return 1
  fi
}
paste() {
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && (( $+commands[wl-paste] )); then
    wl-paste "$@"
  elif [[ -n ${DISPLAY:-} ]] && (( $+commands[xclip] )); then
    xclip -selection clipboard -o "$@"
  else
    print -u2 'No graphical clipboard available.'
    return 1
  fi
}

setopt NO_CLOBBER
# Machine-specific settings stay outside this repository.
[[ ! -r "$HOME/.zshrc.local" ]] || source "$HOME/.zshrc.local"
