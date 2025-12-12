FROM node:24-alpine@sha256:7e0bd0460b26eb3854ea5b99b887a6a14d665d14cae694b78ae2936d14b2befb

# Set the working directory for building and running the server
WORKDIR /usr/src/server

# Copy package.json and package-lock.json
COPY package.json package-lock.json ./

# Install the dependencies
RUN npm install

# Copy the rest of the application code
COPY server.js ./

# Expose the port the app runs on
EXPOSE 8080

# Command to run the server.js application
CMD ["node", "server.js"]
