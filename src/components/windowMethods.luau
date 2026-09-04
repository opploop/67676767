--!nonstrict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Part of the Window class - see window.luau's own header comment for why this file exists
-- (Roblox's 200,000 character ModuleScript Source limit) and windowCore.luau's for how the split
-- actually holds together (a shared core module, not a circular require). Every `function
-- Window:X` below attaches to the exact same table window.luau's Window.new builds instances
-- against - this file is required purely for that side effect, from window.luau's own tail.

local core = require(script.Parent.windowCore)
local Window = core.Window

-- Utility (aliased off windowCore so every split file shares the exact same module instances -
-- see windowCore.luau's own header comment)
local image = core.image
local functions = core.functions
local persistence = core.persistence
local constants = core.constants
local locale = core.locale
local log = core.log
local hapticEngine = core.hapticEngine
local soundEngine = core.soundEngine
local windowSizing = core.windowSizing
local icons = core.icons
local acrylic = core.acrylic
local clipboard = core.clipboard
local chrome = core.chrome
local search = core.search
local tabSelector = require(script.Parent.tabSelector)
local filesystem = core.filesystem
local path = core.path
local variables = core.variables
local themes = core.themes

-- Shared constants/helpers (see windowCore.luau)
local revealInfo = core.revealInfo
local collapsedSize = core.collapsedSize
local collapsedTop = core.collapsedTop
local maxToastWidth = core.maxToastWidth
-- Ported from upstream Rayfield Gen2 1.2's own fix: a top-centre toast used to land at the same
-- spot the collapsed "Tap to show" pill rests at, live-overlapping it. Closed, the stack drops
-- to just below the pill instead; open, it sits back at its normal spot under the topbar.
local topToastOpenPosition = UDim2.new(0.5, 0, 0, 12)
local topToastClosedPosition = UDim2.new(0.5, 0, 0, collapsedTop.Y.Offset + collapsedSize.Y.Offset + 12)
local compactRowHeight = core.compactRowHeight
local viewportReconcileInterval = core.viewportReconcileInterval
local fitWindowSize = core.fitWindowSize
local resolveCustomSize = core.resolveCustomSize
local fontChoices = core.fontChoices
local fontOptionNames = core.fontOptionNames
local fontAtWeight = core.fontAtWeight
local gradientKeys = core.gradientKeys
local coerceThemeValue = core.coerceThemeValue
local firstColor = core.firstColor
local edgeShade = core.edgeShade
local deriveStrokes = core.deriveStrokes
local themeOverrides = core.themeOverrides
local resolveTheme = core.resolveTheme
local WINDOW_REGISTRY_KEY = core.WINDOW_REGISTRY_KEY
local windowRegistry = core.windowRegistry

function Window:_syncLiveAnimation()
    if not self.theme.LiveAnimation then
        self._liveAnimating = false -- the running loop sees this and stops after its current leg
        return
    end
    if self._liveAnimating then
        return -- already drifting
    end

    self._liveAnimating = true
    -- generation stamp: an old loop parked in Completed:Wait() through a static->animated
    -- swap wakes up stale and exits, instead of drifting alongside the new loop
    self._liveGeneration = (self._liveGeneration or 0) + 1
    local generation = self._liveGeneration
    task.spawn(function()
        local out = true
        local tweenInfo = TweenInfo.new(10, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        while self._liveGeneration == generation and self._liveAnimating and not self.unloaded do
            local tweenW = variables.tweenService:Create(self.windowGradient, tweenInfo, {
                Offset = Vector2.new(if out then 0.4 else -0.2, 0),
                Rotation = (if out then 220 else 280),
            })

            self._liveTween = tweenW
            tweenW:Play()
            tweenW.Completed:Wait()
            out = not out
        end
        if self._liveGeneration == generation then
            self._liveAnimating = false
            self._liveTween = nil
        end
    end)
end

-- Re-applies the per-window visual overrides passed at CreateWindow (cornerRadius/borderColor/
-- gradientColorSequence/shadowColor - see window.luau's own construction-time comment on these)
-- on top of self.theme. Called once at construction and again from ChangeTheme below, which
-- otherwise re-resolves self.theme from scratch and would silently drop them right back to
-- whatever the newly-picked theme's own defaults are.
function Window:_applyThemeOverrides()
    if self._cornerRadiusOverride then
        self.theme.CornerRoundness = UDim.new(0, self._cornerRadiusOverride)
    end
    if self._borderColorOverride then
        self.theme.SurfaceStroke = self._borderColorOverride
        self._showBorder = true
    end
    if self._gradientColorOverride then
        self.theme.WindowColor = self._gradientColorOverride
    end
    if self._shadowColorOverride then
        self.theme.ShadowColor = self._shadowColorOverride
    end
end

function Window:ChangeTheme(theme)
    -- A named theme fully switches: resolve against default so keys it omits reset rather than
    -- lingering from the previous theme. A partial table just overrides the keys it names.
    local overrides = if typeof(theme) == "table" then theme else resolveTheme(theme)
    for name, value in overrides do
        self.theme[name] = coerceThemeValue(name, value)
    end
    -- match the constructor: a hand-written table gets derived strokes for the keys it changes
    if typeof(theme) == "table" then
        deriveStrokes(self.theme, overrides)
    end
    -- re-pin this window's own per-window overrides on top of whatever the swap just resolved -
    -- see _applyThemeOverrides' own comment for why this has to happen here too, not just once.
    self:_applyThemeOverrides()

    for instance, properties in self.themeProperties do
        for property, value in properties do
            local targetValue = if typeof(value) == "table" then value[2](self.theme[value[1]]) else self.theme[value]

            if typeof(targetValue) == "Color3" or typeof(targetValue) == "number" then
                variables.tweenService
                    :Create(
                        instance,
                        TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
                        { [property] = targetValue }
                    )
                    :Play()
            else
                instance[property] = targetValue
            end
        end
    end

    -- themeProperties above only carry plain colours; reveal-driven transparencies and state
    -- colours (the toggle knob, field fills, glows) aren't, so refresh the elements to reach
    -- them on a live swap. Every tab's elements stay shown (just page-clipped), settings
    -- included, so refresh them all; groups forward the call to their children.
    if self.hidden then
        -- a hidden window has nothing to animate into, so defer the refresh to the next Show
        -- rather than dropping it and reopening with the old themes state colours
        self._themeRefreshPending = true
    else
        self:_refreshElementThemes()
    end

    self:_syncLiveAnimation()

    -- see OnThemeChanged's own comment - a dev's own hand-built RichText (baked-in <font
    -- color="..."> literals) needs telling explicitly, unlike every Rayfield-built element above.
    for _, callback in self._themeChangedCallbacks do
        task.spawn(callback, self.theme)
    end
end

-- Register a callback for whenever the active theme changes (ChangeTheme, including a player's
-- own Settings > Color theme swap) - fires with the new theme table. Rayfield's own elements
-- already retint themselves via themeProperties/refreshElementThemes; this is for a consumer
-- script's own hand-built RichText (e.g. a `<font color="rgb(...)">` baked from theme.AccentColor
-- at label-creation time) that has no other way to hear about a later swap.
function Window:OnThemeChanged(callback: (theme: { [string]: any }) -> ())
    table.insert(self._themeChangedCallbacks, callback)
end

-- Devlog 6/7 Settings > Font picker: "Auto" (the brand font) or any built-in Roblox font by
-- name. Just a partial ChangeTheme under the hood - Font/TitleFont are already ordinary
-- themeProperties (every FontFace = "Font"/"TitleFont" binding made via Create), so swapping
-- them through here reaches every live element the same way any other theme change does.
function Window:SetFont(name)
    local key = string.lower(tostring(name or "auto"))
    if key ~= "auto" and fontChoices[key] == nil then
        log.warn("Rayfield: unknown font '" .. tostring(name) .. "', using Auto")
        key = "auto"
    end
    self.fontChoice = key

    local titleFont, bodyFont
    if key == "auto" then
        titleFont = variables.brandFont(Enum.FontWeight.SemiBold)
        bodyFont = variables.brandFont(Enum.FontWeight.Medium)
    else
        local enumFont = fontChoices[key]
        titleFont = fontAtWeight(enumFont, Enum.FontWeight.SemiBold)
        bodyFont = fontAtWeight(enumFont, Enum.FontWeight.Medium)
    end

    self:ChangeTheme({ Font = bodyFont, TitleFont = titleFont })
end

-- Devlog 7 "glass window": 0 (fully opaque, default) to 100 (fully invisible). Scales the
-- window frame, the tab dock, and every card uniformly so it all reads as one sheet of glass
-- rather than a stack of independently-faded pieces. Cards ride along for free: ElementTransparency
-- is an ordinary themeProperty already, so pushing a scaled value through ChangeTheme reaches
-- every card the same way any other live theme change does. self.main and self.tabDock aren't
-- theme-bound (their own baselines - fully opaque and 0.2 - are plain literals set once at
-- creation, not read from the theme), so those two get tweened directly instead.
--
-- Reaching literal BackgroundTransparency 1 is safe: a plain Frame's default Active is false,
-- and per Roblox's own rule that stops it blocking/capturing input in its own bounds the moment
-- transparency hits exactly 1 - live-caught this at 100%, the whole window (and every card,
-- ElementTransparency-bound the same way) went click-through to the game behind it, which is
-- what "can't drag the handle back" and "the UI goes into the game's background" both were.
-- Fixed at the source instead of just avoiding the value: self.main, self.tabDock, and every
-- card (via Window:StyleElementBody, or directly where a component styles its own card outside
-- that helper) now set Active = true explicitly, so they stay clickable at any transparency.
function Window:SetTransparency(percent)
    percent = math.clamp(percent, 0, 100)
    self.windowOpacity = 1 - percent / 100

    self:ChangeTheme({ ElementTransparency = 1 - self.windowOpacity })

    local info = TweenInfo.new(0.3, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local target, prop = self:_mainVisual()
    variables.tweenService:Create(target, info, { [prop] = 1 - self.windowOpacity }):Play()
    -- Sidebar mode's own visible fill lives on tabDockCard now, not tabDock itself (see its own
    -- construction comment) - tabDock there stays permanently transparent as a plain structural
    -- container, so tweening it directly would visibly do nothing.
    variables.tweenService
        :Create(self.tabDockCard or self.tabDock, info, { BackgroundTransparency = 1 - 0.8 * self.windowOpacity })
        :Play()
end

-- Devlog 7 "Acrylic Blur": frosts the game behind the window via a Lighting.BlurEffect (see
-- acrylic.luau for why that, and not the DepthOfFieldEffect trick some other UI libraries lean
-- on, is the right tool here). size is BlurEffect.Size (roughly 0-56); omit for a sane default.
function Window:SetAcrylic(enabled, size)
    self.acrylicEnabled = enabled and true or false
    acrylic.setEnabled(self.acrylicEnabled, size)
end

function Window:_refreshElementThemes()
    for _, tab in self.tabs do
        for _, element in tab.elements do
            if element._refreshTheme then
                element:_refreshTheme()
            end
        end
    end
end

function Window:CreateTab(properties)
    local newTab = require(script.Parent.tab).new(self, properties)

    table.insert(self.tabs, newTab)

    -- Tab.new's own construction always builds a visible title (it has no way to know the
    -- sidebar's current width yet, since self.tabs doesn't include this tab until the line
    -- above) - re-applying the window's already-known width immediately covers a tab created
    -- collapsed-by-default (sidebarCollapsed/sidebarWidth at CreateWindow) or one added later
    -- while a player's already dragged the rail down to icon-only.
    if self.tabsMode == "Sidebar" then
        self:_applySidebarWidth(self.sidebarWidth)
    end

    if not newTab.neglectSelector then
        local isFirstVisible = true
        for _, tab in self.tabs do
            if tab ~= newTab and not tab.neglectSelector then
                isFirstVisible = false
                break
            end
        end
        if isFirstVisible then
            newTab:Select(true)
        end

        -- a tab built after the window is already open reveals its pill right away, the
        -- same way _register shows late elements. hidden/minimised windows reveal on restore.
        if not self.hidden and not self.minimised then
            newTab.topbarItem.Visible = true
            newTab:_applyVisual(
                if self.selectedTab == newTab then "selected" else "unselected",
                TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            )
        end
    end

    return newTab
end

-- A heading in the sidebar rail (Sidebar tabsMode only - see tabSection.luau's own header
-- comment for why it does nothing on the top strip). Same props as a Tab's own CreateSection,
-- and it groups the tab rows created after it the way that one groups elements. Ported from
-- upstream Rayfield Gen2 1.2's own Tab Sections.
function Window:CreateSection(properties)
    assert(not self.unloaded, "Cannot create a section on an unloaded window.")
    local section = require(script.Parent.tabSection).new(self, properties)
    table.insert(self.tabSections, section)

    -- built after the window is already open: reveal it now, the same way a late tab reveals
    -- its row rather than waiting for the next open
    if not section.inert and not self.hidden and not self.minimised then
        section:_setVisible(true)
        section:_setShown(true, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    end

    return section
end

-- Sections ride with the rows they label, so every path that fades or hides the rail's rows
-- says the same thing to them.
function Window:_setTabSectionsShown(shown, tweenInfo)
    for _, section in self.tabSections do
        section:_setShown(shown, tweenInfo)
    end
end

function Window:_setTabSectionsVisible(visible)
    for _, section in self.tabSections do
        section:_setVisible(visible)
    end
end

-- Element Locking, ported from upstream Rayfield Gen2 1.2. Lock or unlock one element - it
-- dims and an opaque scrim (see _buildLockScrim) physically covers it, so a real click never
-- reaches the control underneath and its own callback simply never runs. `reason` replaces the
-- element's description while it's locked, so the UI can say why without covering the element
-- up to do it. Reached through the lockable.luau mixin's own Lock/Unlock/IsLocked - see that
-- file's header comment for which components use this directly vs. their own bespoke
-- SetLocked.
local lockScrimTransparency = 0.55
local lockedDescriptionTransparency = 0.55

function Window:_setElementLocked(element, locked, reason)
    locked = locked == true
    -- locked starts out nil, so compare against a real boolean: `nil == false` is false, and
    -- Unlock on an element that was never locked would otherwise build a scrim just to fade it
    -- straight back out. A fresh reason on an already-locked element is still worth applying.
    local wasLocked = element.locked == true
    if wasLocked == locked and not (locked and reason) then
        return
    end
    element.locked = locked

    if not element.lockScrim then
        self:_buildLockScrim(element)
    end

    local info = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    if locked then
        element.lockScrim.Visible = true
    end
    variables.tweenService
        :Create(element.lockScrim, info, {
            BackgroundTransparency = if locked then lockScrimTransparency else 1,
        })
        :Play()
    if not locked then
        task.delay(info.Time, function()
            if not element.locked and element.lockScrim then
                element.lockScrim.Visible = false -- out of hit-testing once it has faded
            end
        end)
    end

    -- say why in the description, and put the element's own back when it unlocks
    local descriptor = element.descriptor
    if not descriptor then
        return
    end

    if locked then
        -- `or`, not plain assignment: re-locking with a new reason must not remember the old
        -- reason as though it were the element's own description
        element._descriptionBefore = element._descriptionBefore or descriptor.titleLabel.Text
        descriptor.titleLabel.Text = locale.resolve(reason or "This element is locked.")
    elseif element._descriptionBefore then
        descriptor.titleLabel.Text = element._descriptionBefore
        element._descriptionBefore = nil
    end

    variables.tweenService
        :Create(descriptor.titleLabel, info, {
            TextTransparency = if locked then lockedDescriptionTransparency else 0.7,
        })
        :Play()
end

-- The scrim: a sheet of the window's own colour over the element, dimming it. It carries
-- nothing itself - it's the dimming and the description that say what's happened. It is an
-- Active button, so it swallows anything aimed at the element underneath rather than leaving
-- each element to check a flag on every input path.
local function firstColor(value)
    return if typeof(value) == "ColorSequence" then value.Keypoints[1].Value else value
end

function Window:_buildLockScrim(element)
    element.lockScrim = self:Create("TextButton", {
        Name = "ElementLock",
        Active = true,
        AutoButtonColor = false,
        Size = UDim2.fromScale(1, 1),
        BorderSizePixel = 0,
        Text = "",
        TextTransparency = 1,
        ZIndex = 60, -- over the element's own content, so a locked element cant be reached through it
        Visible = false,

        -- no literal BackgroundColor3 here: Create applies the theme first and plain properties
        -- second, so setting it both ways would paint straight over the themed colour
        BackgroundTransparency = 1, -- In = lockScrimTransparency

        Parent = element.main,
    }, { BackgroundColor3 = { "WindowColor", firstColor } })

    self:Create("UICorner", {
        Parent = element.lockScrim,
    }, { CornerRadius = "ElementCornerRadius" })
end

-- Alias for CreateTab({ neglectSelector = true }) - a tab left out of the normal tab dock,
-- reachable only by calling :Select() on it yourself (typically from a button/stat elsewhere -
-- "See full details" -> detailsTab:Select()). Good for a drill-down screen (full diagnostics, an
-- expanded account view) that would clutter the main tab list if it sat there permanently.
-- neglectSelector itself already existed (it's how the built-in Rayfield Settings tab stays out
-- of the dock) - this is just a clearer public name for a dev reaching for the same thing on
-- purpose, matching the "hidden tab + a card linking into it" pattern both hub scripts land on
-- independently for the same reason.
-- A small draggable status chip independent of the main window (see hud.luau's own header
-- comment) - stays visible and keeps updating even while the window itself is hidden. Returns a
-- handle with :SetText(text) and :Destroy().
function Window:CreateHUD(properties)
    return require(script.Parent.hud).new(self, properties)
end

function Window:CreateHiddenTab(properties)
    properties = if typeof(properties) == "table" then table.clone(properties) else {}
    properties.neglectSelector = true
    return self:CreateTab(properties)
end

-- Sidebar mode only. self.sidebarWidth is a fixed constant now (no more player drag handle -
-- see window.luau's own comment) - this just re-derives tabDock and the content pane's Size/
-- Position from it, the same formula window.luau's constructor used in the first place. Kept as
-- its own method (rather than inlined at each call site) since CreateTab's own re-application
-- and the public SetSidebarWidth wrapper below both still need to call it.
-- The sidebar is a fixed width now (self.sidebarWidth, matching upstream Rayfield Gen2 1.2's own
-- railWidth) - no more player drag handle or icon-only collapse state, so this just applies
-- self.sidebarWidth itself regardless of what's asked for. Kept (rather than removed outright)
-- so SetSidebarWidth/OnSidebarWidthChanged/CreateTab's own re-application still have a real,
-- harmless method to call instead of erroring.
function Window:_applySidebarWidth(_width: number?)
    -- The window's own width is the only input: narrow enough and the rail collapses to icons
    -- (upstream's railCollapseBelow/railCollapsedWidth), otherwise it's the full rail.
    local windowWidth = self.size and self.size.X.Offset or self.main.AbsoluteSize.X
    -- A dev (or SetSidebarCollapsed) can pin it either way; nil means follow the window's width.
    local collapsed = if self._sidebarCollapsedOverride ~= nil
        then self._sidebarCollapsedOverride
        else windowWidth < self.sidebarCollapseBelow
    local width = if collapsed then self.sidebarCollapsedWidth else self.sidebarFullWidth
    self.sidebarWidth = width

    self.tabDock.Size = UDim2.new(0, width, 1, -85)
    -- self.elements is anchored (1,1) now (flush against the window's own right/bottom edges -
    -- see window.luau's own construction comment), so only its Size needs re-deriving here.
    self.elements.Size = UDim2.new(1, -width, 1, -70)

    for _, tab in self.tabs do
        if not tab.neglectSelector then
            tabSelector.setRowCollapsed(tab, collapsed)
        end
    end

    -- Profile chip follows the same collapse: avatar alone, centred, once there's no room for
    -- the name/subtitle column beside it.
    if self.profile then
        self.profile.Size = UDim2.fromOffset(width, self.profileFooterHeight)
        self.profileContainer.Position = UDim2.new(0, if collapsed then 0 else 12, 0.5, 0)
        self.profileContainer.Size = UDim2.new(1, if collapsed then 0 else -12, 1, 0)
        self.profileLayout.HorizontalAlignment = if collapsed
            then Enum.HorizontalAlignment.Center
            else Enum.HorizontalAlignment.Left
        self.profileLabels.Visible = not collapsed
    end
end

-- Hear about every real sidebar-width change (drag, SetSidebarWidth, or CreateTab's own
-- re-application), regardless of who caused it - e.g. a consumer script mirroring the live width
-- into its own persisted flag (see Window:RegisterFlag in windowExtra.luau).
function Window:OnSidebarWidthChanged(callback: (width: number) -> ())
    table.insert(self._sidebarWidthChangedCallbacks, callback)
end

-- Public wrapper - a dev can call this directly (e.g. restoring a player's last dragged width
-- from their own saved data) without reaching into the underscore-prefixed method above.
function Window:SetSidebarWidth(width: number)
    self:_applySidebarWidth(width)
end

-- Pin the rail to its compact (icon-only + avatar-only) shape, or back to the full one. Pass nil
-- to hand it back to the window's own width (collapses under sidebarCollapseBelow on its own).
function Window:SetSidebarCollapsed(collapsed: boolean?)
    self._sidebarCollapsedOverride = if collapsed == nil then nil else collapsed == true
    self:_applySidebarWidth()
end

-- Set the line under the player's name in the sidebar profile chip ("Premium", a rank, a tier).
-- Empty (or nil) drops the line entirely. Sidebar tabsMode only - no-op if this window has no
-- profile chip to put it in (Top mode, or no LocalPlayer to build one for). Ported from
-- upstream Rayfield Gen2 1.2.
function Window:SetProfile(text: string?)
    self.profileText = text
    if not self.profileSubtitle then
        return
    end
    local resolved = if type(text) == "string" and text ~= "" then locale.resolve(text) else nil
    self.profileSubtitle.Text = resolved or ""
    self.profileSubtitle.Visible = resolved ~= nil
end

function Window:CreateTag(properties)
    local newTag = require(script.Parent.tag).new(self, properties)
    table.insert(self.tags, newTag)
    return newTag
end

-- Register a saveable control under its flag. Keeps flags unique so two same-named
-- elements dont clobber each other's saved value. Updates control.flag to the key we
-- actually stored under and returns it.
function Window:_registerControl(control)
    if not control.flag or control.flag == "" or control.forgetState then
        return
    end

    local flag = control.flag
    if self.controls[flag] then
        local n = 2
        while self.controls[flag .. n] do
            n += 1
        end
        flag = flag .. n
        log.warn(
            "Rayfield: duplicate config flag '"
                .. control.flag
                .. "', saving this one as '"
                .. flag
                .. "'. Set a unique flag to keep it stable across sessions."
        )
    end

    control.flag = flag
    self.controls[flag] = control
    return flag
end

-- Restore an element built after the config was already loaded. autoLoad only fires once on
-- first Show, so without this a late element (one built after a remote fetch, say) keeps its
-- default and the next autosave writes that default over the saved value.
-- Called from the CreateX tails once the element is fully built, since _registerControl runs
-- mid-construction and :Set would touch instances that dont exist yet.
function Window:_restoreLate(element)
    if not self._loadedConfig or not element.flag or element.forgetState then
        return
    end

    local wasLoading = self._loading
    self._loading = true -- dont autosave the value we just read back
    persistence.applyTo(element, self._loadedConfig[element.flag])
    self._loading = wasLoading
end

-- Autosave a control's value after an interactive or programmatic change, when the window is
-- set to autoSave and the control opts into persistence. Every Set/commit path funnels here so
-- persistence stays uniform across elements.
function Window:_persist(control)
    -- _loading: a config restore fires every control's callback, but must not autosave back over
    -- the file it's reading (or storm Save once per control)
    if not control.flag or control.forgetState or self._loading then
        return
    end
    if self.configuration.autoSave then
        self:_scheduleAutoSave()
    end
    -- Auto Save Config (see the Configurations section in _buildSettingsUI): additionally keeps
    -- whichever named configuration is currently selected up to date, independent of the single
    -- default file above. self._autoSaveConfigEnabled/_selectedConfigName are plain fields rather
    -- than reads through a control specifically so this works even before that UI section has
    -- built (or if a consumer script sets them directly without ever showing it).
    if self._autoSaveConfigEnabled then
        self:_scheduleAutoSaveConfig()
    end
end

-- How long a debounced autosave waits for the burst to go quiet before actually writing.
local autoSaveDebounce = 0.2

-- Collapses a burst of rapid _persist calls (dragging a slider fires one per frame) into a
-- single deferred Save - generation-stamped so only the *last* call in a burst is the one that
-- actually survives to write the file; every earlier one's delayed write finds itself stale and
-- skips. Re-checks self._loading at fire time too, not just at the call site above, in case a
-- config Load starts mid-debounce (a real risk here: a Load's control-by-control apply is
-- exactly the kind of rapid-fire burst this debounce exists to collapse in the first place).
function Window:_scheduleAutoSave()
    self._autoSaveGeneration = (self._autoSaveGeneration or 0) + 1
    local generation = self._autoSaveGeneration
    task.delay(autoSaveDebounce, function()
        if self._autoSaveGeneration == generation and not self._loading then
            self:Save()
        end
    end)
end

-- Same debounce/generation shape as _scheduleAutoSave, targeting self._selectedConfigName
-- instead of the default file. Re-reads both the enabled flag and the target name at fire time
-- (not just at schedule time) since either can change mid-debounce - e.g. switching the
-- dropdown's selection again before the first save actually lands.
function Window:_scheduleAutoSaveConfig()
    self._autoSaveConfigGeneration = (self._autoSaveConfigGeneration or 0) + 1
    local generation = self._autoSaveConfigGeneration
    task.delay(autoSaveDebounce, function()
        local name = self._selectedConfigName
        if self._autoSaveConfigGeneration == generation and not self._loading and self._autoSaveConfigEnabled and name and name ~= "" then
            self:Save(name)
        end
    end)
end

-- Drop a control from the flag registry when its element is removed, so Save/Load and the
-- Flags view never touch a destroyed instance.
function Window:_unregisterControl(control)
    if control.flag and self.controls[control.flag] == control then
        self.controls[control.flag] = nil
    end
end

-- Recurses into anything that can host its own nested elements (Group, and a Collapsible/Tabbox
-- via the Group(s) underneath them), so a Keybind buried inside a row/column/panel is still
-- found. Used to matter less when Group had no CreateKeybind at all; now that it does, a plain
-- top-level-only scan would silently miss any Keybind not sitting directly in a tab.
local function forEachElement(elements, visit)
    for _, element in elements do
        visit(element)
        if element.__type == "Group" and element.elements then
            forEachElement(element.elements, visit)
        elseif element.__type == "Collapsible" and element._group then
            forEachElement(element._group.elements, visit)
        elseif element.__type == "Tabbox" and element.pages then
            for _, page in element.pages do
                forEachElement(page.elements, visit)
            end
        end
    end
end

-- find a keybind element currently bound to `key`, skipping `exclude` and unbound keys - lets
-- the menu-toggle keybind refuse a key an element keybind already owns, wherever that keybind
-- actually lives (a tab directly, or nested in a Group/Collapsible/Tabbox).
function Window:_keybindUsing(key, exclude)
    if typeof(key) ~= "EnumItem" or key == Enum.KeyCode.Unknown then
        return nil
    end
    local found = nil
    for _, tab in self.tabs do
        if found then
            break
        end
        forEachElement(tab.elements, function(element)
            if not found and element ~= exclude and element.__type == "Keybind" and element.value == key then
                found = element
            end
        end)
    end
    return found
end

function Window:Notify(properties)
    if self.unloaded then
        return -- nothing to parent into once the ScreenGui is gone
    end
    if not self.notifications then
        -- notifySide: Right (default, matches every prior version of this) or Left - the whole
        -- stack's own corner, not a per-call option, since notifications share one growing
        -- container built once on first use.
        local onLeft = self.notifySide == "Left"
        self.notifications = self:Create("Frame", {
            Name = "Notifications",
            Size = UDim2.new(0, 300, 0, 800),
            Position = if onLeft then UDim2.new(0, 20, 1, -20) else UDim2.new(1, -20, 1, -20),
            AnchorPoint = if onLeft then Vector2.new(0, 1) else Vector2.new(1, 1),
            BackgroundTransparency = 1,

            Parent = self.screenGui,
        })

        self:Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            -- No padding here: the gap lives inside each notification so removing
            -- one doesn't drop an external gap and jolt the stack.
            Padding = UDim.new(0, 0),

            Parent = self.notifications,
        })
    end

    return require(script.Parent.notification).new(self, properties)
end

-- Notify, but silently no-ops if the same `key` fired within `cooldownSeconds` - a loop that
-- would otherwise flood identical toasts (a recurring error, a repeated warning every tick)
-- fires this once per cooldown window instead. `key` is any string the caller picks - unrelated
-- to the notification's own title, so callers control the dedup granularity themselves (e.g. one
-- key per error message, or one key shared across a whole feature). Returns nil (no
-- Notification object) when suppressed, the live Notification otherwise.
function Window:NotifyOnce(key, properties, cooldownSeconds)
    cooldownSeconds = cooldownSeconds or 5
    self._notifyOnceAt = self._notifyOnceAt or {}
    local now = os.clock()
    local last = self._notifyOnceAt[key]
    if last and (now - last) < cooldownSeconds then
        return nil
    end
    self._notifyOnceAt[key] = now
    return self:Notify(properties)
end

-- Consumer-facing debug logging, gated on the player's own "Debug Logging" Settings toggle (or
-- the F9 shortcut - see _bindKeybind) rather than always-on: a dev's script sprinkles DebugLog
-- calls through its own logic same as they would a print, and nothing shows up in anyone's
-- console until a player actually flips the switch to help reproduce a bug, tags every line so
-- multiple concurrent systems logging at once stay readable, and is deliberately separate from
-- this library's own internal `log` module (that one is Rayfield's own output, silenced under
-- secure mode; this one is the dev's, silenced by player opt-in instead).
function Window:DebugLog(tag, ...)
    if not self.settings.debugLogging then
        return
    end
    print(("[%s]"):format(tostring(tag)), ...)
end

-- Typed shortcuts onto Notify, matching Fluent's own NotifySuccess/NotifyWarning/NotifyInfo/
-- NotifyError shape (Title/Description/Time, all accepted as aliases already - see
-- notification.luau) - a preset icon + accentColor per type so a script switching from Fluent
-- can call these with the exact same properties table and get a sensibly-coloured result,
-- without hand-picking an icon/colour every call. Any of the presets are still overridable by
-- passing icon/accentColor explicitly - table.clone before mutating so the caller's own table
-- is never touched.
--
-- Icons use the "pack:icon-name" shorthand image.resolve() understands (see icons.luau/
-- image.luau) - each name below was live-verified against the actual Lucide pack data before
-- shipping (a past pack rename bit a few other icons this same session; see the icon-name
-- verification note in window.luau's Settings section for the method), so this doesn't repeat
-- the earlier resize.luau saga of guessing a bad-fitting rbxassetid.
local function typedNotify(self, properties, icon, color)
    properties = if typeof(properties) == "table" then table.clone(properties) else {}
    properties.icon = properties.icon or properties.Icon or icon
    properties.accentColor = properties.accentColor or properties.AccentColor or color
    return self:Notify(properties)
end

function Window:NotifySuccess(properties)
    return typedNotify(self, properties, "lucide:circle-check", constants.accent.on)
end

function Window:NotifyWarning(properties)
    return typedNotify(self, properties, "lucide:triangle-alert", Color3.fromRGB(235, 175, 55))
end

function Window:NotifyInfo(properties)
    return typedNotify(self, properties, "lucide:info", Color3.fromRGB(80, 150, 235))
end

function Window:NotifyError(properties)
    return typedNotify(self, properties, "lucide:circle-x", self.theme.ErrorColor)
end

-- Slides the top-centre toast stack clear of the collapsed pill (or back to its normal spot) -
-- call this wherever chrome.setCollapsedShown is, so the two always agree. No-op if no top
-- toast has ever fired (container built lazily by Toast itself).
function Window:_setTopToastPosition(animate)
    local container = self._toastsTop
    if not container then
        return
    end
    local target = if self.hidden then topToastClosedPosition else topToastOpenPosition
    if animate then
        variables.tweenService:Create(container, animate, { Position = target }):Play()
    else
        container.Position = target
    end
end

-- Top-centre / bottom-centre toast stack. Like Notify but for brief, centred messages that drop
-- in from the top (or rise from the bottom) of the screen (newest on top). Each toast takes
-- { title, subtitle?, icon?, duration?, position? }.
function Window:Toast(properties)
    if self.unloaded then
        return
    end

    local position = (properties or {}).position or "Top"
    local isTop = position == "Top"
    local containerKey = if isTop then "_toastsTop" else "_toastsBottom"
    local container = self[containerKey]

    if not container then
        container = self:Create("Frame", {
            Name = "Toasts",
            Size = UDim2.new(0, maxToastWidth, 1, -24),
            Position = if isTop
                then (if self.hidden then topToastClosedPosition else topToastOpenPosition)
                else UDim2.new(0.5, 0, 1, -12),
            AnchorPoint = if isTop then Vector2.new(0.5, 0) else Vector2.new(0.5, 1),
            BackgroundTransparency = 1,
            ZIndex = constants.zIndex.toast,

            Parent = self.screenGui,
        })

        self:Create("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            VerticalAlignment = if isTop then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
            -- gap lives inside each toast so removing one collapses its gap with it
            Padding = UDim.new(0, 0),

            Parent = container,
        })

        self[containerKey] = container
    end

    return require(script.Parent.toast).new(self, properties, container)
end

-- Centred modal over a dimmed backdrop. Takes { title, subtitle?, icon?, content?, boxes?,
-- options?, dismissable? } - give it options for a choice dialog, or boxes for a changelog.
-- Returns the popup handle (call :Close() to dismiss it yourself).
function Window:Popup(properties)
    if self.unloaded then
        return
    end
    return require(script.Parent.popup).new(self, properties)
end

local function keySystemFile(self)
    local dir = variables.fileSystemManager:getPath("KeySystem")
    return dir, path.join(dir, path.sanitizeFile(self.name) .. ".key")
end

-- A gate: nothing past this point runs until validator (or a plain key/list match) accepts
-- what's typed, or the dev's own Exit button fires. Not dismissable by backdrop-click or Escape
-- on purpose (see Popup's own dismissable property) - a gate that closes for free isn't one.
-- Built on Popup's input field (see popup.luau's own inputConfig comment) rather than a bespoke
-- screen, so it gets the same chrome/animations/theme everything else in the library already has.
--
-- saveKey persists an *accepted* key to disk (Rayfield/KeySystem/<window name>.key) so a
-- returning player isn't asked again - but it's re-checked against validator/key every launch
-- rather than trusted blindly, so a key that stops validating (rotated, revoked, expired) can't
-- let someone in forever just because it worked once.
function Window:KeySystem(properties)
    properties = if typeof(properties) == "table" then properties else {}

    local validator = properties.validator or properties.Validator
    local keyList = properties.key or properties.Key or properties.keys or properties.Keys
    local saveKey = properties.saveKey or properties.SaveKey
    local onSuccess = properties.onSuccess or properties.OnSuccess or function() end
    local onFailure = properties.onFailure or properties.OnFailure

    local function isValid(key)
        if type(key) ~= "string" or key == "" then
            return false
        end
        if validator then
            local ok, result = pcall(validator, key)
            return ok and result == true
        end
        if typeof(keyList) == "table" then
            return table.find(keyList, key) ~= nil
        end
        return keyList ~= nil and key == keyList
    end

    local keyDir, keyFile = keySystemFile(self)
    if saveKey and filesystem.isfile(keyFile) then
        local ok, saved = pcall(filesystem.readfile, keyFile)
        if ok and isValid(saved) then
            task.spawn(onSuccess)
            return
        end
    end

    self:Popup({
        title = properties.title or properties.Title or "Key Required",
        subtitle = properties.subtitle or properties.Subtitle,
        icon = properties.icon or properties.Icon,
        content = properties.note or properties.Note,
        dismissable = false,
        input = { placeholder = properties.placeholder or properties.Placeholder or "Enter key" },
        options = {
            {
                text = properties.exitText or properties.ExitText or "Exit",
                style = "neutral",
                callback = function()
                    if onFailure then
                        onFailure()
                    end
                end,
            },
            {
                text = properties.submitText or properties.SubmitText or "Submit",
                style = "primary",
                callback = function(key)
                    if not isValid(key) then
                        return false -- rejected: Popup keeps the gate open and flashes the field
                    end
                    if saveKey then
                        pcall(filesystem.ensureFolder, keyDir)
                        pcall(filesystem.writefile, keyFile, key)
                    end
                    onSuccess()
                    return true
                end,
            },
        },
    })
end

local greetingFadeInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- A white overlay, matching the window's own rounded corners, that cycles a short greeting in
-- each of `texts` and then sweeps away in a curved (circular) wipe to reveal the menu - the
-- overlay shrinks toward its centre while its own corner radius grows to fully round at the same
-- time, so a plain rectangle becomes an iris closing rather than needing any actual masking.
-- Takes { texts = {"Hello", "Bonjour", ...}, holdTime?, wipeTime? }. Safe to call on demand (a
-- "Play greeting" button) as well as once on first show - re-entrant calls no-op while one's
-- already running rather than fighting it for the same overlay.
function Window:PlayGreeting(properties)
    if self.unloaded or self._greetingPlaying then
        return
    end
    properties = if typeof(properties) == "table" then properties else {}
    local texts = properties.texts or properties.Texts or { "Hello" }
    local holdTime = properties.holdTime or properties.HoldTime or 0.85
    local wipeTime = properties.wipeTime or properties.WipeTime or 0.7
    if #texts == 0 then
        return
    end
    self._greetingPlaying = true

    if not self._greetingOverlay then
        self._greetingOverlay = self:Create("Frame", {
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = Color3.fromRGB(255, 255, 255),
            BorderSizePixel = 0,
            ZIndex = constants.zIndex.greeting,

            Parent = self.main,
        })

        self._greetingCorner = self:Create("UICorner", {
            Parent = self._greetingOverlay,
        })

        self._greetingLabel = self:Create("TextLabel", {
            Size = UDim2.fromScale(0.85, 0.3),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 28,
            TextColor3 = Color3.fromRGB(20, 20, 20),
            TextTransparency = 1,
            FontFace = self.theme.TitleFont,
            -- ZIndexBehavior is Global, so this child doesn't inherit/get elevated by the
            -- overlay's own high ZIndex - without its own explicit bump above the overlay's,
            -- the overlay's opaque white background paints right over it (confirmed live: the
            -- whole thing just read as a blank white card, the text was there the whole time,
            -- just painted under its own background).
            ZIndex = constants.zIndex.greeting + 1,

            Parent = self._greetingOverlay,
        })
    end

    local overlay, corner, label = self._greetingOverlay, self._greetingCorner, self._greetingLabel
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0.5, 0.5)
    overlay.BackgroundTransparency = 0
    corner.CornerRadius = self.theme.CornerRoundness
    label.TextTransparency = 1
    overlay.Visible = true

    for i, text in texts do
        label.Text = locale.resolve(tostring(text))
        variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 0 }):Play()
        task.wait(holdTime)
        if i < #texts then
            variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 1 }):Play()
            task.wait(0.15)
        end
    end

    variables.tweenService:Create(label, greetingFadeInfo, { TextTransparency = 1 }):Play()
    local wipeInfo = TweenInfo.new(wipeTime, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut)
    variables.tweenService:Create(overlay, wipeInfo, { Size = UDim2.fromScale(0, 0) }):Play()
    variables.tweenService:Create(corner, wipeInfo, { CornerRadius = UDim.new(1, 0) }):Play()
    task.wait(wipeTime)

    overlay.Visible = false
    self._greetingPlaying = false
