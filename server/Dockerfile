FROM ubuntu:latest
#FROM node:16

ENV $APP_USER = appUser
# Add Non Root User
RUN adduser -S -H $APP_USER

# Create app directory
WORKDIR /usr/src/app

# Install app dependencies
# A wildcard is used to ensure both package.json AND package-lock.json are copied
# where available (npm@5+)
COPY package*.json ./


RUN \
    curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash && \
    apt-get update && \
    apt install -y curl && \
    curl -sL https://deb.nodesource.com/setup_12.x | bash - && \
    apt install -y nodejs && \
    npm install -y -g npm@8.1.0 && \
    apt-get install -y clang && \
    apt-get install -y git-lfs && \
    npm install -y typescript --save-devnpm install typescript --save-dev && \
    npm install -g morphir-elm && \
    npm install -g morphir-bsq-transpiler && \
    npm install -y 

# If you are building your code for production

# RUN npm ci --only=production

# Bundle app source
COPY . .

EXPOSE 8080

USER $APP_USER

CMD [ "node", "server.js" ]
