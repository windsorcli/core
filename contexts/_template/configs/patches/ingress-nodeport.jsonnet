{
  apiVersion: 'v1',
  kind: 'Service',
  metadata: {
    name: 'ingress-nginx-controller',
    namespace: 'ingress-nginx',
    labels: {
      'local-dev/patched': 'true',
    },
  },
}

