-- Library stage 1: public rich text and shared feedback. UI-only; no game automation.
-- Pass the same Rayfield library instance your hub uses. Returns handles for integration tests.
return function(Rayfield)
    local window = Rayfield:CreateWindow({
        name = "Rich text & feedback · Stage 1",
        showBanner = false,
        locale = "en",
        autoTranslate = false,
        searchScope = "all",
        configuration = { autoLoad = false, autoSave = false },
    })
    local tab = window:CreateTab({ name = "Overview", icon = "lucide:layout-dashboard" })
    local introduction = tab:CreateRichText({
        name = "Selection summary",
        title = "A readable summary, inside its own container",
        content = {
            { text = "Macro preview\n", style = "title" },
            { text = "Map: Training · Mode: Story · Difficulty: Normal\n" },
            { text = "Team ready", style = "success" },
            { text = " · Estimated duration: 02:15\n" },
            { text = "Plain text is safe: wave < 10 & resources > 0." },
        },
    })
    local ready, start
    ready = tab:CreateToggle({
        name = "Requirements met",
        value = false,
        callback = function(value)
            if value then
                start:Unlock()
            else
                start:Lock("Select a macro and equip its required team first.")
            end
        end,
    })
    start = tab:CreateButton({ name = "Run UI demonstration" })
    start:Lock("Select a macro and equip its required team first.")
    start.callback = function()
        start:Run(function(control, request)
            for step = 1, 8 do
                if request.isCancelled() then
                    return
                end
                control:SetStatus("Preparing selection", "loading", step / 8)
                task.wait(0.2)
            end
            return true
        end, { timeout = 5, busyText = "Preparing…", successText = "Ready to integrate into your hub." })
    end
    local cancel = tab:CreateButton({
        name = "Cancel demonstration",
        callback = function()
            if not start:CancelRun("Stopped by user.") then
                window:NotifyInfo({ title = "Nothing running", content = "Start the demonstration first." })
            end
        end,
    })
    local mode = tab:CreateDropdown({ name = "Mode", options = { "Story", "Challenge", "Raid" }, value = "Story" })
    mode:SetStatus("Select the mode required by your macro.", "idle")
    local states = tab:CreateCollapsible({ name = "Status examples", expanded = true })
    local errorExample = states:CreateButton({ name = "Unavailable action" })
    errorExample:SetStatus("The last request failed. Your selection was preserved.", "error")
    local compact = states:CreateGroup({ direction = "row" }):CreateToggle({ name = "Compact lock" })
    compact:Lock("Available in the lobby. Tap the locked card or hover to read why.")
    states:CreateRichText({
        content = {
            { text = "Warning: ", style = "warning" },
            { text = "This is a UI demonstration. The hub supplies its own requirements and operations." },
        },
    })
    local nested = window:CreateTab({ name = "Nested hosts", icon = "lucide:layers" })
    local page = nested:CreateSubTab({ name = "Details" })
    page:CreateGroup({ direction = "column" }):CreateRichText({
        title = "Long text wraps inside this subtab",
        content = string.rep("The selected item remains in its own host. ", 12),
    })
    local raw = page:CreateCollapsible({ name = "Explicit markup" })
    raw:CreateRichText({
        content = {
            { text = "This span is plain: <b>not a tag</b>.\n" },
            { text = "<b>This developer-authored span explicitly enables markup.</b>", raw = true },
        },
    })
    return { window = window, summary = introduction, ready = ready, start = start, cancel = cancel, mode = mode }
end
