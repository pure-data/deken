### runner
# Use an official Python runtime as a parent image
FROM hylang
# Set the working directory to /dekenserver

WORKDIR /deken
# Copy the deken executable onto the image
COPY deken /usr/local/bin/
COPY deken.hy /usr/local/share/deken/

# we are runnign as root, so set this
ENV DEKEN_ROOT=yes
# gpg-signing in the Docker-container is a bit complicated
ENV DEKEN_SIGN_GPG=no

# install all the required stuff
COPY requirements.txt /tmp
RUN apt-get update && apt-get install -y --no-install-recommends gpg && apt-get clean \
	&& pip install --no-cache-dir --trusted-host pypi.python.org -r /tmp/requirements.txt \
	&& pip uninstall -y cryptography pip \
	&& chmod a+rw . \
	&& rm /tmp/requirements.txt \
	&& deken systemfix --all
