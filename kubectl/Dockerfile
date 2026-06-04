FROM bitnami/kubectl:latest@sha256:172d4889e49c3b66d91a3a5afc289448fa1407dda782b9817ccfd8d1b064660b

USER root

COPY kubectl/files/envplate /usr/bin/envplate

RUN chmod a+x /usr/bin/envplate

USER 1001

ENTRYPOINT [ "" ]
