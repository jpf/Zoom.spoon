--[[
--------------------------------------------------------
-- Instantiate Spoon
--------------------------------------------------------
]]
local obj = {}
obj.__index = obj

--[[
--------------------------------------------------------
-- Spoon Metadata
--------------------------------------------------------
]]
obj.name = 'Expanded Zoom Spoon'
obj.version = '2.0'
obj.author = 'Luke Brooks'
obj.license = 'MIT'
obj.homepage = 'https://github.com/luke-brooks/Zoom.spoon'
obj.adaptedFrom = {
    author = 'Joel Franusic',
    homepage = 'https://github.com/jpf/Zoom.spoon'
}

--[[
--------------------------------------------------------
-- Zoom State Machine
--------------------------------------------------------
]]

APP_STATES = {
    CLOSED = 'closed',
    RUNNING = 'running',
    MEETING = 'meeting',
    SHARING = 'sharing'
}
function unpack(t, i)
    i = i or 1
    if t[i] ~= nil then
        return t[i], unpack(t, i + 1)
    end
end
-- via: https://github.com/kyleconroy/lua-state-machine/
local machine = dofile(hs.spoons.resourcePath('statemachine.lua'))
Zoom_State = machine.create({
    initial = 'closed',
    events = {{
        name = 'start',
        from = APP_STATES.CLOSED,
        to = APP_STATES.RUNNING
    }, {
        name = 'startMeeting',
        from = APP_STATES.RUNNING,
        to = APP_STATES.MEETING
    }, {
        name = 'startShare',
        from = APP_STATES.MEETING,
        to = APP_STATES.SHARING
    }, {
        name = 'endShare',
        from = APP_STATES.SHARING,
        to = APP_STATES.MEETING
    }, {
        name = 'endMeeting',
        from = APP_STATES.MEETING,
        to = APP_STATES.RUNNING
    }, {
        name = 'stop',
        from = APP_STATES.RUNNING,
        to = APP_STATES.CLOSED
    }},
    callbacks = {
        onstatechange = function(self, event, from, to)
            changeName = 'from-' .. from .. '-to-' .. to
            -- hs.printf('internal state machine transition %s', changeName)
            if (obj.transitionCallbackFunction ~= nil) then
                obj.transitionCallbackFunction(changeName)
            end
        end
    }
})

--[[
--------------------------------------------------------
-- Object Properties & Constants
--------------------------------------------------------
]]
ZOOM_APP_NAME = 'zoom.us'
ZOOM_APP_INSTANCE = nil

obj.audio = {
    icon = {
        menuBarItem = hs.menubar.new(nil),
        mutedTitle = '🔴',
        unmutedTitle = '🟢'
    }
}
obj.video = {}
obj.share = {}
obj.chat = {}
obj.participants = {}
obj.stateCallbackFunction = nil
obj.transitionCallbackFunction = nil

local INPUT_STATES = {
    OFF = 'off',
    MUTED = 'muted',
    UNMUTED = 'unmuted'
}

local WINDOW_TITLES = {
    MEETING = 'Zoom Meeting',
    WEBINAR = 'Zoom Webinar',
    MAIN = 'Zoom',
    SHARING = 'zoom share',
    CHAT = 'Chat',
    PARTICIPANTS = 'Participants'
    -- ??? BREAKOUT = 'Zoom Room'
}

local MENU_ITEMS = {
    -- Meeting Menu Items
    MEETING = {
        TOP = 'Meeting',
        INVITE = 'Invite',
        UNMUTE_AUDIO = 'Unmute Audio',
        MUTE_AUDIO = 'Mute Audio',
        START_VIDEO = 'Start Video',
        STOP_VIDEO = 'Stop Video',
        STOP_SHARE = 'Stop Share'
    },
    -- View Menu Items
    VIEW = {
        TOP = 'View',
        SHOW_CHAT = 'Show Chat',
        CLOSE_CHAT = 'Close Chat',
        SHOW_PARTICIPANTS = 'Show Manage Participants',
        CLOSE_PARTICIPANTS = 'Close Manage Participants',
        SHOW_SHARE_CONTROLS = 'Show Floating Meeting Controls'
    }
}

