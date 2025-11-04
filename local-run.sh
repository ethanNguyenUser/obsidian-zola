#!/bin/bash

# Detect macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
	IS_MACOS=true
else
	IS_MACOS=false
fi

# Check for python-is-python3 installed
if ! command -v python &>/dev/null; then
	echo "It appears you do not have python-is-python3 installed"
	exit 1
fi

# Check for zola being installed
if ! command -v zola &>/dev/null; then
	echo "zola could not be found please install it from https://www.getzola.org/documentation/getting-started/installation"
	exit 1
fi

# Check for obsidian-export
if [[ "$IS_MACOS" == true ]]; then
	# On macOS, use obsidian-export from PATH or common installation locations
	OBSIDIAN_EXPORT_CMD=""
	if command -v obsidian-export &>/dev/null; then
		OBSIDIAN_EXPORT_CMD="obsidian-export"
	elif [[ -f "$HOME/.cargo/bin/obsidian-export" ]]; then
		# Check common cargo installation location
		OBSIDIAN_EXPORT_CMD="$HOME/.cargo/bin/obsidian-export"
	elif [[ -f "/opt/homebrew/bin/obsidian-export" ]]; then
		# Check Homebrew location (Apple Silicon)
		OBSIDIAN_EXPORT_CMD="/opt/homebrew/bin/obsidian-export"
	elif [[ -f "/usr/local/bin/obsidian-export" ]]; then
		# Check Homebrew location (Intel)
		OBSIDIAN_EXPORT_CMD="/usr/local/bin/obsidian-export"
	fi
	
	if [[ -z "$OBSIDIAN_EXPORT_CMD" ]]; then
		echo "obsidian-export not found. On macOS, please install it using:"
		echo "  cargo install obsidian-export"
		echo "  (Then ensure ~/.cargo/bin is in your PATH, or restart your terminal)"
		echo "  or"
		echo "  brew install obsidian-export"
		exit 1
	fi
else
	# On Linux, use the bundled binary
	OBSIDIAN_EXPORT_CMD="bin/obsidian-export"
	if [[ ! -f "$OBSIDIAN_EXPORT_CMD" ]]; then
		echo "obsidian-export binary not found at $OBSIDIAN_EXPORT_CMD"
		exit 1
	fi
fi

# Check for correct slugify package
PYTHON_ERROR=$(eval "python -c 'from slugify import slugify; print(slugify(\"Test String One\"))'" 2>&1)

if [[ $PYTHON_ERROR != "test-string-one" ]]; then
	if [[ $PYTHON_ERROR =~ "NameError" ]]; then
		echo "It appears you have the wrong version of slugify installed, the required pip package is python-slugify"
	else
		echo "It appears you do not have slugify installed. Install it with 'pip install python-slugify'"
	fi
	exit 1
fi

# Check for rtoml package
PYTHON_ERROR=$(eval "python -c 'import rtoml'" 2>&1)

if [[ $PYTHON_ERROR =~ "ModuleNotFoundError" ]]; then
	echo "It appears you do not have rtoml installed. Install it with 'pip install rtoml'"
	exit 1
fi

# Check that the vault got set
if [[ -z "${VAULT}" ]]; then
	if [[ -f ".vault_path" ]]; then
		export VAULT=$(cat .vault_path)
	else
		echo "Path to the obsidian vault is not set, please set the path using in the $(.vault_path) file or $VAULT env variable"
		exit 1
	fi
fi

# Pull environment variables from the vault's netlify.toml when building (by generating env.sh to be sourced)
python env.py

# Set the site and repo url as local since locally built
export SITE_URL=local
export REPO_URL=local

# Remove previous build and sync Zola template contents
rm -rf build
rsync -a zola/ build
rsync -a content/ build/content

# Fix config.toml for local Zola version compatibility
# Zola 0.19+ uses generate_feeds (plural), but Netlify uses 0.15.2 which uses generate_feed (singular)
# Zola 0.21+ removed render_emoji field (it's now always enabled)
ZOLA_VERSION=$(zola --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "")
if [[ -n "$ZOLA_VERSION" ]]; then
	MAJOR_VERSION=$(echo "$ZOLA_VERSION" | cut -d. -f1)
	MINOR_VERSION=$(echo "$ZOLA_VERSION" | cut -d. -f2)
	if [[ $MAJOR_VERSION -gt 0 ]] || [[ $MAJOR_VERSION -eq 0 && $MINOR_VERSION -ge 19 ]]; then
		# Zola 0.19+ needs generate_feeds (plural)
		if [[ "$OSTYPE" == "darwin"* ]]; then
			# macOS sed syntax
			sed -i '' 's/^generate_feed =/generate_feeds =/' build/config.toml
		else
			# Linux sed syntax
			sed -i 's/^generate_feed =/generate_feeds =/' build/config.toml
		fi
	fi
	if [[ $MAJOR_VERSION -gt 0 ]] || [[ $MAJOR_VERSION -eq 0 && $MINOR_VERSION -ge 21 ]]; then
		# Zola 0.21+ removed render_emoji (it's always enabled)
		if [[ "$OSTYPE" == "darwin"* ]]; then
			# macOS sed syntax - remove the render_emoji line
			sed -i '' '/^render_emoji =/d' build/config.toml
		else
			# Linux sed syntax
			sed -i '/^render_emoji =/d' build/config.toml
		fi
	fi
fi

# Use obsidian-export to export markdown content from obsidian
mkdir -p build/content/docs build/__docs
# Newer versions of obsidian-export use positional arguments: source destination
# Note: --frontmatter flag uses space-separated value, not equals sign
if [ -z "$STRICT_LINE_BREAKS" ]; then
	$OBSIDIAN_EXPORT_CMD --frontmatter never --hard-linebreaks --no-recursive-embeds "$VAULT" build/__docs
else
	$OBSIDIAN_EXPORT_CMD --frontmatter never --no-recursive-embeds "$VAULT" build/__docs
fi

# Run conversion script
source env.sh && python convert.py && rm env.sh

# Serve Zola site
zola --root=build serve
