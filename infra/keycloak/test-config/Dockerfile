# One-shot config patch applied AFTER keycloak-realm-init completes during
# `make test-e2e`. Reuses the Keycloak image (same as realm-init) for kcadm.
FROM quay.io/keycloak/keycloak:26.0

USER 1000
COPY --chown=1000:0 configure-mock-idp.sh /opt/keycloak/configure-mock-idp.sh

ENTRYPOINT ["/bin/sh", "/opt/keycloak/configure-mock-idp.sh"]