--[[
--------------------------------------------------------
-- App & Zoom Event Watchers
--------------------------------------------------------
]]
zoom_state_watcher = nil
-- Watches all application events
--  & instantiates the zoom_state_watcher if Zoom was not open during hs config load
app_watcher = hs.application.watcher.new(function(appName, eventType, appObject)
    -- hs.printf('examining internal events %s', eventType)
    if (appName == ZOOM_APP_NAME) then
        _start_zoom_state_watcher(appObject)
        -- hs.printf('zoom state machine current %s', Zoom_State.current)
    end
end)

function _start_zoom_state_watcher(tempZoomObject)
    -- hs.printf('zoom_state_watcher status %s', zoom_state_watcher)
    if (zoom_state_watcher == nil and tempZoomObject ~= nil) then
        -- hs.printf('instantiating zoom_state_watcher')
        ZOOM_APP_INSTANCE = tempZoomObject

        zoom_state_watcher = ZOOM_APP_INSTANCE:newWatcher(function(element, event, zoom_state_watcher, userData)
            -- hs.printf('zoom state watcher events %s', event)
            -- hs.printf('zoom state watcher element %s', element)
            _determineZoomState()
        end, {
            name = ZOOM_APP_NAME
        })
        -- these events get frickin hammered on screen share, breakout rooms, & just normal usage
        -- hs.uielement.watcher.windowMoved,
        -- hs.uielement.watcher.windowResized, 

        -- a more aggressive state watcher will help keep the state & mute statuses accurate
        -- but more aggressive seems to be harming performance, need to refine
        zoom_state_watcher:start({hs.uielement.watcher.applicationActivated,
                                  hs.uielement.watcher.applicationDeactivated, hs.uielement.watcher.applicationHidden,
                                  hs.uielement.watcher.applicationShown, hs.uielement.watcher.mainWindowChanged,
                                  hs.uielement.watcher.focusedWindowChanged, hs.uielement.watcher.focusedElementChanged,
                                  hs.uielement.watcher.windowMinimized, hs.uielement.watcher.windowUnminimized,
                                  hs.uielement.watcher.windowCreated, hs.uielement.watcher.titleChanged,
                                  hs.uielement.watcher.elementDestroyed})
    end
end

function _stop_zoom_state_watcher()
    if (zoom_state_watcher ~= nil) then
        zoom_state_watcher:stop()
        Zoom_State:stop()
        zoom_state_watcher = nil
    end
end

--[[
--------------------------------------------------------
-- Trying to deprecate
--------------------------------------------------------
]]
-- alternative to the func below: hs.timer.delayed.new(0.2, function() end)
-- Pauses script execution
local clock = os.clock
function _pause(n) -- 'n' in seconds, can be decimal for partial seconds
    local t0 = clock()
    while clock() - t0 <= n do
    end
end

--[[
--------------------------------------------------------
-- Internal Functions
--------------------------------------------------------
]]
-- Returns the Zoom hs.application object
function _getZoomInstance()
    if (ZOOM_APP_INSTANCE ~= nil) then
        return ZOOM_APP_INSTANCE
    else
        -- nesting like this for processing efficiency by avoiding unnecessary hs.application.get()
        local app = hs.application.get(ZOOM_APP_NAME)
        if (app ~= nil) then
            ZOOM_APP_INSTANCE = app
            return ZOOM_APP_INSTANCE
        else
            return nil
        end
    end
end

function _buildIcon(targetInstance)
    local menuBarInstance = targetInstance or hs.menubar.new(nil)

    menuBarInstance:setClickCallback(function()
        -- hs.printf('menu click')
        obj.audio:toggleMute()
    end)

    return {
        menuBarItem = menuBarInstance,
        mutedTitle = '🔴',
        unmutedTitle = '🟢'
    }
