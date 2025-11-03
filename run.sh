#!/bin/bash

pip install python-slugify

# Avoid copying over netlify.toml (will ebe exposed to public API)
echo "netlify.toml" >>__obsidian/.gitignore

# Sync Zola template contents
rsync -a __site/zola/ __site/build
rsync -a __site/content/ __site/build/content

# Use obsidian-export to export markdown content from obsidian
mkdir -p __site/build/content/docs __site/build/__docs

# Ensure obsidian-export exists (download Linux binary on Netlify if missing)
if [ ! -x "__site/bin/obsidian-export" ]; then
    echo "obsidian-export not found; downloading Linux binary..."
    mkdir -p __site/bin
    TMPDIR=$(mktemp -d)
    # Try to fetch latest Linux x86_64 asset URL from GitHub Releases
    OBS_URL=$(curl -s https://api.github.com/repos/zoni/obsidian-export/releases/latest \
        | grep browser_download_url \
        | grep -E 'x86_64.*linux|x86_64-unknown-linux-gnu' \
        | sed -E 's/.*"(https:[^"]+)".*/\1/' \
        | head -n1)

    if [ -z "$OBS_URL" ]; then
        echo "Failed to locate obsidian-export Linux binary download URL." >&2
        echo "Please ensure __site/bin/obsidian-export is present in the repository." >&2
        exit 1
    fi

    echo "Downloading: $OBS_URL"
    curl -L "$OBS_URL" -o "$TMPDIR/obsidian-export.tar.xz"
    tar -xf "$TMPDIR/obsidian-export.tar.xz" -C "$TMPDIR"
    BIN_PATH=$(find "$TMPDIR" -type f -name obsidian-export | head -n1)
    if [ -z "$BIN_PATH" ]; then
        echo "Downloaded archive did not contain obsidian-export binary." >&2
        exit 1
    fi
    cp "$BIN_PATH" "__site/bin/obsidian-export"
    chmod +x "__site/bin/obsidian-export"
    rm -rf "$TMPDIR"
fi
if [ -z "$STRICT_LINE_BREAKS" ]; then
	__site/bin/obsidian-export --frontmatter=never --hard-linebreaks --no-recursive-embeds __obsidian __site/build/__docs
else
	__site/bin/obsidian-export --frontmatter=never --no-recursive-embeds __obsidian __site/build/__docs
fi

# Run conversion script
python __site/convert.py

# Build Zola site
zola --root __site/build build --output-dir public
