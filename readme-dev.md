This package uses the bundled `@openai/codex` dependency by default.
Set `CODEX_PATH` to run a different Codex binary; versions other than the one specified in `package.json` may not be compatible.

### Runtime environment

- `CODEX_API_KEY` - API key used when the API-key auth method is selected. Takes precedence over `OPENAI_API_KEY`.
- `OPENAI_API_KEY` - fallback API key used when the API-key auth method is selected.
- `CODEX_PATH` - run a specific Codex executable instead of the bundled package dependency.
- `CODEX_CONFIG` - JSON object merged into the Codex session config.
- `MODEL_PROVIDER` - model provider to pass to Codex for new sessions.
- `DEFAULT_AUTH_REQUEST` - ACP auth request JSON used when Codex requires authentication.
- `INITIAL_AGENT_MODE` - initial mode id: `read-only`, `agent`, or `agent-full-access`.
- `NO_BROWSER` - hide browser-based ChatGPT auth when set.
- `APP_SERVER_LOGS` - directory for adapter logs.

### Quick start

#### Develop on Windows?

- Download and install [C++ redistributable package](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#latest-supported-redistributable-version)

#### Adjust ACP client config

Run from sources

1. Install dependencies `npm install`
2. Adjust ACP client config

```json
{
  "agent_servers": {
    "Codex (app-server)": {
      "command": "npm",
      "args": ["run", "start", "--prefix", "/path/to/project/"],
      "env": {
        "CODEX_PATH": "node_modules/.bin/codex",
        "APP_SERVER_LOGS": "optional/path/to/existing/log/directory"
      }
    }
  }
}
```

Run from binaries

1. Download a `codex-acp-<platform>.zip` archive from https://github.com/agentclientprotocol/codex-acp/releases (`<platform>` is one of: `linux`, `darwin`, `win32`)
2. Unzip the archive:
   ```bash
   unzip codex-acp-<platform>.zip
   ```
3. Adjust ACP client config

```json
{
  "agent_servers": {
    "Codex (app-server)": {
      "command": "/path/to/codex-acp",
      "env": {
        "CODEX_PATH": "/path/to/codex"
      }
    }
  }
}
```

### Build binaries

Building standalone binaries requires [bun](https://bun.com/docs/installation).

Build single-file executables in `dist/bin` directory:

```bash
npm run bundle:all
```

Package binaries into zip archives:

```bash
npm run package:all
```

### Update supported Codex version

1. Update the `@openai/codex` version in `package.json` (under `dependencies`).
2. Regenerate Codex types in `src/app-server/`: `npm run generate-types`
3. Ensure there are no type errors or failed tests: `npm run typecheck` and `npm run test`


## Local Studio installation for Buzz

Select a reviewed commit in a clean checkout on the Studio. Build and check it
locally with the existing Buzz-managed Node runtime (`npm ci`,
`npm run typecheck`, `npm test`, `npm run build`). This is an operator action;
GitHub does not execute PR code in the personal macOS account.

Assemble the complete runtime in a new staging directory:

```bash
staging_root="$(mktemp -d -t codex-acp-install)"
runtime_tree="$staging_root/runtime"
mkdir "$runtime_tree"
cp package.json package-lock.json README.md LICENSE "$runtime_tree/"
cp -R dist "$runtime_tree/"
(cd "$runtime_tree" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)
```

Finish existing ACP sessions and quit Buzz normally before installation. The
script rejects a running Buzz/adapter and makes no attempt to stop processes.
Run as `tobiasschluter` on the arm64 Studio with the full selected commit:

```bash
SOURCE_SHA=<full-reviewed-commit> STAGING_ROOT="$staging_root" \
  DEPLOY_TREE="$runtime_tree" scripts/deploy-buzz-desktop-adapter.sh deploy
```

The installer requires a clean tracked source tree, verifies the runtime against
the selected build, preserves the complete previous package under Buzz's
`adapter-backups/codex-acp`, and reports the backup name, installed version and
bundle SHA256. On installation failure it restores the previous package. Open
Buzz normally after success and verify the real ACP client before retiring the
old runner. No authentication or application data is replaced.

To roll back, quit Buzz and use a fresh staging directory plus the reported
backup name. The current installation is retained as another backup:

```bash
SOURCE_SHA=<full-reviewed-commit> STAGING_ROOT="$(mktemp -d -t codex-acp-rollback)" \
  BACKUP_NAME=<reported-backup-name> scripts/deploy-buzz-desktop-adapter.sh rollback
```

The commit selects the installer source; rollback selects the preserved runtime.
Inspect a failed staging tree before removing it. There is no automatic pruning.
