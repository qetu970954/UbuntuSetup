Set-ExecutionPolicy RemoteSigned -scope CurrentUser

iwr -useb get.scoop.sh | iex # Download scoop

scoop bucket add extras

scoop bucket add nerd-fonts

scoop install sudo

sudo scoop install 7zip git openssh jetbrains-mono --global

scoop install aria2 
scoop install curl grep sed less netcat micro touch bat fzf ripgrep fd zoxide delta
scoop python@3.8.10

# to make zoxide work on powershell start
@'
Invoke-Expression (& {
    $hook = if ($PSVersionTable.PSVersion.Major -lt 6) { 'prompt' } else { 'pwd' }
    (zoxide init --hook $hook powershell) -join "`n"
})
'@ | Add-Content -Path (echo $profile)


