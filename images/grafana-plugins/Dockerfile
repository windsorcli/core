# Grafana plugins that core mounts as an image volume, one directory for each plugin.
# Run task grafana:plugins after each change to this file.

FROM --platform=$BUILDPLATFORM docker.io/library/alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS fetch

# Each plugin MUST support the Grafana version in kustomize/observability/install/grafana/helm-release.yaml.
# renovate: datasource=github-releases depName=quickwit-oss/quickwit-datasource
ARG QUICKWIT_VERSION=0.6.3
ARG QUICKWIT_SHA256=0d5b7ef8298e7b421613dda3d84185fde80a595ba3ff75d0d22e9dcb17bdd18f

RUN set -eu; \
    fetch() { \
      wget -q -O /tmp/plugin.zip "$2"; \
      echo "$3  /tmp/plugin.zip" | sha256sum -c -; \
      unzip -q /tmp/plugin.zip -d /plugins; \
      rm /tmp/plugin.zip; \
      test -f "/plugins/$1/plugin.json"; \
    }; \
    mkdir /plugins; \
    fetch quickwit-quickwit-datasource "https://github.com/quickwit-oss/quickwit-datasource/releases/download/v${QUICKWIT_VERSION}/quickwit-quickwit-datasource-${QUICKWIT_VERSION}.zip" "$QUICKWIT_SHA256"

FROM scratch
COPY --from=fetch /plugins/ /
