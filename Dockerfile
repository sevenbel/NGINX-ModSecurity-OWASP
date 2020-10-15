FROM debian:buster-slim

LABEL author="Manuel Leibetseder" \
    name="Nginx" \
    mail="manuel.leibetseder@seven-bel.com" \
    version=1.3.0

ENV NGINX_VERSION 1.19.3

# Copy the ModSecurity library into the image.
# COPY modsec_lib_amd64 /usr/local/modsecurity
# COPY modsec_lib_arm32v7 /usr/local/modsecurity

# Create Nginx user/group first, to be consistent throughout docker variants.
# Install needed tools and packages to be able to compile ModSecurity and Nginx from source.
RUN set -x \
    && addgroup --system --gid 101 nginx \
    && adduser --system --disabled-login --ingroup nginx --no-create-home --home /nonexistent --gecos "nginx user" --shell /bin/false --uid 101 nginx \
    && DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
    && apt-get install -y apache2-utils wget tar apt-utils autoconf automake build-essential git libcurl4-openssl-dev libgeoip-dev liblmdb-dev libpcre++-dev libtool libxml2-dev libssl-dev libyajl-dev pkgconf zlib1g-dev
	
# Only use this if you want to compile the ModSecurity library from source.
# You can use exactly this command to compile it from source and grab the library from your systems /usr/local/modsec
# and import it as mentioned above.
RUN git clone --depth 1 -b v3/master --single-branch https://github.com/SpiderLabs/ModSecurity \
    && cd ModSecurity \
    && git submodule init \
    && git submodule update \
    && ./build.sh \
    && ./configure --enable-standalone-module \
    && make \
    && make install \
	&& cd /

# Clone the ModSecurity-nginx module and compile Nginx with the module.
RUN git clone --depth 1 https://github.com/SpiderLabs/ModSecurity-nginx.git \
    && wget http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz \
    && tar zxvf nginx-${NGINX_VERSION}.tar.gz \
    && cd nginx-${NGINX_VERSION} \
    && ./configure --user=root --group=root --http-log-path=/var/log/nginx/access.log --with-debug --with-http_ssl_module --with-compat --add-dynamic-module=../ModSecurity-nginx \ 
	--sbin-path=/usr/local/nginx/sbin/nginx --error-log-path=/var/log/nginx/error.log --conf-path=/usr/local/nginx/nginx.conf --with-http_v2_module \
    && make \
	&& make modules \
	&& make install \
	&& cd / \
	&& rm nginx-${NGINX_VERSION}.tar.gz

# Clone OWASP ModSecurity ruleset and safe them into modsec-folder.
RUN git clone https://github.com/SpiderLabs/owasp-modsecurity-crs.git /usr/src/owasp-modsecurity-crs \
	&& mkdir -p /usr/local/nginx/owasp.d/rules/ \
	&& cp -R /usr/src/owasp-modsecurity-crs/rules/ /usr/local/nginx/owasp.d/ \
	&& cd / \
	&& mv /usr/local/nginx/modsec.d/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example /usr/local/nginx/owasp.d/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf \
	&& mv /usr/local/nginx/modsec.d/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example /usr/local/nginx/owasp.d/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf \
    && mv /usr/src/owasp-modsecurity-crs/crs-setup.conf.example /usr/local/nginx/owasp.d/crs-setup.conf

# System cleanup and basic authentication preparation.
RUN apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
	&& apt-get remove -y --purge apt-utils autoconf automake build-essential git pkgconf \
	&& apt-get autoremove -y \
	&& cd / \
	&& rm -rf nginx-${NGINX_VERSION} \
	&& rm -rf /usr/local/conf \
	&& rm -rf /usr/src/owasp-modsecurity-crs \

# Copy configuration files into image
# COPY /nginx.conf /usr/local/nginx/nginx.conf
# COPY /conf.d/ /usr/local/nginx/conf.d/
# COPY /modsec.d/ /usr/local/nginx/modsec.d/

# Ending steps
EXPOSE 80 443
STOPSIGNAL SIGQUIT
WORKDIR /usr/local/nginx/

# Use first to just start Nginx or second to restart Nginx after specific hours.
# CMD /usr/local/nginx/sbin/nginx -g 'daemon off;'
CMD /bin/sh -c 'while :; do sleep 6h & wait ${!}; /usr/local/nginx/sbin/nginx -s reload && echo NGINX config reload for Certbot - OK; done & /usr/local/nginx/sbin/nginx'