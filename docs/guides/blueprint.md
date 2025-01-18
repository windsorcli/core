# Blueprint Guidelines

A blueprint is a description of, and a plan to, deploy a cloud infrastructure that includes the necessary configuration, secrets, code, tests, and documentation to support production grade deployments.  

A blueprint template describes the contents of a blueprint repository and is used to define and guide the creation of blueprint repositories.

A blueprint repository is a source code repository that is structured according to the blueprint guidelines.  Each blueprint repository will contain some or most of the contents of the blueprint template and will be in compliance with blueprint guidelines. 

## Blueprint Contents

A typical blueprint contains many of the files and folders shown here.

```
.
├── LICENSE                   // Standard files
├── README.md
├── Taskfile.yaml             
├── aqua.yaml                 // Dependency files
├── pyproject.toml
├── terraform                 // Code
├── kustomize
├── docs                      // Documentation
├── test                      // Test
└── .github                   // CI/CD
  ├── workflows
  |   ├── ci.yaml
  |   ├── enforce-pr-labels.yaml
  |   └── release-drafter.yaml
  ├── release-drafter.yml
  └── renovate.json
```

### Standard Files

The standard files include the LICENSE file and the README.md. 

### Dependency Files

aqua.yaml and pyproject.toml are the default dependency files.

The dependency files contain tool and package dependency information.  The default dependency tools used in the blueprint is Aqua for tool version management and Poetry for python package management.

### Code

The cloud infrastructure code is defined in the terraform and/or the kustomize folders. 

### Documenation

The documentation is created in markdown language and typically is included in a larger documentation deployment.  Internal tools such as the windsorcli.github.io repository are used to deploy the documentation to the gh-pages.

### Test

The test folder contains all the tests that are executed each time the repository is changed.

### CI/CI

The CI/CD files contain github actions

- Automated testing (unit/integration/performance)
- Linting and style checks
- Code scans
- PR Labeling Rules
- Release drafting
- Renovate

# Creating Windsor Blueprints

See [Creating a repository from a template](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-repository-from-a-template)


```
gh repo create --template https://github.com/windsorcli/blueprint.git <repo-name>
```