end

function Window:Hide()
    -- idempotent: a second Hide while collapsed would capture the pill spot as the
    -- restore position and teleport the window there on the next Show
    if self.animating or self.hidden then
        return
    end

    -- drop out of search first so we grow back into the normal tab view on next show. tabList
    -- stays hidden here since the collapse hides it anyway; Show re-enables it.
    if self._searching then
        search.close(self, { showTabs = false, jumpTo = self.selectedTab and self.selectedTab.tabPage })
    end

    self.animating = true
    self._revealing = true
    self.hidden = true
    self.collapsedInteract.Visible = false -- re-shown once the collapse settles, below

    -- main morphs straight into the collapsed pill rather than handing off to a separate
    -- instance - the resize grip is parented to main too, so without this it rides along and
    -- sits there over the "Tap to show" pill, live-caught as a stray corner glyph with nothing
    -- to resize while hidden.
    self.resize.grip.Visible = false

    -- closing while minimised closes properly rather than leaving a stale minimised state -
    -- Show always grows back to the full (non-minimised) layout, so the flag and icon need
    -- to agree with that
    if self.minimised then
        self.minimised = false
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.minimise) -- back to the minimise icon
    end

    -- remember where the window sat so Show grows it back to the same spot
    self._restorePosition = self.main.Position

    local home, size = self:_collapsedRect()

    -- named so the task.delay staging below can stay in lockstep with however long these
    -- actually run - slowed down from 0.18/0.35 (read as too fast, closing almost instantly)
    local fadeDuration, moveDuration = 0.26, 0.5
    local fadeInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    -- "Closing to the pill": one continuous move for the whole collapse, size and position
    -- tweening together on the same curve so they stay perfectly in sync, no seam between
    -- separate legs. Quint/Out (was Exponential/InOut) reads as the window getting sucked
    -- straight into the pill - fast off the mark, settling smoothly into place, rather than
    -- easing gently out of its starting size the way InOut does.
    local moveInfo = TweenInfo.new(moveDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local cornerInfo = TweenInfo.new(moveDuration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
    local faceInfo = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

    -- shrink the drag bar back down the same way it grows in on first reveal, instead of
    -- just cutting it
    variables.tweenService
        :Create(self.drag.dragCosmetic, fadeInfo, { Size = UDim2.fromOffset(0, 4), BackgroundTransparency = 1 })
        :Play()
    task.delay(fadeDuration, function()
        if not self.hidden then
            return
        end
        self.drag.drag.Visible = false
    end)

    -- fade the window's own chrome out; main keeps its own background/gradient/corner the
    -- whole time, it just reshapes underneath - there's nothing to hand off to
    variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 1 }):Play()
    variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 1 }):Play()
    variables.tweenService:Create(self.topFade, fadeInfo, { BackgroundTransparency = 1 }):Play()

    if self.title then
        variables.tweenService:Create(self.title, fadeInfo, { TextTransparency = 1 }):Play()
    end
    if self.subtitle then
        variables.tweenService:Create(self.subtitle, fadeInfo, { TextTransparency = 1 }):Play()
    end
    if self.topbarIcon then
        variables.tweenService:Create(self.topbarIcon, fadeInfo, { ImageTransparency = 1 }):Play()
    end

    for _, action in ipairs(self.actionContainer:GetChildren()) do
        if action:IsA("Frame") then
            variables.tweenService:Create(action.ImageLabel, fadeInfo, { ImageTransparency = 1 }):Play()
        end
    end

    for _, tag in self.tags do
        tag:_setShown(false, fadeInfo)
    end

    for _, tab in pairs(self.tabs) do
        if not tab.neglectSelector and tab.topbarItem then
            tab:_applyVisual("hidden", fadeInfo)
        end
    end
    self:_setTabSectionsShown(false, fadeInfo)

    self:_fadeSelectedElementsOut()

    -- collapse into the pill in one continuous move - size and position tweened together
    -- so they stay perfectly in sync throughout
    variables.tweenService:Create(self.main, moveInfo, { Size = size, Position = home }):Play()
    -- squircle mode has no windowCorner to round into the pill's fully-round corner - the
    -- squircle shape just stays at its own normal radius while collapsed (a known, disclosed
    -- gap: the pill-collapse animation isn't squircle-aware yet - would need the separate
    -- Circle asset squircle.luau doesn't carry, since a squircle can't itself express a true
    -- fully-round pill the way UDim.new(1,0) on a plain UICorner can).
    if self.windowCorner then
        variables.tweenService:Create(self.windowCorner, cornerInfo, { CornerRadius = UDim.new(1, 0) }):Play()
    end

    -- once the chrome's faded, drop it and the scrolling content so nothing squashes/pokes
    -- out as the frame shrinks around it, then bring the collapsed face up over the top
    task.delay(fadeDuration, function()
        if not self.hidden then
            return
        end
        self.topbar.Visible = false
        self.elements.Visible = false
        self.tabList.Visible = false
        self.tabDock.Visible = false
        -- the profile chip hangs off main, not tabDock (see its own construction comment), so
        -- hiding the dock doesn't take it with it
        if self.profile then
            self.profile.Visible = false
        end
        self:_setTabSectionsVisible(false)
        chrome.setCollapsedShown(self, true, faceInfo)
        self:_setTopToastPosition(faceInfo)
    end)

    -- once the move's settled the pill is done morphing: hand clicks to it
    task.delay(moveDuration, function()
        if not self.hidden then
            return
        end
        self.collapsedInteract.Visible = true
        self.animating = false
        self._revealing = false
    end)
