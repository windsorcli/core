# Core Blueprint Guidelines

The Core Blueprint Guideline document is a description of, and a plan to, deploy a cloud infrastructure that includes the necessary configuration, secrets, code, tests, and documentation to support production grade deployments.  

A blueprint template describes the contents of a blueprint repository and is used to define and guide the creation of blueprint repositories.

A blueprint repository is a source code repository that is structured according to the blueprint guidelines.  Each blueprint repository will contain some or most of the contents of the blueprint template and will be in compliance with blueprint guidelines. 

## Blueprint Contents

A typical blueprint contains many of the files and folders shown here.

```
.
├── LICENSE                   // Standard files
├── README.md
├── aqua.yaml                 // Dependency files
├── terraform                 // Code
├── kustomize
├── docs                      // Documentation
├── test                      // Test
└── .github                   // CI/CD
```

# Included Components

[TODO] Add a description of the additional components added to the core
