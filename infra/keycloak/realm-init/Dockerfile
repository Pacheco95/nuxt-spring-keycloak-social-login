# Reuse the Keycloak image so we get kcadm.sh for free, then drop in our
# bootstrap script. Runs once on `docker compose up`, exits when done.
FROM quay.io/keycloak/keycloak:26.0

USER 1000
COPY --chown=1000:0 bootstrap-realm.sh /opt/keycloak/bootstrap-realm.sh

ENTRYPOINT ["/bin/sh", "/opt/keycloak/bootstrap-realm.sh"]
