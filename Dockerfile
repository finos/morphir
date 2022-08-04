FROM node:16.1-alpine3.11

ENV MORPHIR_USER = morphirUser
# Add Non Root User
RUN adduser -S -H $MORPHIR_USER

LABEL author="Piyush Gupta"

ENV  NODE_ENV=production

ENV PORT=3000

#Directory of Docker Container
WORKDIR /var/morphir_home

COPY ./tests-integration/reference-model ./

RUN npm install -g morphir-elm && morphir-elm make

EXPOSE $PORT

USER $MORPHIR_USER

ENTRYPOINT ["morphir-elm","develop"]
#docker run --name ContainerName -p 3000:3000 ImageID