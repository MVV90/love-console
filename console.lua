--[[
The ISC License

Copyright (c) Varun Ramesh

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT,
OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE,
DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS
ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
]]--

local console = {}

-- Utilty functions for manipulating tables.
local function map(tbl, f)
    local t = {}
    for k,v in pairs(tbl) do t[k] = f(v) end
    return t
end
local function filter(tbl, f)
  local t, i = {}, 1
  for _, v in ipairs(tbl) do
    if f(v) then t[i], i = v, i + 1 end
  end
  return t
end
local function push(tbl, ...)
  for _, v in ipairs({...}) do table.insert(tbl, v) end
end

console.HORIZONTAL_MARGIN = 10 -- Horizontal margin between the text and window.
console.VERTICAL_MARGIN = 10 -- Vertical margins between components.
console.PROMPT = "> " -- The prompt symbol.

console.MAX_LINES = 200 -- How many lines to store in the buffer.
console.HISTORY_SIZE = 100 -- How much of history to store.

-- Color configurations.
console.BACKGROUND_COLOR = {0, 0, 0, 0.4}
console.TEXT_COLOR = {1, 1, 1, 1}
console.ERROR_COLOR = {1, 0, 0, 1}

console.FONT_SIZE = 12
console.FONT = love.graphics.newFont(console.FONT_SIZE)

-- The scope in which lines in the console are executed.
console.ENV = setmetatable({}, {__index = _G})

-- The default help text shown.
console.HELP_TEXT = [[==== Welcome to the In-Game Console ====
- Type any expression or statement to evaluate it.
- Type a built-in command to run it (type `commands` to list all commands).]]

-- Builtin commands.
console.COMMANDS = {
  clear = function() console.clear() end,
  quit = function() love.event.quit(0) end,
  exit = function() love.event.quit(0) end,
  help = function() print(console.HELP_TEXT) end,
  commands = function()
    print ("=== Available Commands ===")
    for k, _ in pairs(console.COMMANDS) do
      if console.COMMAND_HELP[k] then
        print(k .. " - " .. console.COMMAND_HELP[k])
      else
        print(k)
      end
    end
  end
}

console.COMMAND_HELP = {
  clear = "Clear the sceen.",
  quit = "Quit the game.",
  exit = "Quit the game.",
  help = "Print help text.",
  commands = "List all commands."
}

function console.inspect(val)
  if type(val) == "table"  then
    -- If this table has a tostring function, just use that.
    local mt = getmetatable(val)
    if mt and mt.__tostring then return tostring(val) end

    local result = "{ "

    -- First print out array-like keys, keeping track of which keys we've seen.
    local seen = {}
    for k, v in ipairs(val) do
      result = result .. tostring(v) .. ", "
      seen[k] = true
    end

    -- Now print out the reset of the keys.
    for k, v in pairs(val) do
      if seen[k] ~= true then
        result = result .. tostring(k) .. " = " .. tostring(v) .. ", "
      end
    end
    result = result .. "}"
    return result
  else
    return tostring(val)
  end
end

-- Overrideable function that is used for formatting return values.
console.INSPECT_FUNCTION = function(...)
  local args = {...}
  if #args == 0 then
    return "nil"
  else
    return table.concat(map(args, console.inspect), "\t")
  end
end

-- Store global state for whether or not the console is enabled / disabled.
local enabled = false
function console.isEnabled() return enabled end

-- Store the printed lines in a buffer.
local lines = {}
function console.clear() lines = {} end

-- Store previously executed commands in a history buffer.
local history = {}
function console.addHistory(command)
  table.insert(history, 1, command)
end

-- Print a colored text to the console. Colored text is simply represented
-- as a table of values that alternate between an {r, g, b, a} object and a
-- string value.
function console.colorprint(coloredtext) table.insert(lines, coloredtext) end

-- Wrap the print function and redirect it to store into the line buffer.
local normal_print = print
_G.print = function(...)
  normal_print(...) -- Call original print function.
  local args = {...}
  local line = table.concat(map({...}, tostring), "\t")
  push(lines, line)

  while #lines > console.MAX_LINES do
    table.remove(lines, 1)
  end
end