end

function Window:ToggleHide()
    if self.animating then
        return
    end
    if self.hidden then
        self:Show()
    else
        self:Hide()
    end
end

function Window:ToggleMinimise()
    if self.animating or self.hidden then
        return
    end

    -- minimising drops out of search back to the tab view first, so it grows back normally
    if self._searching then
        search.close(self, { showTabs = true })
    end

    self.animating = true

    local sizeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
    local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

    if self.minimised then
        self.minimised = false
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.minimise) -- back to the minimise icon

        variables.tweenService:Create(self.main, sizeInfo, { Size = self.size }):Play()
        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = self._shadowTransparency or 0.6 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 0 }):Play()
        variables.tweenService:Create(self.topFade, fadeInfo, { BackgroundTransparency = 0 }):Play()

        variables.tweenService
            :Create(self.drag.drag, sizeInfo, {
                Position = UDim2.new(
                    self.main.Position.X.Scale,
                    self.main.Position.X.Offset,
                    self.main.Position.Y.Scale,
                    self.main.Position.Y.Offset + self.size.Y.Offset / 2 + 15
                ),
            })
            :Play()

        -- once the window's grown back, fade the content and tab pills in rather than
        -- snapping them visible
        task.delay(0.2, function()
            if self.minimised or self.hidden then
                return -- re-minimised or hidden mid animation
            end
            self.elements.Visible = true
            self.tabList.Visible = true
            self.tabDock.Visible = true
            self.resize.grip.Visible = self.settings.resizeGripEnabled
            if self.profile then
                self.profile.Visible = self.settings.showProfile
                self.tabList.Size =
                    UDim2.new(1, 0, 1, if self.settings.showProfile then -self._tabListFooterReserve else 0)
            end
            for _, tab in pairs(self.tabs) do
                if not tab.neglectSelector and tab.topbarItem then
                    tab.topbarItem.Visible = true
                    tab:_applyVisual(if self.selectedTab == tab then "selected" else "unselected", fadeInfo)
                end
            end
            self:_setTabSectionsVisible(true)
            self:_setTabSectionsShown(true, fadeInfo)

            self:_revealElements(0.035, 0.4)
        end)

        task.delay(0.5, function()
            self.animating = false
        end)
    else
        self.minimised = true
        image.assign(self.minimiseAction.iconLabel, "Image", constants.icons.maximise) -- maximise icon while minimised

        -- fade the content + tab pills out instead of cutting them, then hide them once faded
        -- so they don't sit clipped under the collapsed bar
        self:_fadeSelectedElementsOut()
        for _, tab in pairs(self.tabs) do
            if not tab.neglectSelector and tab.topbarItem then
                tab:_applyVisual("hidden", fadeInfo)
            end
        end
        self:_setTabSectionsShown(false, fadeInfo)

        task.delay(0.3, function()
            if not self.minimised then
                return -- restored mid animation
            end
            self.elements.Visible = false
            self.tabList.Visible = false
            self.tabDock.Visible = false
            -- same story as Hide's own: the profile chip is parented to main, so it needs
            -- hiding by hand alongside the dock
            if self.profile then
                self.profile.Visible = false
            end
            self:_setTabSectionsVisible(false)
            -- a collapsed bar isn't something you'd resize, and the grip would otherwise sit
            -- oversized on its now much shorter (66px) height
            self.resize.grip.Visible = false
            for _, tab in pairs(self.tabs) do
                if not tab.neglectSelector and tab.topbarItem then
                    tab.topbarItem.Visible = false
                end
            end
        end)

        variables.tweenService:Create(self.windowShadow, fadeInfo, { Transparency = 1 }):Play()
        variables.tweenService:Create(self.bottomFade, fadeInfo, { BackgroundTransparency = 1 }):Play()
        variables.tweenService:Create(self.topFade, fadeInfo, { BackgroundTransparency = 1 }):Play()
        variables.tweenService:Create(self.main, sizeInfo, { Size = UDim2.fromOffset(self.size.X.Offset, 66) }):Play()

        variables.tweenService
            :Create(self.drag.drag, sizeInfo, {
                Position = UDim2.new(
                    self.main.Position.X.Scale,
                    self.main.Position.X.Offset,
                    self.main.Position.Y.Scale,
                    self.main.Position.Y.Offset + 66 / 2 + 15
                ),
            })
            :Play()

        task.delay(0.5, function()
            self.animating = false
        end)
    end
