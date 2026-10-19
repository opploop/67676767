-- Local identity presentation only. Account identity, game remotes and other clients are unchanged.
return function(window, options)
    options = options or {}
    local players = game:GetService("Players")
    local player = options.player or players.LocalPlayer
    local alias = options.hubName or "Moon HUB"
    local icon = options.hubIcon or "rbxassetid://96306527242184"
    local excluded = options.exclude or window.main:FindFirstAncestorWhichIsA("ScreenGui")
    local id = tostring(player.UserId)
    local records, views, scopes, bindings, knownImages = {}, {}, {}, {}, {}
    local connections, characterConnections, rootSet, identityWatchers = {}, {}, {}, {}
    local queue, pending, head, generation = {}, {}, 1, 0
    local worker, viewWorker, frameConnection
    local active, hideName, hideAvatar, disposed = false, false, false, false
    local username, displayName = player.Name, player.DisplayName
    local batchSize = math.clamp(math.floor(tonumber(options.batchSize) or 64), 8, 256)
    local counters = { batches = 0, processed = 0, errors = 0, viewRefreshes = 0 }
    local controller = {}
    local track, refreshViews, schedule, scheduleViews, watchIdentity, unwatchIdentity

    local function disconnect(list)
        for _, c in list do
            c:Disconnect()
        end
        table.clear(list)
    end
    local function cancel(thread)
        if thread then
            pcall(task.cancel, thread)
        end
    end
    local function safe(fn, ...)
        local ok = pcall(fn, ...)
        if not ok then
            counters.errors += 1
        end
        return ok
    end
    local function skip(inst)
        local node = inst
        while node do
            if node:GetAttribute("MoonPrivacyOverlay") == true then
                return true
            end
            node = node.Parent
        end
        if typeof(excluded) == "Instance" then
            return inst == excluded or inst:IsDescendantOf(excluded)
        elseif type(excluded) == "table" then
            for _, root in excluded do
                if inst == root or inst:IsDescendantOf(root) then
                    return true
                end
            end
        elseif type(excluded) == "function" then
            local ok, result = pcall(excluded, inst)
            return not ok or result == true
        end
        return false
    end
    local function identity(inst)
        local binding = bindings[inst]
        if binding then
            return tostring(binding.userId) == id
        end
        local node = inst
        for _ = 1, 6 do
            if not node then
                break
            end
            for _, attribute in options.identityAttributes or { "UserId", "PlayerUserId", "OwnerUserId" } do
                local value = node:GetAttribute(attribute)
                if value ~= nil then
                    return tostring(value) == id
                end
            end
            node = node.Parent
        end
        return nil
    end
    local function isWord(byte)
        return byte
            and (
                byte >= 128
                or byte == 95
                or (byte >= 48 and byte <= 57)
                or (byte >= 65 and byte <= 90)
                or (byte >= 97 and byte <= 122)
            )
    end
    -- Map visible characters to source positions, preserving RichText tags and attributes.
    local function visibleText(value, rich)
        local chars, map = {}, {}
        local pos = 1
        while pos <= #value do
            local finish = rich and value:sub(pos, pos) == "<" and value:find(">", pos + 1, true)
            if finish then
                pos = finish + 1
            else
                table.insert(chars, value:sub(pos, pos))
                table.insert(map, pos)
                pos += 1
            end
        end
        return table.concat(chars), map
    end
    local function replace(value, rich, allowDisplay)
        local plain, map = visibleText(value, rich)
        local lower, ranges = plain:lower(), {}
        local candidates = { username }
        if allowDisplay and displayName ~= username then
            table.insert(candidates, displayName)
        end
        table.sort(candidates, function(a, b)
            return #a > #b
        end)
        local occupied = {}
        for _, name in candidates do
            local from = 1
            while name ~= "" do
                local first, last = lower:find(name:lower(), from, true)
                if not first then
                    break
                end
                local overlap = false
                for i = first, last do
                    if occupied[i] then
                        overlap = true
                        break
                    end
                end
                if not overlap and not isWord(plain:byte(first - 1)) and not isWord(plain:byte(last + 1)) then
                    table.insert(ranges, { first, last })
                    for i = first, last do
                        occupied[i] = true
                    end
                end
                from = last + 1
            end
        end
        if #ranges == 0 then
            return value
        end
        local starts, removed = {}, {}
        for _, range in ranges do
            starts[map[range[1]]] = if rich then alias:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;") else alias
            for i = range[1], range[2] do
                removed[map[i]] = true
            end
        end
        local output = {}
        for i = 1, #value do
            if starts[i] then
                table.insert(output, starts[i])
            end
            if not removed[i] then
                table.insert(output, value:sub(i, i))
            end
        end
        return table.concat(output)
    end
    local function thumbnail(value)
        if knownImages[value] then
            return true
        end
        local lower = value:lower():gsub("&amp;", "&")
        local kind = lower:match("[?&]type=([^&]+)") or lower:match("^rbxthumb://type=([^&]+)")
        local host = lower:match("^https?://([^/]+)/")
        local trusted = host
            and (host == "roblox.com" or host:sub(-11) == ".roblox.com")
            and (lower:find("thumbnail", 1, true) ~= nil)
        if lower:match("^rbxthumb://") then
            if not kind or not kind:match("^avatar") then
                return false
            end
        elseif not trusted then
            return false
        end
        for _, key in { "id", "userid", "userids" } do
            local found = lower:match("[?&]" .. key .. "=([^&]+)")
            if found and found:match("^%d+$") and found == id then
                return true
            end
        end
        return false
    end
    for uri, known in options.knownImages or {} do
        if type(uri) == "string" and known == true then
            knownImages[uri] = true
        end
    end
    local function inspectScope(inst)
        local node = inst
        while node do
            if node.Name == "InspectAndBuy" and not node:IsA("LuaSourceContainer") then
                return node
            end
            node = node.Parent
        end
    end
    local function inRoots(inst)
        for root in rootSet do
            if inst == root or inst:IsDescendantOf(root) then
                return true
            end
        end
        return false
    end
    local function unview(inst)
        local r = views[inst]
        if not r then
            return
        end
        views[inst] = nil
        disconnect(r.connections)
        safe(function()
            if inst.Visible == false then
                inst.Visible = r.original
            end
        end)
        if r.portal then
            r.portal:Destroy()
        end
        if r.slot then
            r.slot:Destroy()
        end
        if not next(views) and frameConnection then
            frameConnection:Disconnect()
            frameConnection = nil
        end
    end
    local function untrack(inst)
        local r = records[inst]
        if r then
            records[inst] = nil
            disconnect(r.connections)
            unwatchIdentity(inst, r)
            safe(function()
                if inst[r.property] == r.applied then
                    inst[r.property] = r.original
                end
            end)
        end
        unview(inst)
    end
    local function scopeIsLocal(scope)
        local owner = identity(scope)
        if owner ~= nil then
            return owner
        end
        for _, inst in scope:QueryDescendants("TextLabel, TextButton, ImageLabel, ImageButton") do
            local own = identity(inst)
            if own == true then
                return true
            end
            if own == false then
                continue
            end
            local r = records[inst]
            if
                (inst:IsA("TextLabel") or inst:IsA("TextButton"))
                and (inst.Name == "HeaderText" or inst.Name == "UserName" or inst.Name == "Username")
            then
                local value = if r then r.original else inst.Text
                if replace(value, inst.RichText, false) ~= value then
                    return true
                end
            end
        end
        return false
    end
    local function geometry(inst, r)
        if not inst.Parent then
            unview(inst)
            return
        end
        local screen = inst:FindFirstAncestorWhichIsA("ScreenGui")
        if not screen then
            unview(inst)
            return
        end
        if r.portal.Parent ~= screen then
            r.portal.Parent = screen
        end
        local parent = inst.Parent
        local layout = parent:FindFirstChildWhichIsA("UIListLayout") or parent:FindFirstChildWhichIsA("UIGridLayout")
        if layout then
            if not r.slot then
                r.slot = Instance.new("Frame")
                r.slot.Name = "MoonPrivacyAvatarSlot"
                r.slot:SetAttribute("MoonPrivacyOverlay", true)
                r.slot.BackgroundTransparency = 1
                r.slot.BorderSizePixel = 0
            end
            r.slot.Size = inst.Size
            r.slot.Position = inst.Position
            r.slot.AnchorPoint = inst.AnchorPoint
            r.slot.LayoutOrder = inst.LayoutOrder
            r.slot.Rotation = inst.Rotation
            r.slot.Visible = r.original
            local scale = inst:FindFirstChildWhichIsA("UIScale")
            if scale then
                local mirror = r.slot:FindFirstChildWhichIsA("UIScale") or Instance.new("UIScale")
                mirror.Scale = scale.Scale
                mirror.Parent = r.slot
            else
                local mirror = r.slot:FindFirstChildWhichIsA("UIScale")
                if mirror then
                    mirror:Destroy()
                end
            end
            r.slot.Parent = parent
        elseif r.slot then
            r.slot:Destroy()
            r.slot = nil
        end
        local source = r.slot or inst
        local point, size = source.AbsolutePosition, source.AbsoluteSize
        local left, top, right, bottom = point.X, point.Y, point.X + size.X, point.Y + size.Y
        local shown, node = r.original, inst.Parent
        while node and node ~= screen do
            if node:IsA("GuiObject") then
                shown = shown and node.Visible
                if node.ClipsDescendants then
                    local p, extent = node.AbsolutePosition, node.AbsoluteSize
                    left = math.max(left, p.X)
                    top = math.max(top, p.Y)
                    right = math.min(right, p.X + extent.X)
                    bottom = math.min(bottom, p.Y + extent.Y)
                end
            end
            node = node.Parent
        end
        r.portal.Visible = shown and screen.Enabled and right > left and bottom > top
        local origin = screen.AbsolutePosition
        r.portal.Position = UDim2.fromOffset(left - origin.X, top - origin.Y)
        r.portal.Size = UDim2.fromOffset(math.max(0, right - left), math.max(0, bottom - top))
        r.portal.ZIndex = inst.ZIndex + 1
        r.overlay.Position = UDim2.fromOffset(point.X - left + size.X / 2, point.Y - top + size.Y / 2)
        r.overlay.Size = UDim2.fromOffset(size.X, size.Y)
        r.overlay.Rotation = source.AbsoluteRotation
        r.overlay.ZIndex = r.portal.ZIndex
    end
    local function maskView(inst)
        if views[inst] or skip(inst) then
            return
        end
        local screen = inst:FindFirstAncestorWhichIsA("ScreenGui")
        if not screen then
            return
        end
        local portal = Instance.new("Frame")
        portal.Name = "MoonPrivacyAvatarLayer"
        portal:SetAttribute("MoonPrivacyOverlay", true)
        portal.BackgroundTransparency = 1
        portal.ClipsDescendants = true
        local overlay = Instance.new("ImageLabel")
        overlay.Name = "MoonPrivacyAvatar"
        overlay:SetAttribute("MoonPrivacyOverlay", true)
        overlay.BackgroundTransparency = 1
        overlay.Image = icon
        overlay.ScaleType = Enum.ScaleType.Fit
        overlay.AnchorPoint = Vector2.new(0.5, 0.5)
        overlay.Parent = portal
        local r = { original = inst.Visible, portal = portal, overlay = overlay, connections = {} }
        views[inst] = r
        portal.Parent = screen
        inst.Visible = false
        table.insert(
            r.connections,
            inst:GetPropertyChangedSignal("Visible"):Connect(function()
                if views[inst] ~= r or inst.Visible == false then
                    return
                end
                r.original = inst.Visible
                inst.Visible = false
            end)
        )
        table.insert(
            r.connections,
            inst.Destroying:Connect(function()
                unview(inst)
            end)
        )
        geometry(inst, r)
        if not frameConnection then
            frameConnection = game:GetService("RunService").Heartbeat:Connect(function()
                for viewport, state in views do
                    safe(geometry, viewport, state)
                end
            end)
        end
    end
    refreshViews = function()
        if disposed or not active then
            return
        end
        counters.viewRefreshes += 1
        local wanted = {}
        if hideAvatar then
            for scope in scopes do
                if not scope.Parent or not inRoots(scope) then
                    scopes[scope] = nil
                elseif scopeIsLocal(scope) then
                    for _, viewport in scope:QueryDescendants("ViewportFrame") do
                        wanted[viewport] = true
                    end
                end
            end
            for inst, binding in bindings do
                if binding.kind == "viewport" and inst.Parent and tostring(binding.userId) == id then
                    wanted[inst] = true
                end
            end
        end
        for inst in views do
            if not wanted[inst] or skip(inst) then
                unview(inst)
            end
        end
        for inst in wanted do
            maskView(inst)
        end
    end
    scheduleViews = function()
        if disposed or not active or not hideAvatar or viewWorker then
            return
        end
        local epoch = generation
        viewWorker = task.defer(function()
            viewWorker = nil
            if epoch == generation and active and not disposed then
                safe(refreshViews)
            end
        end)
    end
    local function identityContainer(inst)
        local node = inst.Parent
        for _ = 1, 4 do
            if not node then
                break
            end
            if node.Name == "NameContainer" or node.Name == "PersonRow" then
                return node
            end
            node = node.Parent
        end
    end
    local function contextIsLocal(inst)
        local container = identityContainer(inst)
        if not container then
            return false
        end
        for _, label in container:QueryDescendants("TextLabel, TextButton") do
            if label.Name == "UserName" or label.Name == "Username" then
                local record = records[label]
                local original = if record then record.original else label.Text
                local plain = visibleText(original, label.RichText)
                if plain:lower():match("^%s*@?(.-)%s*$") == username:lower() then
                    return true
                end
            end
        end
        return false
    end
    local function scrub(inst, r)
        if disposed or records[inst] ~= r then
            return
        end
        local value = inst[r.property]
        if value ~= r.applied then
            r.original = value
        end
        local replacement = r.original
        local owner = identity(inst)
        if owner ~= false then
            if hideName and (r.property == "Text" or r.property == "DisplayName") then
                local binding = bindings[inst]
                local scope = inspectScope(inst)
                local displaySource = if r.property == "Text" and inst.RichText
                    then visibleText(r.original, true)
                    else r.original
                local hasDisplay = displayName ~= username
                    and displaySource:lower():find(displayName:lower(), 1, true) ~= nil
                local allowDisplay = hasDisplay
                    and (
                        owner == true
                        or contextIsLocal(inst)
                        or r.property == "DisplayName"
                        or (scope and scopeIsLocal(scope))
                        or options.displayNamePolicy == "all"
                    )
                if r.property == "DisplayName" or (binding and binding.whole == true) then
                    local word = if r.property == "Text" and inst.RichText
                        then alias:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
                        else alias
                    replacement = if r.original:sub(1, 1) == "@" then "@" .. word else word
                else
                    replacement = replace(r.original, r.property == "Text" and inst.RichText, allowDisplay)
                end
            elseif hideAvatar and r.property == "Image" and (owner == true or thumbnail(r.original)) then
                replacement = icon
            end
        end
        r.applied = replacement
        if value ~= replacement then
            inst[r.property] = replacement
        end
    end
    local function propertyFor(inst)
        local binding = bindings[inst]
        if binding and binding.kind == "viewport" then
            return nil
        end
        if hideName and (inst:IsA("TextLabel") or inst:IsA("TextButton")) then
            return "Text"
        end
        if hideAvatar and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
            return "Image"
        end
        if hideName and inst:IsA("Humanoid") and player.Character and inst.Parent == player.Character then
            return "DisplayName"
        end
        return nil
    end
    unwatchIdentity = function(inst, r)
        for _, node in r.identityNodes or {} do
            local watcher = identityWatchers[node]
            if watcher then
                watcher.targets[inst] = nil
                if not next(watcher.targets) then
                    watcher.connection:Disconnect()
                    identityWatchers[node] = nil
                end
            end
        end
        r.identityNodes = nil
    end
    watchIdentity = function(inst, r)
        unwatchIdentity(inst, r)
        r.identityNodes = {}
        local node = inst
        for _ = 1, 6 do
            if not node then
                break
            end
            local watcher = identityWatchers[node]
            if not watcher then
                watcher = { targets = {} }
                identityWatchers[node] = watcher
                watcher.connection = node.AttributeChanged:Connect(function(attribute)
                    if
                        not table.find(
                            options.identityAttributes or { "UserId", "PlayerUserId", "OwnerUserId" },
                            attribute
                        )
                    then
                        return
                    end
                    for target in watcher.targets do
                        schedule(target)
                        if inspectScope(target) then
                            scheduleViews()
                        end
                    end
                end)
            end
            watcher.targets[inst] = true
            table.insert(r.identityNodes, node)
            node = node.Parent
        end
    end
    local function watchRichText(inst, r)
        -- Plain fields do not need an extra listener until markup can affect redaction.
        if r.property ~= "Text" or r.richConnection or not (r.original:find("<", 1, true) or alias:find("[<>&]")) then
            return
        end
        r.richConnection = inst:GetPropertyChangedSignal("RichText"):Connect(function()
            safe(scrub, inst, r)
        end)
        table.insert(r.connections, r.richConnection)
    end
    track = function(inst)
        if not active or disposed or not inst.Parent or skip(inst) or (not bindings[inst] and not inRoots(inst)) then
            return
        end
        local scope = hideAvatar and inspectScope(inst)
        if scope then
            scopes[scope] = true
            scheduleViews()
        end
        local property = propertyFor(inst)
        local r = records[inst]
        if r then
            if r.property ~= property then
                untrack(inst)
                r = nil
            else
                scrub(inst, r)
                return
            end
        end
        if not property then
            return
        end
        r = { property = property, original = inst[property], connections = {} }
        records[inst] = r
        watchIdentity(inst, r)
        table.insert(
            r.connections,
            inst.AncestryChanged:Connect(function()
                if records[inst] ~= r then
                    return
                end
                watchIdentity(inst, r)
                schedule(inst)
                if inspectScope(inst) then
                    scheduleViews()
                end
            end)
        )
        table.insert(
            r.connections,
            inst:GetPropertyChangedSignal(property):Connect(function()
                if records[inst] ~= r or inst[property] == r.applied then
                    return
                end
                safe(scrub, inst, r)
                watchRichText(inst, r)
                if property == "Text" then
                    local container = identityContainer(inst)
                    if container then
                        for _, label in container:QueryDescendants("TextLabel, TextButton") do
                            schedule(label)
                        end
                    end
                end
                if inspectScope(inst) then
                    scheduleViews()
                end
            end)
        )
        watchRichText(inst, r)
        table.insert(
            r.connections,
            inst.Destroying:Connect(function()
                untrack(inst)
            end)
        )
        scrub(inst, r)
    end
    local function drain(epoch)
        worker = nil
        if epoch ~= generation or not active or disposed then
            return
        end
        counters.batches += 1
        for _ = 1, batchSize do
            if head > #queue or epoch ~= generation then
                break
            end
            local inst = queue[head]
            head += 1
            pending[inst] = nil
            safe(track, inst)
            counters.processed += 1
        end
        if head <= #queue then
            worker = task.spawn(function()
                game:GetService("RunService").Heartbeat:Wait()
                drain(epoch)
            end)
        else
            table.clear(queue)
            head = 1
        end
    end
    schedule = function(inst)
        if not active or disposed or pending[inst] or skip(inst) then
            return
        end
        if not bindings[inst] and not inRoots(inst) then
            return
        end
        local relevant = propertyFor(inst) or (hideAvatar and inst:IsA("ViewportFrame"))
        if not relevant then
            return
        end
        pending[inst] = true
        table.insert(queue, inst)
        if not worker then
            worker = task.defer(drain, generation)
        end
    end
    local function collect(root)
        local selectors = {}
        if hideName then
            table.insert(selectors, "TextLabel, TextButton")
        end
        if hideAvatar then
            table.insert(selectors, "ImageLabel, ImageButton, ViewportFrame")
        end
        for _, inst in root:QueryDescendants(table.concat(selectors, ", ")) do
            schedule(inst)
        end
    end
    local function addRoot(root)
        if rootSet[root] then
            return
        end
        rootSet[root] = true
        table.insert(connections, root.DescendantAdded:Connect(schedule))
        table.insert(
            connections,
            root.DescendantRemoving:Connect(function(inst)
                local affectsView = hideAvatar and inspectScope(inst) ~= nil
                if not bindings[inst] then
                    untrack(inst)
                end
                if affectsView then
                    scheduleViews()
                end
            end)
        )
        collect(root)
    end
    local function character(model)
        disconnect(characterConnections)
        for inst, r in records do
            if r.property == "DisplayName" then
                untrack(inst)
            end
        end
        if not active or not model then
            return
        end
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid then
            schedule(humanoid)
        end
        table.insert(
            characterConnections,
            model.ChildAdded:Connect(function(child)
                if child:IsA("Humanoid") then
                    schedule(child)
                end
            end)
        )
    end
    local function start()
        active = true
        if options.roots then
            for _, root in options.roots do
                addRoot(root)
            end
        else
            addRoot(workspace)
            local ok, core = pcall(game.GetService, game, "CoreGui")
            if ok then
                addRoot(core)
            end
            local gui = player:FindFirstChildOfClass("PlayerGui")
            if gui then
                addRoot(gui)
            end
            table.insert(
                connections,
                player.ChildAdded:Connect(function(child)
                    if child:IsA("PlayerGui") then
                        addRoot(child)
                    end
                end)
            )
        end
        table.insert(connections, player.CharacterAdded:Connect(character))
        if player.GetPropertyChangedSignal then
            table.insert(
                connections,
                player:GetPropertyChangedSignal("DisplayName"):Connect(function()
                    displayName = player.DisplayName
                    for inst in records do
                        schedule(inst)
                    end
                end)
            )
        end
        if player.Character then
            character(player.Character)
        end
    end
    local fetching, fetched, fetchWorker = false, false, nil
    local function fetchThumbnails()
        if fetching or fetched or options.skipThumbnailFetch then
            return
        end
        fetching = true
        fetchWorker = task.defer(function()
            for _, kind in
                { Enum.ThumbnailType.HeadShot, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailType.AvatarThumbnail }
            do
                for _, size in
                    {
                        Enum.ThumbnailSize.Size48x48,
                        Enum.ThumbnailSize.Size100x100,
                        Enum.ThumbnailSize.Size150x150,
                        Enum.ThumbnailSize.Size420x420,
                    }
                do
                    if disposed then
                        fetching = false
                        return
                    end
                    local ok, uri = pcall(players.GetUserThumbnailAsync, players, player.UserId, kind, size)
                    if ok and type(uri) == "string" then
                        knownImages[uri] = true
                    end
                end
            end
            fetching = false
            fetched = true
            fetchWorker = nil
            if active and hideAvatar then
                for inst, r in records do
                    if r.property == "Image" then
                        schedule(inst)
                    end
                end
                scheduleViews()
            end
        end)
    end
    local function watermark()
        local wm = options.watermark
        if wm then
            safe(function()
                wm:SetSubtitle(if hideName then "@" .. alias else "@" .. username)
                if wm.avatar then
                    wm.avatar.Image = if hideAvatar
                        then icon
                        else ("rbxthumb://type=AvatarHeadShot&id=%s&w=150&h=150"):format(player.UserId)
                end
            end)
        end
    end
    local function clearQueue()
        generation += 1
        cancel(worker)
        cancel(viewWorker)
        worker = nil
        viewWorker = nil
        table.clear(queue)
        table.clear(pending)
        head = 1
    end
    function controller:Set(name, avatar)
        if disposed then
            return false
        end
        local nextAvatar = avatar == true
        local nextName = name == true or nextAvatar
        if hideName == nextName and hideAvatar == nextAvatar then
            return true
        end
        clearQueue()
        hideName, hideAvatar = nextName, nextAvatar
        if not hideAvatar then
            cancel(fetchWorker)
            fetchWorker = nil
            fetching = false
        end
        if hideName or hideAvatar then
            if not active then
                start()
            else
                for root in rootSet do
                    collect(root)
                end
            end
            for inst in records do
                if not propertyFor(inst) then
                    untrack(inst)
                else
                    schedule(inst)
                end
            end
            for inst in bindings do
                schedule(inst)
            end
            if player.Character then
                character(player.Character)
            end
            if hideAvatar then
                fetchThumbnails()
                scheduleViews()
            else
                for inst in views do
                    unview(inst)
                end
            end
        else
            active = false
            disconnect(connections)
            disconnect(characterConnections)
            cancel(fetchWorker)
            fetchWorker = nil
            fetching = false
            for inst in records do
                untrack(inst)
            end
            for inst in views do
                unview(inst)
            end
            table.clear(scopes)
            table.clear(rootSet)
        end
        watermark()
        return true
    end
    function controller:Bind(inst, specification)
        assert(typeof(inst) == "Instance", "Privacy Bind expects an Instance")
        assert(type(specification) == "table", "Privacy Bind expects a specification")
        local kind = specification.kind
        assert(
            (kind == "name" and (inst:IsA("TextLabel") or inst:IsA("TextButton")))
                or (kind == "avatar" and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")))
                or (kind == "viewport" and inst:IsA("ViewportFrame")),
            "Privacy binding kind does not match the instance"
        )
        assert(specification.userId ~= nil, "Privacy Bind requires the represented userId")
        if disposed then
            return function() end
        end
        local previous = bindings[inst]
        if previous then
            previous.release()
        end
        local binding =
            { kind = kind, userId = specification.userId, whole = specification.whole == true, connections = {} }
        bindings[inst] = binding
        local function release()
            if bindings[inst] ~= binding then
                return
            end
            bindings[inst] = nil
            disconnect(binding.connections)
            untrack(inst)
            if active and inst.Parent and inRoots(inst) then
                schedule(inst)
            end
            scheduleViews()
        end
        binding.release = release
        table.insert(binding.connections, inst.Destroying:Connect(release))
        table.insert(
            binding.connections,
            inst.AncestryChanged:Connect(function()
                schedule(inst)
                scheduleViews()
            end)
        )
        schedule(inst)
        scheduleViews()
        return release
    end
    function controller:Destroy()
        if disposed then
            return
        end
        self:Set(false, false)
        disposed = true
        clearQueue()
        for _, binding in table.clone(bindings) do
            binding.release()
        end
        if self._unload then
            self._unload()
            self._unload = nil
        end
    end
    function controller:Stats()
        local watched, overlays, bound, total = 0, 0, 0, #connections + #characterConnections
        local text, images = 0, 0
        for _, r in records do
            watched += 1
            total += #r.connections
            if r.property == "Image" then
                images += 1
            else
                text += 1
            end
        end
        for _, r in views do
            overlays += 1
            total += #r.connections
        end
        for _ in identityWatchers do
            total += 1
        end
        for _, binding in bindings do
            bound += 1
            total += #binding.connections
        end
        if frameConnection then
            total += 1
        end
        return {
            active = active,
            disposed = disposed,
            watched = watched,
            text = text,
            images = images,
            overlays = overlays,
            bindings = bound,
            connections = total,
            rootConnections = #connections,
            characterConnections = #characterConnections,
            queued = math.max(0, #queue - head + 1),
            batches = counters.batches,
            processed = counters.processed,
            errors = counters.errors,
            viewRefreshes = counters.viewRefreshes,
        }
    end
    controller.ReplaceName = function(value)
        return replace(value, false, true)
    end
    controller.IsThumbnail = thumbnail
    controller._unload = window:OnUnload(function()
        controller:Destroy()
    end)
    for _, binding in options.bindings or {} do
        controller:Bind(binding.instance, binding)
    end
    return controller
end
