FROM ubuntu:20.04
COPY install-worker.sh /tmp/install-worker.sh
RUN apt-get -y -qq update && \
	apt-get install -y unzip && \
  apt-get install -y curl && \
  apt-get install -y jq && \
  apt-get install -y sudo && \
	apt-get clean 

#RUN /tmp/install-worker.sh demo 127.0.0.1 127.0.0.1
