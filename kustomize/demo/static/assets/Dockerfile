FROM node:24-alpine@sha256:f1f2c6ee5140c8a7e94d379a40a9467395be641716126f65aea28aff35dbb196

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
