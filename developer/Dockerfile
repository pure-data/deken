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

# install all the required stuff
COPY requirements.txt /tmp
RUN mkdir -p /usr/local/bin/ /usr/local/share/deken/ ~/.deken \
	&& pip install --no-cache-dir --trusted-host pypi.python.org -r /tmp/requirements.txt \
	&& rm /tmp/requirements.txt \
	&& deken systemfix --all
