# core
Core configurations used as the basis for most blueprints

![CI Workflow](https://github.com/your-repo/core/actions/workflows/ci.yaml/badge.svg)

# 1Password
## Blueprint Settings
```
- name: secrets-base
  path: secrets/base
- name: 1password-connect
  path: secrets/1password/connect
  dependsOn:
  - secrets-base
  force: true
- name: 1password-secrets-injector
  path: secrets/1password/secrets-injector
  dependsOn:
  - secrets-base
  force: true
```
