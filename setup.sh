#! /usr/bin/bash
set -euo pipefail

function step(){
  echo "$(tput setaf 6)$1$(tput sgr0)"
}

step "Configuring git"
git config --global user.name "Tzu-Yee"
git config --global user.email "fdja1974.cs07g@nctu.edu.tw"
git config --global core.editor "micro"
git config --global credential.helper 'cache --timeout=3600000'

step "Get useful commands"
sudo add-apt-repository -y ppa:peek-developers/stable
sudo apt update
sudo apt install -y git build-essential zsh fzf bat ncdu curl wget tmux ripgrep peek \
                    htop tree dos2unix openssh-server gnome-tweaks \
                    grub-customizer clang most fonts-roboto fonts-roboto-slab \
                    ibus-chewing aria2 dconf-cli libreoffice \
                    python3-dev python3-pip python3-setuptools pipenv \
                    gnome-shell-extension-autohidetopbar fd-find

step "Get jb font"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/install_manual.sh)"

step "Get micro"
curl https://getmic.ro | bash
sudo mv micro /usr/bin/

step "Get GDB dashboard"
wget -P ~ https://git.io/.gdbinit

step "Get theme"
git clone https://github.com/dracula/gnome-terminal
echo -e -n "1 \n YES \n 1 \n YES" | ./gnome-terminal/install.sh
aria2c https://github.com/dracula/gtk/archive/master.zip -o dracula_theme.zip
mkdir -p ${HOME}/.themes/ && unzip -d ${HOME}/.themes/ dracula_theme.zip && mv -f ${HOME}/.themes/gtk-master ${HOME}/.themes/Dracula
aria2c https://github.com/dracula/gtk/files/5214870/Dracula.zip -o dracula_icon.zip
mkdir -p ${HOME}/.icons/ && unzip -d ${HOME}/.icons/ dracula_icon.zip && rm dracula_icon.zip
# Get dracula-gedit
GEDIT_DIR=${HOME}/.local/share/gedit/styles
mkdir -p ${GEDIT_DIR}
aria2c https://raw.githubusercontent.com/dracula/gedit/master/dracula.xml -d ${GEDIT_DIR}

step "Tweak theme and terminal"
gsettings set org.gnome.desktop.interface gtk-theme "Dracula"
gsettings set org.gnome.desktop.wm.preferences theme "Dracula"
gsettings set org.gnome.desktop.interface icon-theme "Dracula"
gsettings set org.gnome.desktop.interface font-name "Roboto Condensed, 14"
gsettings set org.gnome.desktop.interface document-font-name "Roboto Slab 14"
gsettings set org.gnome.desktop.interface monospace-font-name "JetBrains Mono 14"
gsettings set org.gnome.desktop.wm.preferences titlebar-font "Roboto Condensed, Bold 14"
gsettings set org.gnome.desktop.interface enable-animations false
gsettings set org.gnome.shell enabled-extensions "['hidetopbar@mathieu.bidon.ca']"
gsettings set org.gnome.shell.extensions.dash-to-dock dock-position BOTTOM
gsettings set org.gnome.shell.extensions.dash-to-dock show-apps-at-top true
gsettings set org.gnome.shell favorite-apps "['firefox.desktop', 'org.gnome.Nautilus.desktop', 'jetbrains-toolbox.desktop']"
PROFILE_ID=$( gsettings get org.gnome.Terminal.ProfilesList default | xargs echo )
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/use-system-font false
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/font "'JetBrains Mono 14'"
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/scroll-on-output true
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/scrollback-unlimited true
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/use-transparent-background true
dconf write /org/gnome/terminal/legacy/profiles:/:${PROFILE_ID}/background-transparency-percent 10
dconf write /org/gnome/desktop/interface/gtk-im-module "'ibus'"
dconf write /org/gnome/desktop/input-sources/sources "[('ibus', 'chewing'), ('xkb', 'us')]"
dconf write /org/gnome/gedit/preferences/editor/scheme "'dracula'"
dconf write /org/gnome/desktop/session/idle-delay "uint32 900"

step "Get oh-my-zsh"
sh -c "$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)" "" --unattended
git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git ${HOME}/.oh-my-zsh/plugins/zsh-autosuggestions
git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${HOME}/.oh-my-zsh/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
git clone --depth=1 https://github.com/MichaelAquilina/zsh-you-should-use.git $HOME/.oh-my-zsh/custom/plugins/you-should-use

step "Configure tmux"
git clone --depth=1 https://github.com/gpakosz/.tmux.git ${HOME}/.tmux
ln -s -f ${HOME}/.tmux/.tmux.conf ${HOME}

step "clean up"
# sudo update-alternatives --set cc /usr/bin/clang
# sudo update-alternatives --set c++ /usr/bin/clang++
sudo apt update
sudo apt autoremove -y
sudo apt autoclean
sudo chsh -s /bin/zsh ${USER}
cp .nanorc .tmux.conf.local .p10k.zsh .zshrc ${HOME}/
