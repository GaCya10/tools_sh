#!/bin/bash
# the basic tool for a new unix 

__delimiter() {
    echo "=============$1==============="
}

OS=`hostnamectl | grep System | awk '{print $3}'`

res=`which yum 2>/dev/null`
if [ $? != "0" ]; then
	res=`which apt 2>/dev/null`
	if [ $? != "0" ]; then
		echo "It's not a unix-like system"
		exit 1
	fi
	cmd=apt
	cmd_install="apt install -y "
	cmd_update="apt update; apt upgrade -y"
	cmd_remove="apt remove -y "
	$cmd_update
else
	cmd=yum
	cmd_install="yum install -y "
	cmd_update="yum update -y"
	cmd_remove="yum remove -y "
	$cmd_update
	$cmd_install epel-release
fi

if [ $OS = "Amazon" ]; then
    $cmd_update
    $cmd_install util-linux-user
    amazon-linux-extras install epel -y
fi

__delimiter "preinstall"

$cmd_install wget vim unzip tar gcc
$cmd_install zsh git net-tools openssl curl

__delimiter "install zsh"

curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
chsh -s /bin/zsh

__delimiter "configing"

touch ~/.vimrc
cat > "/root/.vimrc" << EOF
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

set clipboard=unnamed

set backspace=2
EOF

source ~/.zshrc

__delimiter "install some plug-in"

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/paulirish/git-open.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/git-open

if [ ! -d ~/repo ]; then
    mkdir -p -v ~/repo
fi
cd /root/repo
git clone https://github.com/tomasr/molokai.git

if [ ! -d ~/.vim/colors ]; then
    mkdir -p -v ~/.vim/colors
fi
cp molokai/colors/molokai.vim ~/.vim/colors

sed -i 's/^plugins=(git)$/plugins=(\ngit\nzsh-autosuggestions\nzsh-syntax-highlighting\ngit-open\n)/' ~/.zshrc

__delimiter "Done"
