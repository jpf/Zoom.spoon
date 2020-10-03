local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Unofficial Zoom Spoon"
obj.version = "1.0"
obj.author = "Joel Franusic"
obj.license = "MIT"

obj.callbackFunction = nil

function unpack (t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], unpack(t, i + 1)
  end
end

-- via: https://github.com/kyleconroy/lua-state-machine/
local machine = dofile(hs.spoons.resourcePath("statemachine.lua"))

watcher = nil

audioStatus = 'off'
zoomState = machine.create({
  initial = 'closed',
  events = {
    { name = 'start',        from = 'closed',  to = 'running' },
    { name = 'startMeeting', from = 'running', to = 'meeting' },
    { name = 'startShare',   from = 'meeting', to = 'sharing' },
    { name = 'endShare',     from = 'sharing', to = 'meeting' },
    { name = 'endMeeting',   from = 'meeting', to = 'running' },
    { name = 'stop',         from = 'running', to = 'closed' },
  },
  callbacks = {
    onstatechange = function(self, event, from, to)
      changeName = "from-" .. from .. "-to-" .. to
      obj:_change(changeName)

      if changeName == "from-running-to-meeting" then
        audioStatus = obj:getAudioStatus()
        obj:_change(audioStatus)
      elseif changeName == "from-meeting-to-running" then
        audioStatus = 'off'
      end
    end,
  }
})

local endMeetingDebouncer = hs.timer.delayed.new(0.2, function()
  if not _check({"Meeting", "Invite"}) then
    zoomState:endMeeting()
  end
end)

appWatcher = hs.application.watcher.new(function (appName, eventType, appObject)
  if (eventType == hs.application.watcher.launched) then
    zoomState:start()

    watcher = appObject:newWatcher(function (element, event, watcher, userData)
      local eventName = tostring(event)
      local windowTitle = ""
      if element['title'] ~= nil then
        windowTitle = element:title()
      end

      if(eventName == "AXTitleChanged" and windowTitle == "Zoom Meeting") then
        zoomState:startMeeting()
      elseif(eventName == "AXWindowCreated" and windowTitle == "Zoom Meeting") then
        zoomState:endShare()
      elseif(eventName == "AXWindowCreated" and windowTitle == "Zoom") then
        zoomState:start()
      elseif(eventName == "AXWindowCreated" and windowTitle:sub(1, #"zoom share") == "zoom share") then
        zoomState:startShare()
      elseif(eventName == "AXUIElementDestroyed") then
        endMeetingDebouncer:start()
      end
    end, { name = "zoom.us" })
    watcher:start({hs.uielement.watcher.windowCreated, hs.uielement.watcher.titleChanged, hs.uielement.watcher.elementDestroyed})
  elseif (eventType == hs.application.watcher.terminated) then
    if (watcher ~= nil) then
      watcher:stop()
      if zoomState:is('meeting') then zoomState:endMeeting() end
      zoomState:stop()
      watcher = nil
    end
  end
end)

function obj:start()
  appWatcher:start()
end

function _check(tbl)
  local check = hs.application.get("zoom.us")
  if (check ~= nil) then
    return check:findMenuItem(tbl) ~= nil
  end
end

function obj:_click(tbl)
  click = hs.application.get("zoom.us")
  if (click ~= nil) then
    return click:selectMenuItem(tbl)
  end
end

function obj:_change(changeEvent)
  if (self.callbackFunction) then
    self.callbackFunction(changeEvent)
  end
end

function obj:getAudioStatus()
  if _check({"Meeting", "Unmute Audio"}) then
    return 'muted'
  elseif _check({"Meeting", "Mute Audio"}) then
    return 'unmuted'
  else
    return 'off'
  end
end

function obj:toggleMute()
  if audioStatus == 'muted' then
    self:unmute()
  end
  if audioStatus == 'unmuted' then
    self:mute()
  else
    return nil
  end
end

function obj:mute()
  if audioStatus == 'unmuted' and self:_click({"Meeting", "Mute Audio"}) then
    audioStatus = 'muted'
    self:_change("muted")
  end
end

function obj:unmute()
  if audioStatus == 'muted' and self:_click({"Meeting", "Unmute Audio"}) then
    audioStatus = 'unmuted'
    self:_change("unmuted")
  end
end

function obj:inMeeting()
  return zoomState:is('meeting') or zoomState:is('sharing')
end


function obj:setStatusCallback(func)
  self.callbackFunction = func
end

return obj
