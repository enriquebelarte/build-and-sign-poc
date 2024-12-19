ARG DTK_IMAGE
ARG SIGNER_SDK_IMAGE
ARG DRIVER_IMAGE
ARG AWS_AUTH_SECRET
FROM ${DTK_IMAGE} as dtk
ARG DRIVER_REPO
WORKDIR /home/builder
COPY --chmod=0755 build-commands.sh /home/builder/build-commands.sh
RUN git clone $DRIVER_REPO && cd $(basename $DRIVER_REPO .git) && \
    /home/builder/build-commands.sh

FROM ${SIGNER_SDK_IMAGE} as signer
ARG AWS_AUTH_SECRET
ARG AWS_DEFAULT_REGION
ARG AWS_KMS_KEY_LABEL
ARG AWS_KMS_TOKEN
USER root
COPY --from=dtk /home/builder /opt/drivers/
COPY --from=dtk /usr/src/kernels/5.14.0-503.15.1.el9_5.x86_64/scripts/sign-file /usr/local/bin/sign-file
COPY --chmod=0755 enable_kms_pkcs11 /usr/bin/enable_kms_pkcs11
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_KMS_TOKEN echo "export AWS_KMS_TOKEN="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_KMS_TOKEN) >> /tmp/envfile 
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_ACCESS_KEY_ID echo "export AWS_ACCESS_KEY_ID="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_ACCESS_KEY_ID) >> /tmp/envfile
RUN --mount=type=secret,id=${AWS_AUTH_SECRET}/AWS_SECRET_ACCESS_KEY echo "export AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/${AWS_AUTH_SECRET}/AWS_SECRET_ACCESS_KEY) >> /tmp/envfile
ENV AWS_KMS_KEY_LABEL=$AWS_KMS_KEY_LABEL
ENV AWS_KMS_TOKEN=$AWS_KMS_TOKEN
ENV AWS_DEFAULT_REGION=$AWS_DEFAULT_REGION
RUN source /tmp/envfile && \
    cat <<EOF > /etc/aws-kms-pkcs11/config.json
{
  "slots": [
    {
      "label": "$AWS_KMS_KEY_LABEL",
      "kms_key_id": "$AWS_KMS_TOKEN",
      "aws_region": "$AWS_DEFAULT_REGION",
      "certificate_path": "/etc/aws-kms-pkcs11/cert.pem"
     }
           ]
}
EOF
RUN cat /etc/aws-kms-pkcs11/config.json
RUN source /tmp/envfile && \
    env && \
    bash -x /bin/enable_kms_pkcs11 && \
    oot_modules="/opt/drivers/" && \
    find "$oot_modules" -type f -name "*.ko" | while IFS= read -r file; do \
        signedfile="${oot_modules}$(basename "${file%.*}")-signed.ko"; \
        sign-file sha256 \
            "pkcs11:model=0;manufacturer=aws_kms;serial=0;token=$AWS_KMS_KEY_LABEL" \
            /etc/aws-kms-pkcs11/cert.pem \
            "$file" \
            "$signedfile"; \
    done	   
FROM ${DRIVER_IMAGE}
COPY --from=signer /opt/drivers /opt/drivers
