# dirless-ops — build targets

# List available recipes
default:
    @just --list

# Build everything
build: build-api build-webui build-cli

# Build the Grip JSON API binary
build-api:
    crystal build src/dirless_ops.cr -o dirless-ops --release

# Build the one-shot migration binary (run once after merging customers+customer_accounts)
build-migrate:
    crystal build src/dirless_ops_migrate.cr -o dirless-ops-migrate --release

# Build the Lucky web UI binary
build-webui:
    cd webui && shards install && crystal build src/dirless_ops_webui.cr -o dirless-ops-webui --release

# Build the ops CLI binary (release — optimised + stripped)
build-cli:
    cd cli && shards install && crystal build src/dirless_ops_cli.cr -o dirless-ops-cli --release --no-debug
    strip cli/dirless-ops-cli

# Build the ops CLI (debug, no --release — faster compile, larger binary)
build-cli-debug:
    cd cli && crystal build src/dirless_ops_cli.cr -o dirless-ops-cli

# Install the CLI to /usr/local/bin (run after build-cli)
install-cli: build-cli
    sudo install -m 755 cli/dirless-ops-cli /usr/local/bin/dirless-ops-cli
    @echo "Installed: /usr/local/bin/dirless-ops-cli"

# Lint the CLI source
lint-cli:
    cd cli && bin/ameba src/

# Show built binary versions
versions:
    @test -f dirless-ops && ./dirless-ops --version || echo "dirless-ops: not built"
    @test -f cli/dirless-ops-cli && ./cli/dirless-ops-cli version || echo "dirless-ops-cli: not built"
