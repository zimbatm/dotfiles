{ ... }:
{
  # pi auto-discovers *.ts and subdir/index.ts from ~/.pi/agent/extensions/.
  # recursive=true symlinks individual files, leaving the directory writable so
  # ad-hoc extensions can still be dropped alongside without home-manager
  # complaining.
  home.file.".pi/agent/extensions" = {
    source = ./files;
    recursive = true;
  };
}
