FROM bitnami/kubectl:latest@sha256:d7e2de67927af4b644c0631e114024e32062ffde7af8e6af1be532eda91656b0

USER root

COPY kubectl/files/envplate /usr/bin/envplate

RUN chmod a+x /usr/bin/envplate

USER 1001

ENTRYPOINT [ "" ]
