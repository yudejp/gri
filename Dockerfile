FROM ruby:3.1-slim  

RUN apt-get update && apt-get install -y --no-install-recommends git rrdtool ca-certificates && \
    rm -rf /var/lib/apt/lists/*  

RUN gem install webrick --no-document && \
  gem install rack -v "~> 2.2" --no-document

COPY . /tmp/gri

WORKDIR /tmp/gri
RUN gem build *.gemspec && \
  gem install ./*.gem --no-document --ignore-dependencies && \
    rm -rf /tmp/gri

RUN useradd -m -s /bin/bash gri && \  
  mkdir -p /usr/local/gri && \  
  chown gri:gri /usr/local/gri  

WORKDIR /usr/local/gri  
  
COPY --chown=gri:gri <<EOF ./gri.conf
root-dir    /usr/local/gri
gritab-path /usr/local/gri/gritab
font        DEFAULT:0:IPAPGothic
EOF

EXPOSE 9292  

USER gri  

CMD while true; do /usr/local/bundle/bin/gri; sleep 60; done