-- Helper object that encapuslates operations on the current command.
local command = {
  clear = function(self)
    -- Clear the current command.
    self.text, self.cursor, self.history_index = "", 0, 0
  end,
  insert = function(self, input)
    -- Inert text at the cursor.
    self.text = self.text:sub(0, self.cursor) ..
      input .. self.text:sub(self.cursor + 1)
    self.cursor = self.cursor + 1
  end,
  delete_backward = function(self)
    -- Delete the character before the cursor.
    if self.cursor > 0 then
      self.text = self.text:sub(0, self.cursor - 1) ..
        self.text:sub(self.cursor + 1)
      self.cursor = self.cursor - 1
    end
  end,
  delete_forward = function(self)
    -- Delete the character after the cursor.
    self.text = self.text:sub(0, self.cursor) .. self.text:sub(self.cursor + 2)
  end,
  forward_character = function(self)
    self.cursor = math.min(self.cursor + 1, self.text:len())
  end,
  backward_character = function(self)
    self.cursor = math.max(self.cursor - 1, 0)
  end,
  beginning_of_line = function(self) self.cursor = 0 end,
  end_of_line = function(self) self.cursor = self.text:len() end,
  forward_word = function(self)
    local word = self.text:match('%W*%w*', self.cursor + 1)
    self.cursor = math.min(self.cursor + word:len())
  end,
  backward_word = function(self)
    local word = self.text:reverse():match('%W*%w*', self.text:len() - self.cursor + 1)
    self.cursor = math.max(self.cursor - word:len(), 0)
  end,
  previous = function(self)
    -- If there is no more history, don't do anything.
    if self.history_index + 1 > #history then return end

    -- If this is the first time, then save the command in case the user
    -- navigates back to the present command.
    if self.history_index == 0 then self.saved_command = self.text end

    self.history_index = math.min(self.history_index + 1, #history)
    self.text = history[self.history_index]
    self.cursor = self.text:len()
  end,
  next = function(self)
    -- If there is no more history, don't do anything.
    if self.history_index - 1 < 0 then return end
    self.history_index = math.max(self.history_index - 1, 0)

    if self.history_index == 0 then self.text = self.saved_command
    else self.text = history[self.history_index] end
    self.cursor = self.text:len()
  end
}
command:clear()

function console.draw()
  -- Only draw the console if enabled.
  if not enabled then return end

  -- Fill the background color.
  love.graphics.setColor(unpack(console.BACKGROUND_COLOR))
  love.graphics.rectangle('fill', 0, 0, love.graphics.getWidth(),
    love.graphics.getHeight())

  love.graphics.setColor(255, 255, 255, 255)
  love.graphics.setFont(console.FONT)

  local line_start = love.graphics.getHeight() - console.VERTICAL_MARGIN*3 - console.FONT:getHeight()
  local wraplimit = love.graphics.getWidth() - console.HORIZONTAL_MARGIN*2

  for i = #lines, 1, -1 do
    local textonly = lines[i]
    if type(lines[i]) == "table" then
      textonly = table.concat(filter(lines[i], function(val)
        return type(val) == "string"
      end), "")
    end
    width, wrapped = console.FONT:getWrap(textonly, wraplimit)

    love.graphics.printf(
      lines[i], console.HORIZONTAL_MARGIN,
      line_start - #wrapped * console.FONT:getHeight(),
      wraplimit, "left")
    line_start = line_start - #wrapped * console.FONT:getHeight()
  end

  love.graphics.setLineWidth(1)

  love.graphics.line(0,
    love.graphics.getHeight() - console.VERTICAL_MARGIN
      - console.FONT:getHeight() - console.VERTICAL_MARGIN,
    love.graphics.getWidth(),
    love.graphics.getHeight() - console.VERTICAL_MARGIN
      - console.FONT:getHeight() - console.VERTICAL_MARGIN)

  love.graphics.printf(
    console.PROMPT .. command.text,
    console.HORIZONTAL_MARGIN,
    love.graphics.getHeight() - console.VERTICAL_MARGIN - console.FONT:getHeight(),
    love.graphics.getWidth() - console.HORIZONTAL_MARGIN*2, "left")

  if love.timer.getTime() % 1 > 0.5 then
    local cursorx = console.HORIZONTAL_MARGIN +
      console.FONT:getWidth(console.PROMPT .. command.text:sub(0, command.cursor))
    love.graphics.line(
      cursorx,
      love.graphics.getHeight() - console.VERTICAL_MARGIN - console.FONT:getHeight(),
      cursorx,
      love.graphics.getHeight() - console.VERTICAL_MARGIN)
  end
end

function console.textinput(input)
  -- Use the "~" key to enable / disable the console.
  if input == "~" or input == "`" then
    enabled = not enabled
    return
  end

  -- If disabled, ignore the input, otherwise insert at the cursor.
  if not enabled then return end
  command:insert(input)
end

function console.execute(command)
  -- If this is a builtin command, execute it and return immediately.
  if console.COMMANDS[command] then
    console.COMMANDS[command]()
    return
  end

  -- Reprint the command + the prompt string.
  print(console.PROMPT .. command)

  local chunk, error = load("return " .. command)
  if not chunk then
    chunk, error = load(command)
  end

  if chunk then
    setfenv(chunk, console.ENV)
    local values = { pcall(chunk) }
    if values[1] then
      table.remove(values, 1)
      print(console.INSPECT_FUNCTION(unpack(values)))

      -- Bind '_' to the first returned value, and bind 'last' to a list
      -- of returned values.
      console.ENV._ = values[1]
      console.ENV.last = values
    else
      console.colorprint({console.ERROR_COLOR, values[2]})
    end
  else
    console.colorprint({console.ERROR_COLOR, error})
  end
end

function console.keypressed(key, scancode, isrepeat)
  -- Ignore if the console isn't enabled.
  if not enabled then return end

  local ctrl = love.keyboard.isDown("lctrl", "lgui")
  local shift = love.keyboard.isDown("lshift")
  local alt = love.keyboard.isDown("lalt")

  if key == 'backspace' then command:delete_backward()
  elseif key == 'delete' then command:delete_forward()

  elseif key == "up" then command:previous()
  elseif key == "down" then command:next()

  elseif alt and key == "left" then command:backward_word()
  elseif alt and key == "right" then command:forward_word()

  elseif ctrl and key == "left" then command:beginning_of_line()
  elseif ctrl and key == "right" then command:end_of_line()

  elseif key == "left" then command:backward_character()
  elseif key == "right" then command:forward_character()

  elseif key == "c" and ctrl then command:clear()

  elseif key == "=" and shift and ctrl then
      console.FONT_SIZE = console.FONT_SIZE + 1
      console.FONT = love.graphics.newFont(console.FONT_SIZE)
  elseif key == "-" and ctrl then
      console.FONT_SIZE = math.max(console.FONT_SIZE - 1, 1)
      console.FONT = love.graphics.newFont(console.FONT_SIZE)

  elseif key == "return" then
    console.addHistory(command.text)
    console.execute(command.text)
    command:clear()
  end
end

return console
