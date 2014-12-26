--- === hs.uielement ===
--- A generalized framework for working with OSX UI elements.

local uielement = require "hs.uielement.internal"
local application = {}
application.watcher = require "hs.application.watcher"
local fnutils = require "hs.fnutils"

--- hs.uielement:isWindow() -> bool
--- Returns whether the UI element represents a window.
function uielement:isWindow()
    return self:role() == "AXWindow"
end

--- hs.uielement:isApplication() -> bool
--- Returns whether the UI element represents an application.
function uielement:isApplication()
    return self:role() == "AXApplication"
end

--- hs.uielement.watcher
--- Defines events that can be watched using hs.uielement.watcher.
---
--- You can watch the following events:
--- ### Application-level events
--- See hs.application.watcher for more events you can watch.
--- * hs.uielement.watcher.applicationActivated: The current application switched to this one.
--- * hs.uielement.watcher.applicationDeactivated: The current application is no longer this one.
--- * hs.uielement.watcher.applicationHidden: The application was hidden.
--- * hs.uielement.watcher.applicationShown: The application was shown.
--- #### Focus change events
--- These events are watched on the application level, but send the relevant child element to the handler.
--- * hs.uielement.watcher.mainWindowChanged: The main window of the application was changed.
--- * hs.uielement.watcher.focusedWindowChanged: The focused window of the application was changed. Note that the application may not be activated itself.
--- * hs.uielement.watcher.AXFocusedUIElementChanged: The focused UI element of the application was changed.
---
--- ### Window-level events
--- * hs.uielement.watcher.windowCreated: A window was created. You should watch for this event on the application, or the parent window.
--- * hs.uielement.watcher.windowMoved: The window was moved.
--- * hs.uielement.watcher.windowResized: The window was resized.
--- * hs.uielement.watcher.windowMinimized: The window was minimized.
--- * hs.uielement.watcher.windowUnminimized: The window was unminimized.
---
--- ### Element-level events
--- These work on all UI elements, including windows.
--- * hs.uielement.watcher.elementDestroyed: The element was destroyed.
--- * hs.uielement.watcher.titleChanged: The element's title was changed.

uielement.watcher.applicationActivated   = "AXApplicationActivated"
uielement.watcher.applicationDeactivated = "AXApplicationDeactivated"
uielement.watcher.applicationHidden      = "AXApplicationHidden"
uielement.watcher.applicationShown       = "AXApplicationShown"

uielement.watcher.mainWindowChanged     = "AXMainWindowChanged"
uielement.watcher.focusedWindowChanged  = "AXFocusedWindowChanged"
uielement.watcher.focusedElementChanged = "AXFocusedUIElementChanged"

uielement.watcher.windowCreated     = "AXWindowCreated"
uielement.watcher.windowMoved       = "AXWindowMoved"
uielement.watcher.windowResized     = "AXWindowResized"
uielement.watcher.windowMinimized   = "AXWindowMiniaturized"
uielement.watcher.windowUnminimized = "AXWindowDeminiaturized"

uielement.watcher.elementDestroyed = "AXUIElementDestroyed"
uielement.watcher.titleChanged     = "AXTitleChanged"


-- Keep track of apps, to automatically stop watchers on apps AND their elements when apps quit.

local appWatchers = {}

local function appCallback(name, event, app)
    if appWatchers[app:pid()] and event == application.watcher.terminated then
        fnutils.each(appWatchers[app:pid()], function(watcher) watcher:_stop() end)
        appWatchers[app:pid()] = nil
    end
end

local globalAppWatcher = application.watcher.new(appCallback)
globalAppWatcher:start()

-- Keep track of all other UI elements to automatically stop their watchers.

local function handleEvent(callback, element, event, watcher, userData)
    if event == watcher.elementDestroyed then
        -- element is newly created from a dead UI element and may not have critical fields like pid and id.
        -- Use the existing watcher element instead.
        if element == watcher:element() then
            element = watcher:element()
        end

        -- Pass along event if wanted.
        if watcher._watchingDestroyed then
            callback(element, event, watcher, userData)
        end

        -- Stop watcher.
        if element == watcher:element() then
            watcher:stop()  -- also removes from appWatchers
        end
    else
        callback(element, event, watcher, userData)
    end
end

--- hs.uielement:newWatcher(handler[, userData]) -> hs.uielement.watcher
--- Method
--- Creates a new watcher for the element represented by self.
---
--- You must pass a handler function. The args passed are as follows:
--- * element: The element the event occurred on. Note this is not always the element being watched.
--- * event: The name of the event that occurred.
--- * watcher: The watcher object being created.
--- * userData: The userData you included, if any.
function uielement:newWatcher(callback, ...)
    local obj = self:_newWatcher(function(...) handleEvent(callback, ...) end, ...)

    obj._pid = self:pid()
    if self.id then obj._id = self:id() end

    return obj
end

--- hs.uielement.watcher:start(events)
--- Method
--- Tells the watcher to start watching the given list of events.
---
--- See hs.uielement.watcher for a list of events. You may also specify arbitrary event names as strings.
---
--- Does nothing if the watcher has already been started. To start with different events, stop it first.
function uielement.watcher:start(events)
    -- Track all watchers in appWatchers.
    local pid = self._element:pid()
    if not appWatchers[pid] then appWatchers[pid] = {} end
    table.insert(appWatchers[pid], self)

    -- For normal elements, listen for elementDestroyed events.
    if not self._element:isApplication() then
        if fnutils.contains(events, self.elementDestroyed) then
            self._watchingDestroyed = true
        else
            self._watchingDestroyed = false
            events = fnutils.copy(events)
            table.insert(events, self.elementDestroyed)
        end
    end

    -- Actually start the watcher.
    return self:_start(events)
end

--- hs.uielement.watcher:stop()
--- Method
--- Tells the watcher to stop listening for events.
--- This is automatically called if the element is destroyed.
function uielement.watcher:stop()
    -- Remove self from appWatchers.
    local pid = self._element:pid()
    if appWatchers[pid] then
        local idx = fnutils.indexOf(appWatchers[pid], self)
        if idx then
            table.remove(appWatchers[pid], idx)
        end
    end

    self:_stop()
end

--- hs.uielement.watcher:element()
--- Method
--- Returns the element the watcher is watching.
function uielement.watcher:element()
    return self._element
end

return uielement
