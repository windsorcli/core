local context = std.extVar("context");
local hlp = std.extVar("helpers");

local gitUsername = hlp.getString(context, "git.livereload.username", null);
local gitPassword = hlp.getString(context, "git.livereload.password", null);
local webhook_token = if hlp.has(context, "git.livereload") then "abcdef123456" else null;

local result = {};

result +
  (if gitUsername != null then { git_username: gitUsername } else {}) +
  (if gitPassword != null then { git_password: gitPassword } else {}) +
  (if webhook_token != null then { webhook_token: webhook_token } else {})
