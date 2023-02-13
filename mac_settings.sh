#!/bin/bash
# the basic tool for MacOS

_hr() {
    echo "=============$1==============="
}

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# cmd=brew
cmd_install="brew install "
# cmd_remove="brew remove "

_hr "preinstall"

# $cmd_install wget vim unzip tar gcc
# $cmd_install zsh gnu-sed git net-tools openssl curl 

_hr "install zsh"

/bin/bash -c "$(curl -fsSL https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh)"
chsh -s /bin/zsh

_hr "configing"

touch ~/.vimrc
cat > "$HOME"/.vimrc << EOF
set nocompatible

syntax on

colorscheme molokai

set showmode

set showcmd

set mouse=a

set encoding=utf-8

set t_Co=256

set number

set autoread

set autoindent

set tabstop=4

set shiftwidth=4

set expandtab

set softtabstop=4

"  highlight current line
" set cursorline

" 折行
set nowrap

set scrolloff=5

set sidescrolloff=10

set laststatus=2

set ruler

set showmatch

set hlsearch

" ***编辑
" set spell spelllang=en_us

" 保留撤销历史
" set undofile

set autochdir

set noerrorbells

" set visualbell

set history=3000

set autoread

set listchars=tab:»■,trail:■
"set list

set wildmenu
set wildmode=longest:list,full

set clipboard+=unnamed

set backspace=2
EOF

#source "$HOME"/.zshrc

_hr "install some plug-in"

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/paulirish/git-open.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/git-open

if [ ! -d ~/.vim/colors ]; then
    mkdir -p -v ~/.vim/colors
fi
cd ~/.vim/colors
git clone https://github.com/tomasr/molokai.git
cp molokai/colors/molokai.vim ~/.vim/colors
rm -rf molokai

gsed -i 's/^plugins=(git)$/plugins=(\ngit\nzsh-autosuggestions\nzsh-syntax-highlighting\ngit-open\n)/' ~/.zshrc

_hr "Done"
