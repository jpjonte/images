FROM bitnami/kubectl:latest

USER root

COPY kubectl/files/envplate /usr/bin/envplate

RUN chmod a+x /usr/bin/envplate

USER 1001

ENTRYPOINT [ "" ]
