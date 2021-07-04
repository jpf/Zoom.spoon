--[[

 Known issues:
 * Mute is not detected properly during a Zoom Webinar

]]

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "Unofficial Zoom Spoon"
obj.version = "1.0"
obj.author = "Joel Franusic"
obj.license = "MIT"
obj.homepage = "https://github.com/jpf/Zoom.spoon"

obj.callbackFunction = nil
obj.pollingInterval = nil

function unpack (t, i)
  i = i or 1
  if t[i] ~= nil then
    return t[i], unpack(t, i + 1)
  end
end

-- via: https://github.com/kyleconroy/lua-state-machine/
local machine = dofile(hs.spoons.resourcePath("statemachine.lua"))

watcher = nil
timer = nil

audioStatus = 'off'
videoStatus = 'off'

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

      if changeName == "from-running-to-meeting" then
        audioStatus = obj:getAudioStatus()
        videoStatus = obj:getVideoStatus()
        obj:_change(audioStatus)
        obj:_change(videoStatus)
      elseif changeName == "from-meeting-to-running" then
        audioStatus = 'off'
        videoStatus = 'off'
      end
      obj:_change(changeName)
    end,
  }
})

local endMeetingDebouncer = hs.timer.delayed.new(0.2, function()
  -- Only end the meeting if the "Meeting" menu is no longer present
  if not _check({"Meeting", "Invite"}) then
    zoomState:endMeeting()
  end
end)

local stopTimer = function()
  if (timer ~= nil) then
    timer:stop()
    timer = nil
  end
end

local timerCallback = function()
  -- keep current state
  local currentAudioStatus = audioStatus
  local currentVideoStatus = videoStatus
  -- and refresh state from Zoom
  audioStatus = obj:getAudioStatus()
  videoStatus = obj:getVideoStatus()

  -- if either audio or video state has changed, trigger callback
  if currentAudioStatus ~= audioStatus then obj:_change(audioStatus) end
  if currentVideoStatus ~= videoStatus then obj:_change(videoStatus) end
end

appWatcher = hs.application.watcher.new(function (appName, eventType, appObject)
  if (appName == "zoom.us" and eventType == hs.application.watcher.launched) then
    zoomState:start()

    watcher = appObject:newWatcher(function (element, event, watcher, userData)
      local eventName = tostring(event)
      local windowTitle = ""
      if element['title'] ~= nil then
        windowTitle = element:title()
      end

      if(eventName == "AXTitleChanged" and windowTitle == "Zoom Meeting") then
        zoomState:startMeeting()
      elseif(eventName == "AXTitleChanged" and windowTitle == "Zoom Webinar") then
        zoomState:startMeeting()
      elseif(eventName == "AXWindowCreated" and windowTitle == "Zoom Meeting") then
        zoomState:endShare()
      elseif(eventName == "AXWindowCreated" and windowTitle == "Zoom Webinar") then
        zoomState:startMeeting()
      elseif(eventName == "AXWindowCreated" and windowTitle == "Zoom") then
        zoomState:start()
      elseif(eventName == "AXWindowCreated" and windowTitle:sub(1, #"zoom share") == "zoom share") then
        zoomState:startShare()
      elseif(eventName == "AXUIElementDestroyed") then
        endMeetingDebouncer:start()
      end
    end, { name = "zoom.us" })
    watcher:start({hs.uielement.watcher.windowCreated, hs.uielement.watcher.titleChanged, hs.uielement.watcher.elementDestroyed})

    if obj.pollingInterval ~= nil then
      stopTimer()
      timer = hs.timer.new(obj.pollingInterval, timerCallback, true)
      timer:start()
    end

  elseif (eventType == hs.application.watcher.terminated) then
    if (watcher ~= nil) then
      watcher:stop()
      if zoomState:is('meeting') then endMeetingDebouncer:start() end
      zoomState:stop()
      watcher = nil
    end
    stopTimer()
  end
end)

function obj:start()
  appWatcher:start()
end

function obj:stop()
  appWatcher:stop()
  stopTimer()
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

function obj:getVideoStatus()
  if _check({"Meeting", "Start Video"}) then
    return 'videoStopped'
  elseif _check({"Meeting", "Stop Video"}) then
    return 'videoStarted'
  else
    return 'off'
  end
end

--- Zoom:toggleMute()
--- Method
--- Toggles between the 'muted' and 'unmuted states'
function obj:toggleMute()
  if audioStatus ~= obj:getAudioStatus() then
    audioStatus = obj:getAudioStatus()
    self:_change(audioStatus)
  end
  if audioStatus == 'muted' then
    self:unmute()
  end
  if audioStatus == 'unmuted' then
    self:mute()
  else
    return nil
  end
end

--- Zoom:toggleVideo()
--- Method
--- Toggles between the 'videoStarted' and 'videoStopped states'
function obj:toggleVideo()
  if videoStatus ~= obj:getVideoStatus() then
    videoStatus = obj:getVideoStatus()
    self:_change(videoStatus)
  end
  if videoStatus == 'videoStopped' then
    self:startVideo()
  end
  if videoStatus == 'videoStarted' then
    self:stopVideo()
  else
    return nil
  end
end

--- Zoom:mute()
--- Method
--- Mutes the audio in Zoom, if Zoom is currently unmuted
function obj:mute()
  if obj:getAudioStatus() == 'unmuted' and self:_click({"Meeting", "Mute Audio"}) then
    audioStatus = 'muted'
    self:_change("muted")
  end
end

--- Zoom:unmute()
--- Method
--- Unmutes the audio in Zoom, if Zoom is currently muted
function obj:unmute()
  if obj:getAudioStatus() == 'muted' and self:_click({"Meeting", "Unmute Audio"}) then
    audioStatus = 'unmuted'
    self:_change("unmuted")
  end
end

--- Zoom:stopVideo()
--- Method
--- Stops the video in Zoom, if Zoom is currently streaming video
function obj:stopVideo()
  if obj:getVideoStatus() == 'videoStarted' and self:_click({"Meeting", "Stop Video"}) then
    videoStatus = 'videoStopped'
    self:_change("videoStopped")
  end
end

--- Zoom:startVideo()
--- Method
--- Starts the video in Zoom, if Zoom is currently not streaming video
function obj:startVideo()
  if obj:getVideoStatus() == 'videoStopped' and self:_click({"Meeting", "Start Video"}) then
    videoStatus = 'videoStarted'
    self:_change("videoStarted")
  end
end

function obj:inMeeting()
  return zoomState:is('meeting') or zoomState:is('sharing')
end


--- Zoom:setStatusCallback(func)
--- Method
--- Registers a function to be called whenever Zoom's state changes
---
--- Parameters:
--- * func - A function in the form "function(event)" where "event" is a string describing the state change event
function obj:setStatusCallback(func)
  self.callbackFunction = func
end

--- Zoom:pollStatus(interval)
--- Method
--- Enables a polling timer checking for mute/video status
---
--- Parameters:
--- * interval - Polling interval in seconds
function obj:pollStatus(interval)
  self.pollingInterval = interval
end

return obj
