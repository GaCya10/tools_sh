#!/bin/bash
# the basic tool for a new unix

__delimiter() {
	echo "=============$1==============="
}

OS=$(hostnamectl | grep System | awk '{print $3}')

if ! which yum 2>/dev/null; then
	if ! which apt 2>/dev/null; then
		echo "It's not a unix-like system"
		exit 1
	fi
	cmd_install="sudo apt install -y "
	cmd_update="sudo apt update; sudo apt upgrade -y"
	# cmd_remove="apt remove -y "
	eval $cmd_update
else
	# cmd=yum
	cmd_install="sudo yum install -y "
	cmd_update="sudo yum update -y"
	# cmd_remove="yum remove -y "
	$cmd_update
	$cmd_install epel-release
fi

if [ "$OS" = "Amazon" ]; then
	$cmd_install util-linux-user 
    sudo amazon-linux-extras install epel -y
fi

__delimiter "preinstall"

$cmd_install wget vim unzip tar gcc zsh
$cmd_install zsh git net-tools openssl curl

__delimiter "install zsh"

curl -L https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh | sh
sudo chsh -s /bin/zsh $(whoami)

__delimiter "configing"

touch "$HOME"/.vimrc
cat >"$HOME"/.vimrc<<EOF
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

# source "$HOME"/.zshrc

__delimiter "install some plug-in"

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/paulirish/git-open.git ${ZSH_CUSTOM:-"$HOME"/.oh-my-zsh/custom}/plugins/git-open

if [ ! -d "$HOME"/repo ]; then
	mkdir -p -v "$HOME"/repo
fi
cd "$HOME"/repo || exit
git clone https://github.com/tomasr/molokai.git

if [ ! -d "$HOME"/.vim/colors ]; then
	mkdir -p -v "$HOME"/.vim/colors
fi
cp molokai/colors/molokai.vim "$HOME"/.vim/colors

sudo sed -i 's/^plugins=(git)$/plugins=(\ngit\nzsh-autosuggestions\nzsh-syntax-highlighting\ngit-open\n)/' "$HOME"/.zshrc

sudo sed -i 's/^#Port 22/Port 54321/' /etc/ssh/sshd_config
sudo sed -i 's/^#ClientAliveInterval.*/ClientAliveInterval 60/' /etc/ssh/sshd_config
sudo sed -i 's/^#ClientAliveCountMax.*/ClientAliveCountMax 60/' /etc/ssh/sshd_config
sudo sed -i 's/^#TCPKeepAlive.*/TCPKeepAlive yes/' /etc/ssh/sshd_config
sudo systemctl restart sshd

sudo sed -i '/^PROMPT/d' ~/.zshrc
sudo echo 'PROMPT="[%{$fg[white]%}%n@%{$fg[green]%}%m%{$reset_color%}] ${PROMPT}"' >>  "$HOME"/.zshrc

__delimiter "Done"
