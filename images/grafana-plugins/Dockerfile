# Grafana plugins that core mounts as an image volume, one directory for each plugin.
# Run task grafana:plugins after each change to this file.

FROM --platform=$BUILDPLATFORM docker.io/library/alpine:3.24.4@sha256:f59abe656b692d901e184be3445e084786602108599d2a51d229c0f5a48c71bf AS fetch

# Each plugin MUST support the Grafana version in kustomize/observability/install/grafana/helm-release.yaml.
# renovate: datasource=github-releases depName=quickwit-oss/quickwit-datasource
ARG QUICKWIT_VERSION=0.6.3
ARG QUICKWIT_SHA256=0d5b7ef8298e7b421613dda3d84185fde80a595ba3ff75d0d22e9dcb17bdd18f
# renovate: datasource=github-releases depName=grafana/metrics-drilldown
ARG METRICSDRILLDOWN_VERSION=3.0.0
ARG METRICSDRILLDOWN_SHA256=413f162e141b3eefce04511300b0cc1b60da51069a5517f6c02b7a36b87d3667
# renovate: datasource=github-releases depName=grafana/grafana-advisor-app
ARG ADVISOR_VERSION=1.1.3
ARG ADVISOR_SHA256=144d17028d169332b577f6e3ab6c2aa6cec102b82c1e86bffd2454a02cdd3c3a

RUN set -eu; \
    fetch() { \
      wget -q -O /tmp/plugin.zip "$2"; \
      echo "$3  /tmp/plugin.zip" | sha256sum -c -; \
      unzip -q /tmp/plugin.zip -d /plugins; \
      rm /tmp/plugin.zip; \
      test -f "/plugins/$1/plugin.json"; \
    }; \
    mkdir /plugins; \
    fetch quickwit-quickwit-datasource "https://github.com/quickwit-oss/quickwit-datasource/releases/download/v${QUICKWIT_VERSION}/quickwit-quickwit-datasource-${QUICKWIT_VERSION}.zip" "$QUICKWIT_SHA256"; \
    fetch grafana-metricsdrilldown-app "https://grafana.com/api/plugins/grafana-metricsdrilldown-app/versions/${METRICSDRILLDOWN_VERSION}/download" "$METRICSDRILLDOWN_SHA256"; \
    fetch grafana-advisor-app "https://grafana.com/api/plugins/grafana-advisor-app/versions/${ADVISOR_VERSION}/download" "$ADVISOR_SHA256"

FROM scratch
COPY --from=fetch /plugins/ /
