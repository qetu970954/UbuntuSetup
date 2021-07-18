Set-ExecutionPolicy RemoteSigned -scope CurrentUser

iwr -useb get.scoop.sh | iex # Download scoop

scoop bucket add extras

scoop install sudo

sudo scoop install 7zip git openssh --global

scoop install aria2 curl grep sed less netcat micro touch bat fzf ripgrep fd zoxide delta nu

# nu = nushell, see 'https://github.com/nushell/nushell/'
# Use this on windows to replace ugly powershell cmds

# Initiate zoxide
Invoke-Expression (& {
    $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell) -join "`n"
})

