from os import environ
from pathlib import Path
import sys

import rtoml

if __name__ == "__main__":
    netlify_toml_path = Path(environ["VAULT"]) / "netlify.toml"
    
    # Create empty env.sh file first
    with open("env.sh", "w") as f:
        pass
    
    # Try to load netlify.toml if it exists (for local testing, it might not)
    if netlify_toml_path.exists():
        try:
            env_vars = rtoml.load(netlify_toml_path)["build"]["environment"]
            with open("env.sh", "a") as f:
                for k, v in env_vars.items():
                    val = v.replace("'", "'\\''")
                    print(f"export {k}='{val}'", file=f)
        except (KeyError, TypeError) as e:
            # If netlify.toml exists but doesn't have the expected structure, warn but continue
            print(f"Warning: Could not parse netlify.toml structure: {e}", file=sys.stderr)
    else:
        # For local testing without netlify.toml, create empty env.sh
        # The local-run.sh script will set SITE_URL=local and REPO_URL=local anyway
        pass