end

-- Park the drag bar under the window's bottom edge, matching whichever positioning the window
-- itself uses so a centred window stays centred and a dragged one stays where it was left.
function Window:_syncDragBar()
    local bar = self.drag and self.drag.drag
    if not bar then
        return
    end
    local position = self.main.Position
    local below = self.size.Y.Offset / 2 + 15
    bar.Position = UDim2.new(position.X.Scale, position.X.Offset, position.Y.Scale, position.Y.Offset + below)
end

-- Pull a dragged window back on screen after a re-fit, the same way a drag clamps. A window
-- parked near an edge would otherwise end up half off it when the viewport shrinks underneath.
-- Where a position ends up once the current size has to fit on the current screen. Returns it
-- unchanged when theres nothing to do, so callers can compare.
function Window:_clampedPosition(position: UDim2): UDim2
    if not self.settings or not self.settings.keepOnScreen then
        return position
    end
    -- untouched windows sit on scale and are centred, so theyre on screen by construction -
    -- clamping would only freeze them to offsets and stop them recentring later
    if position.X.Scale ~= 0 or position.Y.Scale ~= 0 then
        return position
    end

    local screen = self.screenGui.AbsoluteSize
    local halfX, halfY = self.size.X.Offset / 2, self.size.Y.Offset / 2
    local margin = 8
    -- math.max in case the window is bigger than the screen
    local x = math.clamp(position.X.Offset, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
    local y = math.clamp(position.Y.Offset, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
    if x == position.X.Offset and y == position.Y.Offset then
        return position
    end
    return UDim2.fromOffset(x, y)
end

function Window:_clampToScreen()
    self.main.Position = self:_clampedPosition(self.main.Position)
end

-- Take the size the current screen calls for. Only a live window is resized on the spot;
-- hidden, minimised or mid-animation ones just bank the size and pick it up on their next
-- show, so a rotation cant yank a collapsed pill back open.
function Window:_applyWindowSize()
    if self.unloaded then
        return
    end

    local size = fitWindowSize(self.customSize)
    local changed = size ~= self.size
    self.size = size

    -- a window mid-animation is already tweening toward the old size, so bank the change and
    -- let the reconcile apply it once the tween is done rather than fighting it
    if self.hidden or self.minimised or self.animating or self._revealing then
        self._pendingResize = self._pendingResize or changed
        return
    end

    if not changed and not self._pendingResize then
        return
    end
    self._pendingResize = false

    self.main.Size = size
    self:_clampToScreen()
    self:_syncDragBar()
end

-- Follow the screen. The property signal is the fast path, but CurrentCamera gets swapped
-- (respawn, or a game replacing it) and a listener bound to the old camera dies silently, so
-- rebind on the swap and keep a slow reconcile behind it as the backstop.
function Window:_watchViewport()
    local cameraConnection: RBXScriptConnection? = nil
    local pending = false

    local function request()
        -- a rotation fires a burst of intermediate sizes, so settle on the last one
        if pending then
            return
        end
        pending = true
        task.defer(function()
            pending = false
            self:_applyWindowSize()
        end)
    end

    local function bind()
        if cameraConnection then
            self:Disconnect(cameraConnection)
            cameraConnection = nil
        end
        local camera = variables.workspace.CurrentCamera
        if camera then
            cameraConnection = self:Connect(camera:GetPropertyChangedSignal("ViewportSize"), request)
        end
        request()
    end

    self:Connect(variables.workspace:GetPropertyChangedSignal("CurrentCamera"), bind)
    bind()

    -- Backstop for anything the signals miss. Heartbeat rather than a wait loop so it rides the
    -- normal connection cleanup and cant spin if the scheduler hands back a wait that never yields.
    local sinceReconcile = 0
    self:Connect(variables.runService.Heartbeat, function(delta: number)
        sinceReconcile += delta
        if sinceReconcile < viewportReconcileInterval then
            return
        end
        sinceReconcile = 0
        self:_applyWindowSize()
    end)
end

function Window:_bindKeybind()
    self:Connect(variables.userInputService.InputBegan, function(input, processed)
        if processed or self._recordingKeybind then
            return -- a keybind element is mid-rebind, dont eat its capture
        end
        if input.KeyCode == self.settings.toggleKeybind or input.UserInputType == self.settings.toggleKeybind then
            -- Live-caught: the default toggle key is plain K, and Ctrl+K (below) is a *different*
            -- shortcut - but InputBegan fires on the K keydown regardless of what else is held,
            -- so pressing Ctrl+K matched here too and closed the window in the same beat the
            -- search shortcut was trying to open it, netting "nothing happened but the menu
            -- closed". Skip the plain-toggle match while Ctrl is held, unless the toggle key
            -- itself *is* Ctrl (a player could rebind it to that) - only guard against a
            -- modifier stealing a *different* key's plain binding, not break a deliberate one.
            local uis = variables.userInputService
            local ctrlHeld = uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)
            local toggleIsCtrl = self.settings.toggleKeybind == Enum.KeyCode.LeftControl
                or self.settings.toggleKeybind == Enum.KeyCode.RightControl
            if not (ctrlHeld and not toggleIsCtrl) then
                self:ToggleHide()
            end
        end
    end)

    -- Ctrl+K: the same "search all pages" the topbar's own Search action already opens/closes
    -- (search.toggle) - just a keyboard shortcut onto a feature that already existed, not a new
    -- search system. Fixed to Ctrl+K rather than reading a configurable setting the way the menu
    -- toggle key does - this is meant to be the one predictable shortcut every window shares
    -- (the same convention a browser's or VS Code's own Ctrl+K carries), not something a dev or
    -- player would want to rebind per window.
    self:Connect(variables.userInputService.InputBegan, function(input, processed)
        if processed or self._recordingKeybind then
            return
        end
        if input.KeyCode ~= Enum.KeyCode.K then
            return
        end
        local uis = variables.userInputService
        if not (uis:IsKeyDown(Enum.KeyCode.LeftControl) or uis:IsKeyDown(Enum.KeyCode.RightControl)) then
            return
        end
        if self.minimised or not self:_interactive() then
            return
        end
        search.toggle(self)
    end)

    -- Escape: closes search first if it's open (backs out one level, the same convention most
    -- apps use for Escape), otherwise closes the window - only when the dev opted in via
    -- escapeToClose (see its own comment on why this is dev-set, not a player Settings toggle).
    self:Connect(variables.userInputService.InputBegan, function(input, processed)
        if processed or self._recordingKeybind then
            return
        end
        if input.KeyCode ~= Enum.KeyCode.Escape then
            return
        end
        if self.minimised or not self:_interactive() then
            return
        end
        if self._searching then
            search.close(self, { showTabs = true })
            return
        end
        if self.escapeToClose and not self.hidden then
            self:Hide()
        end
    end)

    -- F9: flips debug logging on/off from anywhere, not just the Settings toggle - the point is
    -- a player can turn it on the moment a bug happens without hunting through menus first, then
    -- reproduce it and hand the dev script's own console output (see DebugLog below) straight
    -- over. Fixed to F9 for the same reason Ctrl+K is fixed above: one shortcut every window
    -- shares, not a per-player rebind.
    self:Connect(variables.userInputService.InputBegan, function(input, processed)
        if processed or self._recordingKeybind then
            return
        end
        if input.KeyCode ~= Enum.KeyCode.F9 then
            return
        end
        self.settings.debugLogging = not self.settings.debugLogging
        self:SaveSettings()
        if self._debugLoggingToggleControl then
            self._debugLoggingToggleControl:Set(self.settings.debugLogging, true)
        end
        self:Toast({
            title = locale.resolve(if self.settings.debugLogging then "Debug logging on" else "Debug logging off"),
            icon = "lucide:bug",
        })
    end)
