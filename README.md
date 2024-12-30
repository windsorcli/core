# core

Core configurations used as the basis for most blueprints

### Install Windsor on MacOS

To install Windsor, use the following commands:

```bash
curl -L -o /usr/local/bin/windsor https://github.com/windsorcli/cli/releases/download/v0.2.0/windsor-darwin-arm64
```

```bash
chmod +x /usr/local/bin/windsor
```

# Self Hosted Runner

## Local ubuntu server

```
ssh forest-shadows-runner
```

## GitHub Runner Setup

https://github.com/organizations/windsorcli/settings/actions/runners/new?arch=x64&os=linux


### Start the runner

```
cd actions-runner;run.sh
```