end

-- Adjusts state to a proper value
--  mostly needed when hs config load happens while Zoom is already running
function _handleImproperState()
    if (Zoom_State.current == APP_STATES.CLOSED) then
        Zoom_State:start()
    end
    if (Zoom_State.current == APP_STATES.MEETING) then
        Zoom_State:endMeeting()
    end
end

-- Determines Zoom state by examining open windows & their titles
-- Returns highest priority hs.window object for current Zoom state
function _determineZoomState(triggerChange)
    local app = _getZoomInstance()
    if (app ~= nil and Zoom_State ~= nil) then
        -- https://stackoverflow.com/a/66003880/8677309
        -- using this default nonsense until i can streamline the _change function
        local defaultTrigger = true
        triggerChange = triggerChange or (triggerChange == nil and defaultTrigger)

        local priorityWindow = nil

        local meetingWindow = app:findWindow(WINDOW_TITLES.MEETING)
        local sharingWindow = app:findWindow(WINDOW_TITLES.SHARING)
        local webinarWindow = app:findWindow(WINDOW_TITLES.WEBINAR)
        local mainWindow = app:findWindow(WINDOW_TITLES.MAIN)

        if (meetingWindow ~= nil) then
            -- hs.printf('set state to meeting')
            _handleImproperState()
            Zoom_State:startMeeting() -- this will not move from 'closed' to 'meeting' needs to go to 'running' first
            priorityWindow = meetingWindow
        elseif (sharingWindow ~= nil) then
            -- hs.printf('set state to sharing')
            _handleImproperState()
            Zoom_State:startShare()
            priorityWindow = sharingWindow
        elseif (webinarWindow ~= nil) then
            -- hs.printf('set state to webinar')
            _handleImproperState()
            Zoom_State:startMeeting()
            priorityWindow = webinarWindow
        elseif (mainWindow ~= nil) then
            -- hs.printf('set state to running')
            _handleImproperState()
            Zoom_State:start()
            priorityWindow = app:findWindow(WINDOW_TITLES.MAIN)
        end

        if (priorityWindow ~= nil) then
            -- hs.printf('checking audio/video status')
            obj.audio:status()
            obj.video:status()
            if (triggerChange) then _change() end -- this _change is slowing down my Zoom:focus() func
        else
            Zoom_State:stop()
        end
        return priorityWindow
    end
    return nil
end

-- Checks for the presence of a given menu item
function _check(tbl)
    local app = _getZoomInstance()
    if (app ~= nil) then
        -- this seems to be a bottleneck, likely due to the menus taking forever to sift through
        -- the chrome itemMenu took like 30 seconds to compile lol
        return app:findMenuItem(tbl) ~= nil
    end
end

-- Performs a "click" action on a given menu item
function _click(tbl)
    local app = _getZoomInstance()
    if (app ~= nil) then
        -- hs.printf('clicking menu item')
        return app:selectMenuItem(tbl)
    end
end

-- Triggers the user-defined callback function
function _change()
    if (obj.stateCallbackFunction ~= nil) then
        -- hs.printf('triggering callback')
        -- this pause is going to be very difficult to remove...
        _pause(0.5) -- it would be nice to not have to delay. this also slows down non-audio status updates
        obj.stateCallbackFunction(Zoom_State.current, obj.audio:status(), obj.video:status())
    end
end