end

function Window:_bindMouseOverride()
    local uis = variables.userInputService

    local function active()
        return self.settings.mouseOverride and not self.hidden and not self.minimised
    end

    local function free()
        if not active() then
            return
        end
        -- hands off while the right button is held: thats the camera panning in third person,
        -- and it needs to lock the mouse to do it. we free again the moment it lets go.
        if uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
            return
        end
        if uis.MouseBehavior ~= Enum.MouseBehavior.Default then
            uis.MouseBehavior = Enum.MouseBehavior.Default
        end
        if not uis.MouseIconEnabled then
            uis.MouseIconEnabled = true
        end
    end

    -- react to the game re-locking instead of racing it each frame. it sets LockCenter, we set
    -- it back, so we always get the last word. same deal if it hides the mouse icon.
    self:Connect(uis:GetPropertyChangedSignal("MouseBehavior"), free)
    self:Connect(uis:GetPropertyChangedSignal("MouseIconEnabled"), free)

    -- right-release doesnt always flip MouseBehavior back (so the signals above wouldnt fire),
    -- so re-free explicitly once the pan ends
    self:Connect(uis.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton2 then
            free()
        end
    end)

    -- Show calls this on open to free the cursor immediately (the signals above only fire on change)
    self._freeMouse = free
end

