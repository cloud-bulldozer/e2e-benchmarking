FROM quay.io/openshifttest/python:3.9

LABEL vendor="Red Hat Inc." maintainer="OCP Perfscale Team"

RUN curl -sSL https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.15/openshift-client-linux.tar.gz  | tar -xvzf -  &&\
    mv oc /bin && mv kubectl /bin && apt-get update && apt-get install -y gettext-base uuid-runtime jq && \
    ln -s /bin/bash /usr/bin/bash && /usr/local/bin/python -m pip install --upgrade pip && pip install virtualenv jq

WORKDIR /e2e

RUN chown -R 777 /e2e

CMD cd /e2e && tail -f /dev/null
