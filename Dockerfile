FROM node:16.1-alpine3.11

LABEL author="Piyush Gupta"

ENV  NODE_ENV=production
ENV PORT=3000
ENV MORPHIR_USER = morphir

# Add Non Root User
RUN adduser --system --uid=7357 --no-create-home ${MORPHIR_USER}

#Directory of Docker Container
WORKDIR /var/morphir_home

COPY ./tests-integration/reference-model ./

RUN npm install -g morphir-elm && morphir-elm make

EXPOSE $PORT

USER $MORPHIR_USER

ENTRYPOINT ["morphir-elm","develop"]
#docker run --name ContainerName -p 3000:3000 ImageID