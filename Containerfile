ARG DRIVER_REPO
ARG DTK_IMAGE
ARG DRIVER_IMAGE

FROM ${DTK_IMAGE} as dtk
WORKDIR /home/builder
COPY --chmod=0755 build-commands.sh /home/builder/build-commands.sh
RUN git clone ${DRIVER_REPO} && cd $(basename ${DRIVER_REPO} .git) && \
    /home/builder/build-commands.sh

FROM ${DRIVER_IMAGE}
USER root
COPY --from=dtk /home/builder /opt/drivers/