-- Process window title string
function _processWindowTitle(title, target)
    return title:sub(1, #target)
end

function _updateMenuBarIcon(menuBarIcon, iconTitle)
    if (menuBarIcon ~= nil and iconTitle ~= nil) then
        menuBarIcon:returnToMenuBar()
        menuBarIcon:setTitle(iconTitle)
    elseif (menuBarIcon ~= nil and iconTitle == nil) then
        menuBarIcon:removeFromMenuBar()
    end
end

-- Examines the current muted status of either audio or video 
function _determineInputStatus(muteItem, unmuteItem, menuBarIcon, mutedTitle, unmutedTitle)
    local result = INPUT_STATES.OFF

    if _check({MENU_ITEMS.MEETING.TOP, muteItem}) then
        result = INPUT_STATES.UNMUTED
        _updateMenuBarIcon(menuBarIcon, unmutedTitle)
    elseif _check({MENU_ITEMS.MEETING.TOP, unmuteItem}) then
        result = INPUT_STATES.MUTED
        _updateMenuBarIcon(menuBarIcon, mutedTitle)
    else
        _updateMenuBarIcon(menuBarIcon)
    end

    return result
end

-- Performs a menu click to change a muted status 
--  & triggers user-defined callback if click was successful
function _changeInputSetting(menuItem, menuBarIcon, iconTitle)
    if _click({MENU_ITEMS.MEETING.TOP, menuItem}) then
        _updateMenuBarIcon(menuBarIcon, iconTitle)
        _change()
    end
end

-- Examines the current muted status of either audio or video
--  & performs a click to change to the opposite
function _toggleInputSetting(muteItem, unmuteItem, menuBarIcon, mutedTitle, unmutedTitle)
    local current = _determineInputStatus(muteItem, unmuteItem)
    local itemToClick = muteItem
    local iconTitle = mutedTitle

    if current == INPUT_STATES.MUTED then
        itemToClick = unmuteItem
        iconTitle = unmutedTitle
    end
    _changeInputSetting(itemToClick, menuBarIcon, iconTitle)
end

--[[
--------------------------------------------------------
-- External API
--------------------------------------------------------
]]
function obj:start()
    -- hs.printf('starting app watcher in spoon')
    _start_zoom_state_watcher(_getZoomInstance())
    app_watcher:start()
    self.audio:setIcon()
    _determineZoomState()
end
function obj:stop()
    app_watcher:stop()
    _stop_zoom_state_watcher()
end
function obj:inMeeting()
    return Zoom_State:is('meeting') or Zoom_State:is('sharing')
end
function obj:leaveMeeting()
    local app = _getZoomInstance()
    if (app ~= nil) then
        local meetingWindow = app:findWindow(WINDOW_TITLES.MEETING)

        if (meetingWindow ~= nil) then
            -- hs.printf('ending meeting')
            meetingWindow:close() -- this opens leave/end submenu
            hs.eventtap.keyStroke({}, 'return') -- triggers end meeting option of submenu
        end
    end
end
-- Focuses on Zoom window, prioritising order: Meeting -> Sharing -> Webinar -> Main
-- Returns the hs.window object on successful focus
function obj:focus()
    local window = _determineZoomState(false)
    if (window ~= nil) then
        return window:focus()
    end
    return nil
end
-- new feature: delete join zoom meeting tabs from chrome when going from-running-to-meeting

-------------------
-- spoon.Zoom.audio
-------------------
function obj.audio:status()
    return _determineInputStatus(MENU_ITEMS.MEETING.MUTE_AUDIO, MENU_ITEMS.MEETING.UNMUTE_AUDIO, self.icon.menuBarItem,
               self.icon.mutedTitle, self.icon.unmutedTitle)
end
function obj.audio:mute()
    return _changeInputSetting(MENU_ITEMS.MEETING.MUTE_AUDIO, self.icon.menuBarItem, self.icon.mutedTitle)
end
function obj.audio:unmute()
    return _changeInputSetting(MENU_ITEMS.MEETING.UNMUTE_AUDIO, self.icon.menuBarItem, self.icon.unmutedTitle)
end
function obj.audio:toggleMute()
    return _toggleInputSetting(MENU_ITEMS.MEETING.MUTE_AUDIO, MENU_ITEMS.MEETING.UNMUTE_AUDIO, self.icon.menuBarItem,
               self.icon.mutedTitle, self.icon.unmutedTitle)
end
function obj.audio:setIcon() -- setIcon(userMenuBarItem)
    -- local targetMenuBarItem = userMenuBarItem or self.icon.menuBarItem
    self.icon = _buildIcon(self.icon.menuBarItem)
end

-------------------
-- spoon.Zoom.video
-------------------
function obj.video:status()
    return _determineInputStatus(MENU_ITEMS.MEETING.STOP_VIDEO, MENU_ITEMS.MEETING.START_VIDEO)
end
function obj.video:mute()
    return _changeInputSetting(MENU_ITEMS.MEETING.STOP_VIDEO)
end
function obj.video:unmute()
    return _changeInputSetting(MENU_ITEMS.MEETING.START_VIDEO)
end
function obj.video:toggleMute()
    return _toggleInputSetting(MENU_ITEMS.MEETING.STOP_VIDEO, MENU_ITEMS.MEETING.START_VIDEO)
end

-------------------
-- spoon.Zoom.chat
-------------------
function obj.chat:open()
    return _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.SHOW_CHAT})
