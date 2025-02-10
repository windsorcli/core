const express = require('express');
const livereload = require('livereload');
const connectLivereload = require('connect-livereload');
const path = require('path');

// Create a livereload server
const liveReloadServer = livereload.createServer();
liveReloadServer.watch('/usr/src/app');

// Create an express app
const app = express();

// Use connect-livereload middleware
app.use(connectLivereload());

// Serve static files from the '/usr/src/app' directory
app.use(express.static('/usr/src/app'));

// Start the server
const PORT = 8080;
app.listen(PORT, () => {
  console.log(`Server is running on http://localhost:${PORT}`);
});
