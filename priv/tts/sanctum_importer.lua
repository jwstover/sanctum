-- Sanctum deck importer tile for Tabletop Simulator.
-- Written from scratch for Sanctum. Contains no Cerebro or Hitch Lua and
-- embeds no assets. Needs "Marvel Champions: Hitch's Table" (Workshop 2514286571).

-- Prod host. For local dev use "http://localhost:4150".
BASE_URL = "https://sanctummc.com"
BAG_GUID = "7fd666"
MOD_NAME = "Marvel Champions: Hitch's Table"

local deckInput = ""
local busy = false

local function say(msg, color)
  broadcastToAll("[Sanctum] " .. msg, color or {1, 0.4, 0.4})
end

function onLoad()
  self.clearInputs()
  self.clearButtons()
  self.createInput{
    input_function = "onDeckIdInput", function_owner = self,
    label = "Sanctum deck id or URL", value = "", tooltip = "Paste a Sanctum deck id or URL",
    position = {0, 0.3, 0.6}, rotation = {0, 0, 0}, width = 2400, height = 300,
    font_size = 200, alignment = 3, validation = 1,
  }
  self.createButton{
    click_function = "onImportClick", function_owner = self,
    label = "Import", tooltip = "Import deck from Sanctum",
    position = {0, 0.3, -0.4}, rotation = {0, 0, 0}, width = 1200, height = 400,
    font_size = 240,
  }
end

function onDeckIdInput(obj, color, value, selected)
  deckInput = value
end

-- Spawns pieces one at a time; each spawn's callback starts the next.
local function spawnPieces(bag, pieces, title)
  local entries = bag.getData().ContainedObjects
  if entries == nil then
    busy = false
    return say("Could not read the importer bag contents.")
  end
  local function spawnNext(i)
    if i > #pieces then
      busy = false
      return say("Imported " .. title, {0.3, 1, 0.3})
    end
    local name, found = pieces[i], nil
    for _, entry in ipairs(entries) do
      if entry.Nickname == name then found = entry break end
    end
    if not found then
      busy = false
      return say(name .. " isn't in this version of " .. MOD_NAME .. "'s importer bag")
    end
    spawnObjectData{
      data = found,
      position = self.getPosition() + Vector(0, 2, -4),
      callback_function = function() spawnNext(i + 1) end,
    }
  end
  spawnNext(1)
end

local function onResponse(req, id)
  local function fail(msg) busy = false say(msg) end
  if req.is_error then
    return fail("Network error: " .. tostring(req.error) .. ". Check your connection.")
  end
  if req.response_code == 404 then
    return fail("Deck not found — check the id, and that the deck is published on Sanctum")
  elseif req.response_code == 429 then
    return fail("Too many imports — wait a minute")
  elseif req.response_code ~= 200 then
    return fail("Unexpected response " .. tostring(req.response_code) .. " from " .. BASE_URL)
  end
  local ok, data = pcall(JSON.decode, req.text)
  if not ok or type(data) ~= "table" then
    return fail("Sanctum sent an unreadable response")
  end
  if data.version ~= 1 then
    return fail("This tile is out of date — get the latest from Sanctum")
  end
  local identity = type(data.hero) == "table" and data.hero.identity
  if not identity then return fail("Response is missing hero.identity") end
  if type(data.unmapped) == "table" and #data.unmapped > 0 then
    local names = {}
    for _, u in ipairs(data.unmapped) do
      names[#names + 1] = type(u) == "table" and (u.name or u.code or "?") or tostring(u)
    end
    say("Not importable: " .. table.concat(names, ", "), {1, 1, 0.3})
  end
  local bag = getObjectFromGUID(BAG_GUID)
  if bag == nil then return fail("Importer bag disappeared") end
  local title = type(data.deck) == "table" and data.deck.title or identity
  spawnPieces(bag, {identity}, title)
end

function onImportClick()
  if busy then return say("Import already in progress") end
  local id = string.match(deckInput, "%x+%-%x+%-%x+%-%x+%-%x+")
  if not id then return say("Paste a Sanctum deck id or deck URL") end
  local bag = getObjectFromGUID(BAG_GUID)
  if bag == nil or bag.getName() ~= "ImporterCards" then
    return say("This tile must be used inside " .. MOD_NAME .. " (Steam Workshop). Load that table and try again.")
  end
  busy = true
  WebRequest.custom(BASE_URL .. "/api/decks/" .. id .. "/tts", "GET", true, nil,
    {Accept = "application/json"}, function(req) onResponse(req, id) end)
end
