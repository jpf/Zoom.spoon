#+TITLE: Documentation for the Unoffical Zoom Spoon
* What this Spoon does

This is a [[https://www.hammerspoon.org/Spoons/][Spoon]] (or plugin) that makes it easier for Hammerspoon to interact with the Zoom videotelephony software.

If you aren't familiar with  [[https://www.hammerspoon.org/][Hammerspoon]] yet, it is a powerful programmable automation tool for macOS.

Using this Spoon in concert with Hammerspoon, you can do things like:
- Get notified when the Zoom app opens, starts a meeting, or starts screensharing
- Get notified when the Zoom app closes, stops a meeting, or stops screensharing
- Mute Zoom when it's open and in a meeting or screensharing
- Unmute Zoom when it's open and in a meeting or screensharing

- Mute & unmute Zoom Audio or Video, even if your meeting window is buried under other apps

The original goal for this Spoon was to enable the author to create a "mute status light" for Zoom.

* How to install this Spoon

1. Make sure that you have Hammerspoon installed

   If it's not installed already, then use the [[https://www.hammerspoon.org/go/][Getting Started with Hammerspoon]] guide to learn how to install and use Hammerspoon.

2. Install the Zoom Spoon

   The easiest way to do this is to download the [[https://github.com/jpf/Zoom.spoon/archive/main.zip][ZIP version of this Spoon]], unzip it, then double click the =Zoom.spoon= folder. Hammerspoon will install it for you.

   If you plan on modifying the Spoon and sending a pull request to this repo, then you should clone this repo into your =~/.hammerspoon/Spoons=

* How to use this Spoon

Open your Hammerspoon configuration file and edit it to make use of this Spoon. Below is a sample configuration that does the following:

- Creates a menu bar item that will display a red circle when a Zoom meeting is in progress and you are muted and a green circle if you are unmuted
- Will toggle between mute and unmute if the red or green circle is clicked
- Will assign the =F13= button to be a mute toggle button

#+BEGIN_SRC lua
-- This lets you click on the menu bar item to toggle the mute state
zoomStatusMenuBarItem = hs.menubar.new(nil)
zoomStatusMenuBarItem:setClickCallback(function()
    spoon.Zoom:toggleMute()
end)

updateZoomStatus = function(event)
  hs.printf("updateZoomStatus(%s)", event)
  if (event == "from-running-to-meeting") then
    zoomStatusMenuBarItem:returnToMenuBar()
  elseif (event == "muted") then
    zoomStatusMenuBarItem:setTitle("🔴")
  elseif (event == "unmuted") then
    zoomStatusMenuBarItem:setTitle("🟢")
  elseif (event == "from-meeting-to-running") or (event == "from-running-to-closed") then
    zoomStatusMenuBarItem:removeFromMenuBar()
  end
end

hs.loadSpoon("Zoom")
spoon.Zoom:setStatusCallback(updateZoomStatus)
spoon.Zoom:start()

-- Next up:
-- https://github.com/adamyonk/PushToTalk.spoon/blob/master/init.lua
hs.hotkey.bind('', 'f13', function()
  spoon.Zoom:toggleMute()
end)
#+END_SRC

These three lines are the most important:
#+BEGIN_SRC lua
hs.loadSpoon("Zoom")
spoon.Zoom:setStatusCallback(updateZoomStatus)
spoon.Zoom:start()
#+END_SRC

The first line, =hs.loadSpoon("Zoom")=, loads this Spoon.
The second line, uses the =spoon.Zoom:setStatusCallback()= method to have the =updateZoomStatus= function called when the state of the Zoom app changes.
And finally, the last line, =spoon.Zoom:start()= starts up the Zoom spoon.