end
function obj.chat:close()
    return _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.CLOSE_CHAT})
end
-- function obj.chat:focus()
--     -- this needs either cleaned up or deleted...
--     local result = _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.SHOW_CHAT})
--     local app = _getZoomInstance()
--     if (app ~= nil) then
--         local chatWindow = app:findWindow(WINDOW_TITLES.CHAT)
--         if (chatWindow ~= nil) then
--             -- TODO: fucking zoom main window always steals focus...
--             return chatWindow:focus()
--         end
--     end
--     return result
-- end

-------------------
-- spoon.Zoom.participants
-------------------
-- TODO: get participant count
function obj.participants:open()
    return _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.SHOW_PARTICIPANTS})
end
function obj.participants:close()
    return _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.CLOSE_PARTICIPANTS})
end
-- function obj.participants:focus()
--     -- this needs either cleaned up or deleted...
--     local result = _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.SHOW_PARTICIPANTS})
--     local app = _getZoomInstance()
--     if (app ~= nil) then
--         local participantsWindow = app:findWindow(WINDOW_TITLES.PARTICIPANTS)
--         if (participantsWindow ~= nil) then
--             -- TODO: fucking zoom main window always steals focus...
--             return participantsWindow:focus()
--         end
--     end
--     return result
-- end

-------------------
-- spoon.Zoom.share
-------------------
function obj.share:stop()
    return _click({MENU_ITEMS.MEETING.TOP, MENU_ITEMS.MEETING.STOP_SHARE})
end
function obj.share:showControls()
    return _click({MENU_ITEMS.VIEW.TOP, MENU_ITEMS.VIEW.SHOW_SHARE_CONTROLS})
end

--[[
--------------------------------------------------------
-- User-Defined Callback Functions
--------------------------------------------------------
]]--
---------------------------------------------------------------------------------------------
-- Registers a function to be called whenever Zoom's state is changed or examined
--     Parameters:
--     func - A function in the form function(currentState, audioStatus, videoStatus)
--         currentState = a string representing the current state of the Zoom State Machine
--         audioStatus = a string representing the current Zoom Audio state
--         videoStatus = a string representing the current Zoom Video state
---------------------------------------------------------------------------------------------
function obj:setStatusCallback(func)
    -- hs.printf('setting zoom state callback')
    self.stateCallbackFunction = func
end
---------------------------------------------------------------------------------------------
-- Registers a function to be called whenever a Zoom state transition occurs
--     Parameters:
--     func - A function in the form function(stateTransition)
--         stateTransition = a string representing the state transition in the form: 'from-running-to-meeting'
---------------------------------------------------------------------------------------------
function obj:setTransitionCallback(func)
    -- hs.printf('setting zoom transition callback')
    self.transitionCallbackFunction = func
end

--[[
--------------------------------------------------------
-- Spoon Delivery
--------------------------------------------------------
]]
return obj
