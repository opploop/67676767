-- Stage 2: selection details and ID-based priorities. UI fixtures only; no game remotes.
return function(Rayfield)
    local window = Rayfield:CreateWindow({
        name = "Details & priorities · Stage 2",
        size = Vector2.new(900, 720),
        showBanner = false,
        locale = "en",
        autoTranslate = false,
        searchScope = "all",
        configuration = { autoLoad = false, autoSave = false },
    })
    local handles = { window = window }
    local logo = "rbxassetid://96306527242184"
    local function action(id, text)
        return {
            id = id,
            text = text,
            primary = id == "start" or id == "join",
            icon = if id == "start" then "lucide:play" elseif id == "join" then "lucide:log-in" else nil,
            callback = function(selected, request)
                task.wait(0.2)
                if request.isCancelled() then
                    return false, "Cancelled"
                end
                handles.lastAction = { id = id, item = selected.id }
                return true
            end,
            options = { successText = "UI demonstration completed." },
        }
    end
    local macros = {
        {
            id = "macro:training",
            name = "Training route",
            image = logo,
            description = "Inspect the map, required team and timing before starting. These actions demonstrate UI feedback only.",
            badges = { { text = "Ready", color = "success" }, "Story" },
            properties = {
                { label = "Map", value = "Training grounds" },
                { label = "Mode", value = "Story" },
                { label = "Difficulty", value = "Normal", icon = "lucide:gauge" },
                { label = "Duration", value = "02:15", icon = "lucide:clock" },
                {
                    label = "Required team",
                    value = "Six equipped units",
                    images = { logo, logo, logo, logo, logo, logo },
                },
            },
            actions = { action("equip", "Equip required team"), action("start", "Start macro") },
        },
        {
            id = "macro:challenge",
            name = "Challenge route",
            image = logo,
            description = "A second stable ID with different requirements.",
            badges = { { text = "Needs team", color = "warning" } },
            properties = {
                { label = "Map", value = "Mountain pass" },
                { label = "Mode", value = "Challenge" },
                { label = "Difficulty", value = "Hard", icon = "lucide:gauge" },
                { label = "Duration", value = "04:30", icon = "lucide:clock" },
                { label = "Required team", value = "Hill + Ground units" },
            },
            actions = {
                action("equip", "Equip required team"),
                {
                    id = "start",
                    primary = true,
                    icon = "lucide:play",
                    text = "Start macro",
                    enabled = false,
                    disabledReason = "Equip the required team first.",
                },
            },
        },
    }
    local overview = window:CreateTab({ name = "Macro details", icon = "lucide:info" })
    handles.macros = overview:CreateDropdown({
        name = "Selected macro",
        options = { "Training route", "Challenge route" },
        value = "Training route",
    })
    handles.details = overview:CreateItemDetails({
        name = "Macro details",
        items = macros,
        source = handles.macros,
        binding = {
            getSelection = function(value)
                return if value == "Training route"
                    then "macro:training"
                    elseif value == "Challenge route" then "macro:challenge"
                    else nil
            end,
        },
    })
    overview:CreateButton({
        name = "Refresh metadata without changing selection",
        callback = function()
            macros[1].properties[4].value = "02:16"
            handles.details:Refresh(macros)
        end,
    })
    local slots = {}
    local slotDetails = {}
    for i = 1, 6 do
        local id = "slot:" .. i
        local enabled = i ~= 6
        table.insert(slots, {
            id = id,
            name = "Unit slot " .. i,
            image = logo,
            subtitle = if i % 2 == 0 then "Hill · upgrade priority" else "Ground · placement priority",
            badges = {
                { text = if enabled then "Equipped" else "Empty", color = if enabled then "success" else "warning" },
                "Slot " .. i,
            },
            enabled = enabled,
            disabledReason = if enabled then nil else "Unit is not equipped. Select to inspect.",
        })
        table.insert(slotDetails, {
            id = id,
            name = "Unit slot " .. i,
            image = logo,
            available = enabled,
            disabledReason = "This slot has no equipped unit.",
            badges = { "Stable ID: " .. id },
            properties = {
                { label = "Slot", value = i },
                { label = "Placement", value = if i % 2 == 0 then "Hill" else "Ground" },
                { label = "Copies", value = 3 },
            },
            actions = { action("inspect", "Inspect unit") },
        })
    end
    local priorities = window:CreateTab({ name = "Unit priorities", icon = "lucide:list-ordered" })
    priorities:CreateRichText({
        content = "Drag the grip or use the arrows. Click a row to inspect it. Refresh keeps the committed order and selected ID.",
    })
    handles.priorities = priorities:CreateReorderList({
        name = "Placement priority",
        rich = true,
        maxHeight = 224,
        flag = "stage2-priorities",
        items = slots,
    })
    handles.slotDetails =
        priorities:CreateItemDetails({ name = "Selected slot", items = slotDetails, source = handles.priorities })
    handles.priorities:SelectItem("slot:1")
    priorities:CreateButton({
        name = "Refresh slot names",
        callback = function()
            slots[1].name = "Unit slot 1 · refreshed"
            handles.priorities:Refresh(slots, true)
            handles.slotDetails:Refresh(slotDetails)
        end,
    })
    local challenges = window:CreateTab({ name = "Challenge details", icon = "lucide:timer" })
    local challengeItems = {
        {
            id = "challenge:daily",
            name = "Daily challenge",
            image = logo,
            description = "The hub provides live values; the panel does not run the challenge or own its timer.",
            badges = { "Daily", { text = "Available", color = "success" } },
            properties = {
                { label = "Map", value = "Training grounds" },
                { label = "Modifier", value = "Reduced range" },
                { label = "Time remaining", value = "12:30" },
                { label = "Rewards", value = "Gems · upgrade materials" },
            },
            actions = { action("join", "Enter challenge") },
        },
        {
            id = "challenge:event",
            name = "Event challenge",
            image = logo,
            available = false,
            disabledReason = "The event is currently closed.",
            badges = { { text = "Unavailable", color = "warning" } },
            properties = { { label = "Map", value = "Event arena" }, { label = "Rewards", value = "Event currency" } },
            actions = { action("join", "Enter challenge") },
        },
    }
    handles.challenges = challenges:CreateItemGrid({
        name = "Challenges",
        multiSelect = false,
        items = {
            { id = "challenge:daily", name = "Daily challenge", image = logo },
            { id = "challenge:event", name = "Event challenge", image = logo },
        },
    })
    handles.challengeDetails = challenges:CreateItemDetails({
        name = "Challenge details",
        items = challengeItems,
        source = handles.challenges,
    })
    challenges:CreateButton({
        name = "Show multiple-selection summary",
        callback = function()
            handles.challengeDetails:Select({ "challenge:daily", "challenge:event" })
        end,
    })
    challenges:CreateButton({
        name = "Show loading state",
        callback = function()
            handles.challengeDetails:SetLoading(true)
        end,
    })
    challenges:CreateButton({
        name = "Restore challenge data",
        callback = function()
            handles.challengeDetails:Refresh(challengeItems)
        end,
    })
    handles.slots, handles.macrosData, handles.slotData = slots, macros, slotDetails
    return handles
end
