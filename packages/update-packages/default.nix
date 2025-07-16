{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "update-packages";
  runtimeInputs = with pkgs; [
    nix-update
    git
    jq
    curl
  ];
  text = ''
    set -euo pipefail

    # Get the flake directory
    flake_dir="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"
    cd "$flake_dir"

    # Check if specific packages were provided
    if [ $# -gt 0 ]; then
        # Use provided packages
        packages=("$@")
        echo "Updating specified packages: ''${packages[*]}"
    else
        # Get all packages from the flake
        echo "Updating all packages in the flake..."
        mapfile -t packages < <(nix eval --json --impure .#packages.x86_64-linux --apply 'builtins.attrNames' | jq -r '.[]')
    fi
    echo

    # Track results
    updated=()
    failed=()
    already_uptodate=()

    for pkg in "''${packages[@]}"; do
        echo "Checking $pkg..."
        
        # Skip packages that are not meant to be updated
        case "$pkg" in
            update-packages|default)
                echo "  Skipping $pkg"
                continue
                ;;
        esac

        # Check if package has a custom update script first
        if [ -f "packages/$pkg/update.sh" ]; then
            echo "  Found custom update script, running..."
            if "packages/$pkg/update.sh"; then
                updated+=("$pkg")
                echo "  ✓ Updated successfully (custom script)"
            else
                failed+=("$pkg")
                echo "  ✗ Failed to update (custom script)"
            fi
        else
            # Fall back to nix-update
            if output=$(nix-update --flake --version=stable "$pkg" 2>&1); then
                if echo "$output" | grep -q "Package already up to date"; then
                    already_uptodate+=("$pkg")
                    echo "  ✓ Already up to date"
                else
                    updated+=("$pkg")
                    echo "  ✓ Updated successfully"
                fi
            else
                failed+=("$pkg")
                echo "  ✗ Failed to update"
            fi
        fi
        echo
    done

    # Summary
    echo "Update Summary:"
    echo "==============="

    if [ ''${#updated[@]} -gt 0 ]; then
        echo "Updated (''${#updated[@]}):"
        printf "  - %s\n" "''${updated[@]}"
    fi

    if [ ''${#already_uptodate[@]} -gt 0 ]; then
        echo "Already up to date (''${#already_uptodate[@]}):"
        printf "  - %s\n" "''${already_uptodate[@]}"
    fi

    if [ ''${#failed[@]} -gt 0 ]; then
        echo "Failed (''${#failed[@]}):"
        printf "  - %s\n" "''${failed[@]}"
        echo
        echo "Note: Some packages may need manual intervention or custom update scripts."
    fi

    if [ ''${#updated[@]} -gt 0 ]; then
        echo
        echo "Don't forget to:"
        echo "  1. Review the changes: git diff"
        echo "  2. Build updated packages: nix build .#packages.x86_64-linux.<package>"
        echo "  3. Commit the updates"
    fi
  '';
}
