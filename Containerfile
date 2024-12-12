ARG DTK_IMAGE
ARG SIGNER_SDK_IMAGE
ARG DRIVER_IMAGE

FROM ${DTK_IMAGE} as dtk
ARG DRIVER_REPO
WORKDIR /home/builder
COPY --chmod=0755 build-commands.sh /home/builder/build-commands.sh
RUN git clone $DRIVER_REPO && cd $(basename $DRIVER_REPO .git) && \
    /home/builder/build-commands.sh

FROM ${SIGNER_SDK_IMAGE} as signer
ARG AWS_AUTH_SECRET
USER root
COPY --from=dtk /home/builder /opt/drivers/
COPY --from=dtk /usr/src/kernels/5.14.0-503.15.1.el9_5.x86_64/scripts/sign-file /usr/local/bin/sign-file
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/data \
    export_env_file=$(mktemp) && \
    yq '.data | to_entries | .[] | "\(.key)=\(.value)"' /run/secrets/${AWS_AUTH_SECRET}/data > $export_env_file && \
    source $export_env_file && \
    echo "AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"	&& \
    echo "KMS=${AWS_KMS_TOKEN}" 
RUN /bin/configure_pkcs.sh
RUN find /opt/drivers -name "*.ko" -exec sign-file {} \;
FROM ${DRIVER_IMAGE}
COPY --from=signer /opt/drivers /opt/drivers