-- Grabbing the topbar drags the whole window too, its own separate handle from the bar
-- underneath - tracks the cursor 1:1 with no lag, unlike the bars own deliberate smoothing, and
-- the bar just glues to wherever main currently is each frame so it never drifts off on its own
function Window:_bindTopbarDrag()
    local uis = variables.userInputService
    local dragging = false
    local relative = Vector2.zero

    -- main.Position lives in a space shifted from AbsolutePosition by the gui inset, even
    -- though the ScreenGui ignores it - add it back or the window jumps on the first move
    local offset = Vector2.zero
    if self.screenGui and self.screenGui.IgnoreGuiInset then
        offset = variables.guiService:GetGuiInset()
    end

    local function getTarget()
        local position = uis:GetMouseLocation() + relative + offset
        local x, y = position.X, position.Y

        if self.settings and self.settings.keepOnScreen then
            local size = self.main.AbsoluteSize
            local screen = self.screenGui.AbsoluteSize
            local margin = 8
            local halfX, halfY = size.X / 2, size.Y / 2
            x = math.clamp(x, halfX + margin, math.max(halfX + margin, screen.X - halfX - margin))
            y = math.clamp(y, halfY + margin, math.max(halfY + margin, screen.Y - halfY - margin))
        end

        return UDim2.fromOffset(x, y)
    end

    -- Global ZIndexBehavior still delivers InputBegan to an Active ancestor even when a child
    -- button covers that exact pixel, so checking the event alone isnt enough - a press over the
    -- tabs or the actions has to be rejected by where it actually landed, not just left to bubble
    local function overInteractiveChild(x, y)
        for _, region in { self.tabList, self.actionContainer } do
            local position, size = region.AbsolutePosition, region.AbsoluteSize
            if x >= position.X and x <= position.X + size.X and y >= position.Y and y <= position.Y + size.Y then
                return true
            end
        end
        return false
    end

    self:Connect(self.topbar.InputBegan, function(input, processed)
        if processed then
            return
        end

        local inputType = input.UserInputType.Name
        if inputType ~= "MouseButton1" and inputType ~= "Touch" then
            return
        end

        if overInteractiveChild(input.Position.X, input.Position.Y) then
            return
        end

        -- a grab started mid-reveal would fight the tween thats still moving the window
        if not self:_interactive() then
            return
        end

        dragging = true

        if self.screenGui and self.screenGui.IgnoreGuiInset then
            offset = variables.guiService:GetGuiInset()
        end

        relative = self.main.AbsolutePosition + self.main.AbsoluteSize * self.main.AnchorPoint - uis:GetMouseLocation()
    end)

    self:Connect(uis.InputEnded, function(input)
        local inputType = input.UserInputType.Name
        if inputType == "MouseButton1" or inputType == "Touch" then
            dragging = false
        end
    end)

    -- alt-tabbing with the button still down never delivers InputEnded, so without this the
    -- grab stays armed and the window snaps to the cursor the moment youre back
    self:Connect(uis.WindowFocusReleased, function()
        dragging = false
    end)

    self:Connect(variables.runService.RenderStepped, function()
        if not dragging then
            return
        end

        -- hidden or mid-animation means the grab went stale under us, so drop it here rather
        -- than let it wake up later and yank the window to wherever the cursor drifted
        if not self:_interactive() then
            dragging = false
            return
        end

        self.main.Position = getTarget()

        if self.drag and self.drag.drag then
            local mainPosition = self.main.Position
            self.drag.drag.Position = UDim2.new(
                mainPosition.X.Scale,
                mainPosition.X.Offset,
                mainPosition.Y.Scale,
                mainPosition.Y.Offset + (self.main.Size.Y.Offset / 2 + 15)
            )
        end
    end)
