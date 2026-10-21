FROM node:24-alpine@sha256:6a1c190e17215d844926b0677f4bf87273ff7d5e54db06d3b5b5863ab0b09a3d

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
