{ pkgs, ... }:
{
  imports = [ ../terminal ];

  programs.firefox.enable = true;
  programs.vscode.enable = true;

  home.packages = with pkgs; [
    # Graphical
    brave
    discord
    element-desktop
    joplin-desktop
    signal-desktop
    slack
    tdesktop # telegram desktop
    termite
    vlc
    zed-editor
    zoom-us

    # KDE stuff
    kdePackages.filelight
    kdePackages.okular
  ];
}