end

-- Programmatic equivalent of the Settings "Haptics" toggle - for a hub that hides that toggle
-- (showHapticsToggle = false) but still wants to pin the value one way or the other, since
-- hapticEngine keeps its own enabled flag separate from self.settings.haptics (only synced at
-- construction and from the toggle's own callback otherwise).
function Window:SetHaptics(enabled)
    enabled = enabled == true
    self.settings.haptics = enabled
    hapticEngine.setEnabled(enabled)
    self:SaveSettings()
end

function Window:_buildSettingsUI()
    self.rfSettings:CreateSection({ name = "General" })

    self.rfSettings:CreateKeybind({
        name = "Toggle Keybind",
        -- was constants.icons.search - a leftover mismatch (a magnifying glass for a keybind
        -- setting), fixed to an icon that actually matches what this does.
        icon = "lucide:keyboard",
        value = self.settings.toggleKeybind,
        isMenuToggle = true, -- reject keys already owned by an element keybind
        onChanged = function(key)
            self.settings.toggleKeybind = key
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Unlock cursor while open",
        icon = "lucide:mouse-pointer-2",
        description = "Unlocks the cursor while the menu is open so you can configure in FPS games that lock it.",
        value = self.settings.mouseOverride,
        callback = function(state)
            self.settings.mouseOverride = state
            self:SaveSettings()
        end,
    })

    if self._showWelcomeToastToggle then
        self.rfSettings:CreateToggle({
            name = "Welcome toast",
            icon = "lucide:hand",
            description = "Shows a 'Signed in as' toast the first time you open the menu on a new account.",
            value = self.settings.welcomeToast,
            callback = function(state)
                self.settings.welcomeToast = state
                self:SaveSettings()
            end,
        })
    end

    if self._showHapticsToggle then
        self.rfSettings:CreateToggle({
            name = "Haptics",
            icon = "lucide:vibrate",
            description = "A subtle tap as you interact, on devices that support haptics.",
            value = self.settings.haptics,
            callback = function(state)
                self:SetHaptics(state)
            end,
        })
    end

    if self._showSoundEffectsToggle then
        self.rfSettings:CreateToggle({
            name = "Sound Effects",
            icon = "lucide:volume-2",
            description = "A soft click as you interact with toggles, buttons, and tabs.",
            value = self.settings.soundEffects,
            callback = function(state)
                self.settings.soundEffects = state
                soundEngine.setEnabled(state)
                self:SaveSettings()
            end,
        })
    end

    -- Debug Logging: gates Window:DebugLog (see its own comment) - off by default, a player
    -- flips it (or presses F9, same effect - see _bindKeybind) only when a dev asks them to
    -- reproduce a bug with it on. Captured into self._debugLoggingToggleControl so the F9
    -- shortcut can push its own toggles back into this control without it drifting out of sync.
    self._debugLoggingToggleControl = self.rfSettings:CreateToggle({
        name = "Debug Logging (F9)",
        icon = "lucide:bug",
        description = "Prints extra diagnostic output to the console - turn this on if a dev asked you to reproduce a bug.",
        value = self.settings.debugLogging,
        callback = function(state)
            self.settings.debugLogging = state
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateSection({ name = "Appearance" })

    -- "Amber" is the one preset name that doesn't match its theme file 1:1 (ember.luau) - every
    -- other option here is both the picker label and the real theme name, case-insensitively.
    local themeFileFor = { Amber = "ember", ["High Contrast"] = "highcontrast" }

    self.rfSettings:CreateDropdown({
        name = "Color theme",
        icon = "lucide:palette",
        options = {
            "Default",
            "Ocean",
            "Amber",
            "Rose",
            "Emerald",
            "Amethyst",
            "Midnight",
            "High Contrast",
        },
        value = "Default",
        callback = function(value)
            self:ChangeTheme(themeFileFor[value] or value)
        end,
    })

    self.rfSettings:CreateDropdown({
        name = "Font",
        icon = "lucide:type",
        placeholder = "Search fonts...",
        options = fontOptionNames,
        value = "Auto",
        callback = function(value)
            self:SetFont(value)
        end,
    })

    -- Player-facing language for the library's own chrome (search, config messages, keybind
    -- clash toasts, and so on - see builtinLocales.luau's own header comment on exactly what's
    -- covered and what isn't). Not element names a dev supplies - those were never routed
    -- through locale.t() to begin with, so switching this doesn't touch them.
    do
        local languageNameFor = { en = "English", pt = "Português", es = "Español" }
        local languageIdFor = { English = "en", ["Português"] = "pt", ["Español"] = "es" }
        local currentLanguage = string.match(locale.current, "^(%a+)") or "en"

        self.rfSettings:CreateDropdown({
            name = "Language",
            icon = "lucide:languages",
            options = { "English", "Português", "Español" },
            value = languageNameFor[currentLanguage] or "English",
            callback = function(value)
                self:SetLocale(languageIdFor[value] or "en")
            end,
        })
    end

    self.rfSettings:CreateSlider({
        name = "Window transparency",
        icon = "lucide:layers",
        range = { 0, 100 },
        value = 0,
        suffix = "%",
        callback = function(value)
            self:SetTransparency(value)
        end,
    })

    -- Kept to 85-115 rather than a wider range on purpose - see self.contentScale's own
    -- construction comment on why an extreme scale isn't safe to let the content area reach
    -- (main has no ClipsDescendants, deliberately, for the resize grip's sake).
    self.rfSettings:CreateSlider({
        name = "UI Scale",
        icon = "lucide:scale",
        range = { 85, 115 },
        value = self.settings.uiScale,
        suffix = "%",
        callback = function(value)
            self.settings.uiScale = value
            self.contentScale.Scale = value / 100
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateToggle({
        name = "Acrylic blur",
        icon = "lucide:droplet",
        description = "Frost the game behind a see-through window.",
        value = false,
        callback = function(value)
            self:SetAcrylic(value)
        end,
    })

    self.rfSettings:CreateSection({ name = "Window" })

    self.rfSettings:CreateToggle({
        name = "Keep window on screen",
        icon = "lucide:pin",
        description = "Stops the window being dragged off the edge of the screen and lost.",
        value = self.settings.keepOnScreen,
        callback = function(state)
            self.settings.keepOnScreen = state
            self:SaveSettings()
        end,
    })

    -- Only shown when the dev actually configured a loading splash (self.loading) AND hasn't
    -- pinned it via _showLoadingAnimationToggle - otherwise there's nothing for this to turn on
    -- or off, or the dev wants it always on with no player override.
    if self.loading and self._showLoadingAnimationToggle then
        self.rfSettings:CreateToggle({
            name = "Loading Animation",
            icon = "lucide:sparkles",
            description = "Shows a brief splash the first time the window opens.",
            value = self.settings.loadingAnimationEnabled,
            callback = function(state)
                self.settings.loadingAnimationEnabled = state
                self:SaveSettings()
            end,
        })
    end

    -- Same conditional-on-the-dev-opting-in shape as Loading Animation above - only shown at
    -- all if there's actually a tour configured to replay.
    if self.tourSteps then
        self.rfSettings:CreateButton({
            name = "Replay Tour",
            icon = "lucide:compass",
            description = "Show the guided tour again.",
            callback = function()
                self:StartTour()
            end,
        })
    end

    self.rfSettings:CreateToggle({
        name = "Resizable window",
        icon = "lucide:expand",
        description = "Shows a grip in the bottom-right corner that drags the window's size.",
        value = self.settings.resizeGripEnabled,
        callback = function(state)
            self.settings.resizeGripEnabled = state
            self.resize:SetEnabled(state)
            self:SaveSettings()
        end,
    })

    self.rfSettings:CreateButton({
        name = "Reset Window Size",
        icon = "lucide:maximize",
        callback = function()
            self.resize:ResetSize()
        end,
    })

    self.rfSettings:CreateButton({
        name = "Reset Window Position",
        icon = "lucide:move",
        callback = function()
            variables.tweenService
                :Create(self.main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                })
                :Play()
            variables.tweenService
                :Create(self.drag.drag, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
                    Position = UDim2.new(0.5, 0, 0.5, self.size.Y.Offset / 2 + 15),
                })
                :Play()
        end,
    })

    -- Only the sidebar layout has somewhere to put a profile chip, and only once it actually
    -- built one (a real LocalPlayer to build it for - see window.luau's own profile block).
    -- Ported from upstream Rayfield Gen2 1.2.
    if self.profile then
        self.rfSettings:CreateToggle({
            name = "Show profile",
            icon = "lucide:user",
            description = "Shows your avatar and name at the base of the sidebar.",
            value = self.settings.showProfile,
            callback = function(state)
                self.settings.showProfile = state
                self.profile.Visible = state
                -- Give the rows back the height the profile isn't using (and vice versa), so a
                -- hidden profile leaves no dead strip at the base of the rail.
                self.tabList.Size = UDim2.new(1, 0, 1, if state then -self._tabListFooterReserve else 0)
                self:SaveSettings()
            end,
        })
    end

    -- Configurations: save the current setup under a name and switch between saved ones.
    -- Only shown once the developer opts into config saving.
    if next(self.configuration) ~= nil then
        self.rfSettings:CreateSection({ name = "Configurations" })

        local selected = self:ListConfigs()[1]
        local configDropdown, nameInput, autoTargetLabel

        local function autoTargetText()
            if selected and selected ~= "" then
                return locale.resolve("Applies to") .. ": " .. selected
            end
            return locale.resolve("Applies to: no configuration selected")
        end

        -- Persist which configuration is "selected" here across restarts - same
        -- Window:RegisterFlag pattern the hub template's own sidebar width/HUD position use for a
        -- plain value with no visible control of its own (see its doc comment). Window:_persist
        -- reads self._selectedConfigName to know which file Auto Save Config should target, and
        -- the Auto Load Config button below reads plain `selected` to know what to commit - both
        -- point at this exact same selection, which is also what autoTargetLabel below exists to
        -- make visible next to them.
        local selectedFlag = self:RegisterFlag("_SelectedConfig", selected, function(name)
            selected = name
            self._selectedConfigName = name
            if configDropdown and name and configDropdown.value ~= name then
                configDropdown:Set(name, true)
            end
            if autoTargetLabel then
                autoTargetLabel:Set(autoTargetText())
            end
        end)
        self._selectedConfigName = selected

        -- Auto Save Config: when on, Window:_persist also re-saves straight into whichever
        -- configuration is currently selected (self._autoSaveConfigEnabled, checked there) any
        -- time a registered control changes - not just the single default file
        -- `configuration.autoSave` already keeps current, so switching to "PvP Loadout" and
        -- tweaking a slider keeps "PvP Loadout" itself up to date without a manual Save click.
        local autoSaveConfigFlag = self:RegisterFlag("_AutoSaveConfig", false, function(value)
            self._autoSaveConfigEnabled = value
        end)
        self._autoSaveConfigEnabled = autoSaveConfigFlag.value

        local function refreshConfigs()
            local names = self:ListConfigs()
            configDropdown:Refresh(names)
            if selected and not table.find(names, selected) then
                selected = names[1]
            end
            if selected then
                selectedFlag:Set(selected)
            end
        end

        configDropdown = self.rfSettings:CreateDropdown({
            name = "Saved Configurations",
            icon = constants.icons.config,
            options = self:ListConfigs(),
            value = selected,
            placeholder = "No saved configurations",
            callback = function(value)
                selectedFlag:Set(value)
            end,
        })

        nameInput = self.rfSettings:CreateInput({
            name = "Configuration Name",
            icon = "lucide:tag",
            description = "Name a new configuration, or leave blank to overwrite the selected one.",
            placeholder = "e.g. PvP Loadout",
            clearOnFocus = false,
        })

        local actions = self.rfSettings:CreateGroup()

        actions:CreateButton({
            name = "Save",
            icon = "lucide:save",
            callback = function()
                local name = nameInput.value
                if name == "" then
                    name = selected
                end
                if not name or name == "" then
                    self:Toast({ title = locale.resolve("Name your configuration first") })
                    return
                end
                if self:Save(name) then
                    nameInput:Set("")
                    selectedFlag:Set(name)
                    refreshConfigs()
                    self:Toast({
                        title = locale.resolve("Saved configuration"),
                        subtitle = name,
                        icon = constants.icons.config,
                    })
                else
                    self:Toast({ title = locale.resolve("Couldn't save configuration"), subtitle = name })
                end
            end,
        })

        actions:CreateButton({
            name = "Load",
            icon = "lucide:folder-open",
            callback = function()
                if not selected or selected == "" then
                    self:Toast({ title = locale.resolve("Pick a configuration to load") })
                    return
                end
                if self:_applyNamedConfig(selected) then
                    self:Toast({ title = locale.resolve("Loaded configuration"), subtitle = selected })
                else
                    self:Toast({ title = locale.resolve("Couldn't load configuration"), subtitle = selected })
                end
            end,
        })

        actions:CreateButton({
            name = "Delete",
            icon = "lucide:trash-2",
            callback = function()
                local deleting = selected
                if not deleting or deleting == "" then
                    self:Toast({ title = locale.resolve("Pick a configuration to delete") })
                    return
                end
                if self:DeleteConfig(deleting) then
                    refreshConfigs()
                    self:Toast({ title = locale.resolve("Deleted configuration"), subtitle = deleting })
                else
                    self:Toast({ title = locale.resolve("Couldn't delete configuration"), subtitle = deleting })
                end
            end,
        })

        -- Clipboard export/import: a text-based sibling to the file-based Save/Load/Delete above,
        -- for sharing a config outside the executor's own file system (Discord, a text box, a
        -- config a friend sends over). Import pastes into an ordinary input rather than reading
        -- the clipboard directly - see ImportConfig's own comment for why.
        actions:CreateButton({
            name = "Export",
            icon = "lucide:share-2",
            callback = function()
                local ok, encoded = self:ExportConfig()
                if ok then
                    self:Toast({
                        title = locale.resolve("Configuration copied"),
                        subtitle = locale.resolve("Paste it anywhere to share it"),
                        icon = constants.icons.config,
                    })
                else
                    self:Toast({ title = locale.resolve("Couldn't export configuration") })
                end
            end,
        })

        local importInput = self.rfSettings:CreateInput({
            name = "Import Configuration",
            icon = "lucide:clipboard",
            description = "Paste a configuration string here, then Import.",
            placeholder = "Paste here...",
            clearOnFocus = false,
        })

        actions:CreateButton({
            name = "Import",
            icon = "lucide:clipboard-paste",
            callback = function()
                local raw = importInput.value
                if raw == "" then
                    self:Toast({ title = locale.resolve("Paste a configuration first") })
                    return
                end
                if self:ImportConfig(raw) then
                    importInput:Set("")
                    self:Save()
                    refreshConfigs()
                    self:Toast({ title = locale.resolve("Imported configuration") })
                else
                    self:Toast({ title = locale.resolve("That doesn't look like a valid configuration") })
                end
            end,
        })

        -- Both controls below only ever act on whatever's picked in "Saved Configurations" above -
        -- easy to lose track of once you've scrolled past it, so this stays in view right next to
        -- them and updates live off the same selectedFlag everything else here reads.
        autoTargetLabel = self.rfSettings:CreateLabel({
            text = autoTargetText(),
            icon = constants.icons.config,
        })

        -- A row Group (its default direction) sits the button and toggle side by side instead of
        -- each taking the full row - see group.luau's own compactCapable table for why Button/
        -- Toggle can do this and most other element types can't.
        local autoGroup = self.rfSettings:CreateGroup()

        -- A one-shot action rather than a toggle: press it once, with the configuration you want
        -- selected above, and *that* becomes what this script opens with from here on - not a
        -- live on/off state that would otherwise keep re-pointing itself at whatever you're just
        -- browsing to in the dropdown above (live-reported: switching configs while this was a
        -- toggle silently changed what would auto-load, with no separate action to "commit" one).
        -- Same underlying call as Window:SetAutoloadConfig/the Load button above - loads it live
        -- immediately too, and that's what makes the default file (what plain autoLoad restores
        -- next session) reflect it from here on.
        autoGroup:CreateButton({
            name = "Auto Load Config",
            icon = "lucide:download",
            description = "Makes the configuration above the one this script opens with automatically.",
            callback = function()
                if not selected or selected == "" then
                    self:Toast({ title = locale.resolve("Pick a configuration first") })
                    return
                end
                if self:SetAutoloadConfig(selected) then
                    self:Toast({ title = locale.resolve("Set as Auto Load Config"), subtitle = selected })
                else
                    self:Toast({ title = locale.resolve("Couldn't set Auto Load Config"), subtitle = selected })
                end
            end,
        })

        autoGroup:CreateToggle({
            name = "Auto Save Config",
            icon = "lucide:refresh-cw",
            description = "Keeps the configuration above updated as you change things.",
            value = autoSaveConfigFlag.value,
            callback = function(state)
                autoSaveConfigFlag:Set(state)
            end,
        })
    end

    -- Opt-in only (self._showUnloadButton, default false - see window.luau's own comment on it):
    -- a hold-to-confirm destructive action, so it's never one accidental click away. Danger Zone
    -- section lands last, after Configurations, so a player has already seen every save/export
    -- option before reaching the one button that throws all of it away for this session.
    if self._showUnloadButton then
        self.rfSettings:CreateSection({ name = "Danger Zone" })
        self.rfSettings:CreateHoldButton({
            name = "Destroy UI",
            icon = "lucide:trash-2",
            description = "Fully closes and unloads this menu. You'll need to run the script again to bring it back.",
            holdDuration = 1.5,
            danger = true,
            callback = function()
                self:Unload()
            end,
        })
    end

    if self._showSessionDashboard then
        self:_buildSessionDashboard()
    end
end

-- Devlog 7 "live session dashboard": player name, players on the server, uptime, and FPS,
-- refreshed every second. A plain card built straight onto rfSettings.tabPage rather than
-- through Tab:_register - it's a settings-only utility display, not a real element type devs
-- create, so it skips the reveal-fade system entirely and just renders opaque from the start.
function Window:_buildSessionDashboard()
    self.rfSettings:CreateSection({ name = "Session" })

    local card = self:Create("Frame", {
        Size = UDim2.new(1, -20, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Name = "SessionDashboard",
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BackgroundTransparency = 0,

        Parent = self.rfSettings.tabPage,
    }, { BackgroundTransparency = "ElementTransparency" })
    self:StyleElementBody(card)

    self:Create("UIPadding", {
        PaddingLeft = UDim.new(0, 20),
        PaddingRight = UDim.new(0, 20),
        PaddingTop = UDim.new(0, 14),
        PaddingBottom = UDim.new(0, 14),

        Parent = card,
    })

    self:Create("UIListLayout", {
        FillDirection = Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 8),

        Parent = card,
    })

    local function buildRow(order, labelText)
        local row = self:Create("Frame", {
            Size = UDim2.new(1, 0, 0, 16),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            LayoutOrder = order,

            Parent = card,
        })
        self:Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween,

            Parent = row,
        })
        self:Create("TextLabel", {
            Text = locale.t(labelText),
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,

            Parent = row,
        }, { TextColor3 = "PlaceholderColor", FontFace = "Font" })
        local value = self:Create("TextLabel", {
            Text = "-",
            Size = UDim2.fromOffset(0, 16),
            AutomaticSize = Enum.AutomaticSize.X,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Right,
            LayoutOrder = 1,

            Parent = row,
        }, { TextColor3 = "ContentColor", FontFace = "Font" })
        return value
    end

    local playerValue = buildRow(1, "Player")
    local playersValue = buildRow(2, "Players online")
    local uptimeValue = buildRow(3, "Uptime")
    local fpsValue = buildRow(4, "FPS")

    local playersService = game:GetService("Players")
    local localPlayer = playersService.LocalPlayer
    local sessionStart = os.clock()
    local frameCount = 0

    self:Connect(variables.runService.RenderStepped, function()
        frameCount += 1
    end)

    local function formatUptime(seconds)
        seconds = math.floor(seconds)
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        if h > 0 then
            return string.format("%d:%02d:%02d", h, m, s)
        end
        return string.format("%d:%02d", m, s)
    end

    task.spawn(function()
        while not self.unloaded do
            playerValue.Text = if localPlayer then localPlayer.Name else "-"
            playersValue.Text = tostring(#playersService:GetPlayers())
            uptimeValue.Text = formatUptime(os.clock() - sessionStart)
            fpsValue.Text = tostring(frameCount) -- frames counted over the last ~1s window
            frameCount = 0
            task.wait(1)
        end
    end)
end


return Window
