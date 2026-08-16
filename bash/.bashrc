#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

GREEN="\[$(tput setaf 2)\]"
RESET="\[$(tput sgr0)\]"
BOLD="\[$(tput bold)\]"

PS1="${BOLD}${GREEN} \W > ${RESET}"

# Aliases
# alias code='codium'

# Pi
export PATH="$HOME/.local/bin:$PATH"
