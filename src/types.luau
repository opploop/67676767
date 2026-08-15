--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Public API types. camelCase is the documented surface; PascalCase keys still work.

export type Theme = string | { [string]: any }

-- Optional dev hook: given a source string (the English copy, which doubles as its key) and the
-- active locale id, return the translation, or nil/"" to fall through to the built-in tables.
export type Translator = (source: string, localeId: string) -> string?

-- Translation tables keyed by locale id, each mapping a source string to its translation, e.g.
-- { fr = { ["Close"] = "Fermer" }, ["pt-br"] = { ["Close"] = "Fechar" } }.
export type Translations = { [string]: { [string]: string } }

export type WindowConfiguration = {
    autoSave: boolean?,
    autoLoad: boolean?,
    fileName: string?,
    customFolder: string?,
}

export type WindowProps = {
    name: string?,
    subtitle: string?,
    theme: Theme?,
    icon: (string | number)?,
    showName: string?,
    showIcon: (string | number)?,
    configuration: WindowConfiguration?,
    fallbackFont: (Font | Enum.Font)?, -- built-in stand-in shown in secure mode while the brand font downloads
    locale: string?, -- pin the UI language; defaults to the player's Roblox locale
    translations: Translations?, -- language tables keyed by locale id; the easy, table-first path
    translator: Translator?, -- resolve copy yourself; falls back to the built-in tables
    tabStyle: ("white" | "accent")?, -- the shared tab pill's look (default "accent")
    tabAccentGlow: boolean?, -- soft glow under the pill in accent mode (default true)
    -- initial window size (Vector2, a UDim2's offset component, or a {width,height}/{X,Y} table)
    -- - still screen-fit the same way the built-in default is, see windowSizing.luau
    size: (Vector2 | UDim2 | { [string]: number } | { number })?,
}

export type TabProps = {
    name: string?,
    icon: (string | number)?,
    locked: boolean?,
}

export type TagProps = {
    text: string?,
    title: string?,
    icon: (string | number)?,
    color: Color3?,
    order: number?,
}

export type SectionProps = {
    name: string?,
    icon: (string | number)?,
}

export type LabelProps = {
    text: string?,
    icon: (string | number)?,
}

export type ParagraphProps = {
    title: string?,
    content: string?,
    icon: (string | number)?,
}

export type DividerProps = {
    text: string?,
    line: boolean?, -- default true; false = spacing-only, no visible rule
    spacing: string?, -- "tight" | "normal" (default) | "loose" - vertical padding around the line
    height: number?, -- gap height in px when line = false (default 24)
}

export type GroupProps = {
    direction: string?, -- "row" | "column" (default row); "horizontal"/"vertical" also work
}

-- tooltip is shared by every card element (see Window:_wireTooltip): hold the mouse a moment
-- and it fades in above the cursor, wrapping for longer text.
export type ButtonProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    locked: boolean?,
    callback: (() -> ())?,
}

export type ToggleProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    value: boolean?,
    locked: boolean?,
    forgetState: boolean?,
    callback: ((value: boolean) -> ())?,
}

-- A compact alternative to Toggle: same flag/config/description contract, a check box instead
-- of a pill switch.
export type CheckboxProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    value: boolean?,
    forgetState: boolean?,
    callback: ((value: boolean) -> ())?,
}

export type CopyButtonProps = {
    name: string?,
    description: string?,
    icon: (string | number)?, -- shown inside the well; the well still works without one
    tooltip: string?,
    text: string?, -- the string copied to the clipboard
    callback: ((success: boolean) -> ())?, -- fires after every press with whether the copy landed
}

export type FlipButtonProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    secondaryName: string?, -- the back face; hovering flips the title to this and back
    callback: (() -> ())?,
}

-- A Button whose press feedback is a ripple from the exact point pressed (mouse or touch),
-- clipped to the card's rounded corners, instead of Button's stroke-ghost + width-bounce.
export type RippleButtonProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    callback: (() -> ())?,
}

export type ProgressBarProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    value: number?,
    max: number?, -- default 100
    suffix: string?, -- set this to switch the readout to "{value} {suffix} out of {max}"
}

export type ScrollHintProps = {
    text: string?,
}

export type SegmentedPickerOption = string | {
    text: string?,
    Text: string?,
    -- nested sub-options, expanded inline within this segment's own slot once it's selected
    options: { (string | { text: string?, Text: string? }) }?,
    Options: { (string | { text: string?, Text: string? }) }?,
}

export type SegmentedPickerProps = {
    options: { SegmentedPickerOption }?,
    value: string?, -- a leaf's text - a top-level option's own, or a nested child's
    description: string?,
    flag: string?,
    forgetState: boolean?,
    callback: ((value: string) -> ())?,
}

export type ShimmerLabelProps = {
    text: string?,
    speed: number?, -- seconds per sweep (default 1.4)
    spread: number?, -- 0..1, width of the bright band (default 0.2)
    angle: number?, -- gradient rotation in degrees (default 20)
    textSize: number?,
}

export type SliderProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    range: { number }?, -- { min, max }
    increment: number?,
    value: number?,
    suffix: string?,
    minimal: boolean?, -- track only, no name/value (for dense rows)
    forgetState: boolean?,
    callback: ((value: number) -> ())?,
}

export type DropdownSection = {
    name: string?,
    options: { string }?,
}

export type DropdownProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    options: { string }?,
    -- section headers (e.g. "MELEE"/"RANGED") - when given, takes over from `options` above,
    -- which is instead derived by flattening every section's own option list in order
    sections: { DropdownSection }?,
    value: (string | { string })?,
    multiSelect: boolean?,
    placeholder: string?,
    locked: boolean?,
    forgetState: boolean?,
    callback: ((value: any) -> ())?,
}

export type InputProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    value: string?,
    placeholder: string?,
    numeric: boolean?,
    clearOnFocus: boolean?,
    forgetState: boolean?,
    callback: ((value: string) -> ())?,
}

export type KeybindProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    value: (EnumItem | string)?, -- an Enum.KeyCode / mouse button, or a KeyCode name
    forgetState: boolean?,
    isMenuToggle: boolean?, -- internal: the settings menu-toggle keybind, clash check runs in reverse
    hold: boolean?, -- fire callback(true) once held, callback(false) on release
    holdThreshold: number?, -- seconds to hold before it counts (default 0.2)
    callback: ((value: EnumItem | boolean) -> ())?, -- bound key on press, or true/false in hold mode
    onChanged: ((key: EnumItem) -> ())?, -- fires when the binding is changed
}

export type ColorPickerProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    color: Color3?, -- initial colour (accepts a hex string too)
    alpha: number?, -- initial alpha 0..1 (default 1, no dedicated control in this layout - set via code)
    presets: { Color3 }?, -- quick-pick swatches under the RGB row
    glow: boolean?, -- ambient glow behind the card (default true)
    forgetState: boolean?,
    callback: ((value: Color3, alpha: number) -> ())?,
}

export type GradientStop = {
    time: number,
    color: Color3,
}

export type GradientPickerProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    gradient: (ColorSequence | { Color3 } | { GradientStop })?, -- initial value
    glow: boolean?, -- ambient glow behind the card (default true)
    forgetState: boolean?,
    callback: ((value: ColorSequence) -> ())?,
}

export type HoldButtonProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    flag: string?,
    holdDuration: number?, -- seconds the fill takes to complete (default 1)
    danger: boolean?, -- tint the fill red instead of the accent colour
    locked: boolean?,
    callback: (() -> ())?,
}

export type ChangelogEntry = {
    tag: string?, -- "ADDED" | "FIXED" | "CHANGED" | "REMOVED", or any custom tag
    text: string?,
}

export type ChangelogProps = {
    name: string?, -- card title (default "Update Log")
    version: string?,
    date: string?,
    entries: { ChangelogEntry }?,
}

export type CollapsibleProps = {
    name: string?,
    icon: (string | number)?,
    expanded: boolean?, -- start open (default false)
}

export type SpacerProps = {
    height: number?, -- pixel gap (default 12)
}

export type StatProps = {
    name: string?,
    description: string?,
    icon: (string | number)?,
    tooltip: string?,
    prefix: string?,
    suffix: string?,
    value: number?,
    display: string?, -- "value" | "change"
    compact: boolean?,
    changeMode: string?, -- "percentage" | "absolute"
    changeBaseline: string?, -- "previous" | "initial"
    numberEasing: boolean?,
}

export type NotifyProps = {
    title: string?,
    content: string?,
    icon: (string | number)?,
    duration: number?,
}

export type ToastProps = {
    title: string?,
    subtitle: string?, -- optional second line
    subtitleAbove: boolean?, -- render the subtitle above the title (label-over-value)
    icon: (string | number)?, -- optional; asset id or ready image string (rbxthumb works)
    avatar: number?, -- optional user id; shows that user's headshot as a larger avatar
    minWidth: number?, -- floor the pill width; slack becomes right-hand room (content is left-aligned)
    duration: number?,
    position: "Top" | "Bottom"?,
}

export type PopupBox = {
    title: string?,
    description: string?,
    icon: (string | number)?,
}

export type PopupOption = {
    text: string?,
    style: string?, -- "neutral" (default) | "primary" | "danger"
    callback: (() -> ())?,
}

export type PopupProps = {
    title: string?,
    subtitle: string?,
    icon: (string | number)?,
    content: string?, -- a body paragraph
    boxes: { PopupBox }?, -- a list of cards (the changelog layout)
    options: { PopupOption }?, -- footer buttons; defaults to a single dismiss button
    dismissable: boolean?, -- click the dim or press Escape to close (default true)
}

-- Handles ------------------------------------------------------------------
-- Every element can be reordered within its tab.
export type Moveable = {
    MoveTo: (self: any, index: number) -> (),
    MoveToTop: (self: any) -> (),
    MoveToBottom: (self: any) -> (),
    MoveUp: (self: any) -> (),
    MoveDown: (self: any) -> (),
    -- Devlog 7: shows/hides the element at runtime, independent of tab switching or the window
    -- itself hiding - pulls it out of layout entirely rather than just fading it.
    SetVisible: (self: any, visible: boolean) -> (),
}

export type Button = Moveable & {
    locked: boolean,
    SetLocked: (self: Button, locked: boolean) -> (),
}

export type RippleButton = Moveable & {}

export type ProgressBar = Moveable & {
    value: number,
    Set: (self: ProgressBar, value: number, skipAnimation: boolean?) -> (),
}

export type ScrollHint = Moveable & {
    Set: (self: ScrollHint, text: string) -> (),
}

export type SegmentedPicker = Moveable & {
    value: string,
    Set: (self: SegmentedPicker, value: string, skipCallback: boolean?) -> (),
}

export type ShimmerLabel = Moveable & {
    text: string,
    Set: (self: ShimmerLabel, text: string) -> (),
    SetSpeed: (self: ShimmerLabel, seconds: number) -> (),
    SetSpread: (self: ShimmerLabel, fraction: number) -> (),
    SetAngle: (self: ShimmerLabel, degrees: number) -> (),
    SetTextSize: (self: ShimmerLabel, size: number) -> (),
}

export type CopyButton = Moveable & {
    text: string,
    Set: (self: CopyButton, text: string) -> (),
}

export type FlipButton = Moveable & {
    Set: (self: FlipButton, front: string?, back: string?) -> (),
}

export type Toggle = Moveable & {
    value: boolean,
    locked: boolean,
    Set: (self: Toggle, value: boolean, skipCallback: boolean?) -> (),
    SetLocked: (self: Toggle, locked: boolean) -> (),
}

export type Checkbox = Moveable & {
    value: boolean,
    Set: (self: Checkbox, value: boolean, skipCallback: boolean?) -> (),
}

export type Slider = Moveable & {
    value: number,
    Set: (self: Slider, value: number, skipCallback: boolean?) -> (),
}

export type Dropdown = Moveable & {
    value: { string }, -- always stored pruned to the current options, even single-select
    locked: boolean,
    Set: (self: Dropdown, value: string | { string }, skipCallback: boolean?) -> (),
    Reset: (self: Dropdown, skipCallback: boolean?) -> (), -- clears back to the placeholder
    SetLocked: (self: Dropdown, locked: boolean) -> (),
}

export type Input = Moveable & {
    value: string,
    Set: (self: Input, value: string, skipCallback: boolean?) -> (),
}

export type Keybind = Moveable & {
    value: EnumItem,
    Set: (self: Keybind, value: EnumItem | string, skipChanged: boolean?) -> (),
}

export type ColorPicker = Moveable & {
    value: Color3,
    alpha: number,
    Set: (self: ColorPicker, value: Color3 | string, skipCallback: boolean?) -> (),
    SetAlpha: (self: ColorPicker, alpha: number, skipCallback: boolean?) -> (),
    SetGlow: (self: ColorPicker, shown: boolean) -> (),
}

export type GradientPicker = Moveable & {
    value: ColorSequence,
    Set: (self: GradientPicker, value: (ColorSequence | { Color3 } | { GradientStop }), skipCallback: boolean?) -> (),
    SetGlow: (self: GradientPicker, shown: boolean) -> (),
}

export type Stat = Moveable & {
    value: number,
    Set: (self: Stat, value: number) -> (),
    ResetBaseline: (self: Stat, value: number?) -> (),
}

export type Section = Moveable & {}

export type Label = Moveable & {
    Set: (self: Label, text: string) -> (),
}

export type Paragraph = Moveable & {
    Set: (self: Paragraph, props: { title: string?, content: string? }) -> (),
    SetTitle: (self: Paragraph, text: string) -> (),
    SetContent: (self: Paragraph, text: string) -> (),
}

export type Divider = Moveable & {
    Set: (self: Divider, text: string) -> (),
}

export type HoldButton = Moveable & {
    locked: boolean,
    SetLocked: (self: HoldButton, locked: boolean) -> (),
}

export type Changelog = Moveable & {}

export type Spacer = Moveable & {
    height: number,
    SetHeight: (self: Spacer, height: number, animate: boolean?) -> (),
}

-- A collapsible section hosts its own nested elements through the same reduced CreateX surface
-- as a Group (see Group above) - it wraps one internally.
export type Collapsible = Moveable & {
    expanded: boolean,
    Toggle: (self: Collapsible) -> (),
    SetExpanded: (self: Collapsible, expanded: boolean) -> (),
    CreateButton: (self: Collapsible, props: ButtonProps) -> Button,
    CreateFlipButton: (self: Collapsible, props: FlipButtonProps) -> FlipButton,
    CreateCopyButton: (self: Collapsible, props: CopyButtonProps) -> CopyButton,
    CreateRippleButton: (self: Collapsible, props: RippleButtonProps) -> RippleButton,
    CreateToggle: (self: Collapsible, props: ToggleProps) -> Toggle,
    CreateSwitch: (self: Collapsible, props: ToggleProps) -> Toggle,
    CreateCheckbox: (self: Collapsible, props: CheckboxProps) -> Checkbox,
    CreateStat: (self: Collapsible, props: StatProps) -> Stat,
    CreateSlider: (self: Collapsible, props: SliderProps) -> Slider,
    CreateDropdown: (self: Collapsible, props: DropdownProps) -> Dropdown,
    CreateSection: (self: Collapsible, props: SectionProps) -> Section,
    CreateLabel: (self: Collapsible, props: LabelProps?) -> Label,
    CreateParagraph: (self: Collapsible, props: ParagraphProps?) -> Paragraph,
    CreateDivider: (self: Collapsible, props: DividerProps?) -> Divider,
    CreateGroup: (self: Collapsible, props: GroupProps?) -> Group,
}

-- Tags sit in the window's title bar and order themselves, so they aren't Moveable.
export type Tag = {
    Set: (self: Tag, props: TagProps) -> (),
    SetColor: (self: Tag, color: Color3) -> (),
    SetText: (self: Tag, text: string?) -> (),
    SetIcon: (self: Tag, icon: (string | number)?) -> (),
    Remove: (self: Tag) -> (),
}

export type Popup = {
    Close: (self: Popup) -> (),
}

-- A group lays elements along one axis and nests, so a row of columns builds a grid.
-- A row accepts the compact elements
-- (button/toggle/stat/checkbox/copybutton/flipbutton/ripplebutton) + slider; a column also
-- takes dropdown and section. Input, keybind, colorpicker, progressbar and scrollhint stay
-- tab-level for now.
export type Group = Moveable & {
    CreateButton: (self: Group, props: ButtonProps) -> Button,
    CreateFlipButton: (self: Group, props: FlipButtonProps) -> FlipButton,
    CreateCopyButton: (self: Group, props: CopyButtonProps) -> CopyButton,
    CreateRippleButton: (self: Group, props: RippleButtonProps) -> RippleButton,
    CreateToggle: (self: Group, props: ToggleProps) -> Toggle,
    CreateSwitch: (self: Group, props: ToggleProps) -> Toggle,
    CreateCheckbox: (self: Group, props: CheckboxProps) -> Checkbox,
    CreateStat: (self: Group, props: StatProps) -> Stat,
    CreateSlider: (self: Group, props: SliderProps) -> Slider,
    CreateDropdown: (self: Group, props: DropdownProps) -> Dropdown,
    CreateSection: (self: Group, props: SectionProps) -> Section,
    CreateLabel: (self: Group, props: LabelProps?) -> Label,
    CreateParagraph: (self: Group, props: ParagraphProps?) -> Paragraph,
    CreateDivider: (self: Group, props: DividerProps?) -> Divider,
    CreateGroup: (self: Group, props: GroupProps?) -> Group,
}

export type Tab = {
    CreateButton: (self: Tab, props: ButtonProps) -> Button,
    CreateFlipButton: (self: Tab, props: FlipButtonProps) -> FlipButton,
    CreateCopyButton: (self: Tab, props: CopyButtonProps) -> CopyButton,
    CreateRippleButton: (self: Tab, props: RippleButtonProps) -> RippleButton,
    CreateToggle: (self: Tab, props: ToggleProps) -> Toggle,
    CreateSwitch: (self: Tab, props: ToggleProps) -> Toggle,
    CreateCheckbox: (self: Tab, props: CheckboxProps) -> Checkbox,
    CreateSlider: (self: Tab, props: SliderProps) -> Slider,
    CreateDropdown: (self: Tab, props: DropdownProps) -> Dropdown,
    CreateInput: (self: Tab, props: InputProps) -> Input,
    CreateKeybind: (self: Tab, props: KeybindProps) -> Keybind,
    CreateColorPicker: (self: Tab, props: ColorPickerProps) -> ColorPicker,
    CreateGradientPicker: (self: Tab, props: GradientPickerProps?) -> GradientPicker,
    CreateStat: (self: Tab, props: StatProps) -> Stat,
    CreateSection: (self: Tab, props: SectionProps) -> Section,
    CreateLabel: (self: Tab, props: LabelProps?) -> Label,
    CreateParagraph: (self: Tab, props: ParagraphProps?) -> Paragraph,
    CreateDivider: (self: Tab, props: DividerProps?) -> Divider,
    CreateProgressBar: (self: Tab, props: ProgressBarProps) -> ProgressBar,
    CreateScrollHint: (self: Tab, props: ScrollHintProps?) -> ScrollHint,
    CreateSegmentedPicker: (self: Tab, props: SegmentedPickerProps?) -> SegmentedPicker,
    CreateShimmerLabel: (self: Tab, props: ShimmerLabelProps?) -> ShimmerLabel,
    CreateGroup: (self: Tab, props: GroupProps?) -> Group,
    CreateHoldButton: (self: Tab, props: HoldButtonProps?) -> HoldButton,
    CreateCollapsible: (self: Tab, props: CollapsibleProps?) -> Collapsible,
    CreateChangelog: (self: Tab, props: ChangelogProps?) -> Changelog,
    CreateSpacer: (self: Tab, props: SpacerProps?) -> Spacer,
    locked: boolean,
    SetLocked: (self: Tab, locked: boolean) -> (),
}

export type GreetingProps = {
    texts: { string }?,
    holdTime: number?, -- seconds each greeting stays fully shown (default 0.85)
    wipeTime: number?, -- duration of the closing curved wipe (default 0.7)
}

export type Window = {
    unloaded: boolean, -- true once Unload has run; the handle is spent
    CreateTab: (self: Window, props: TabProps) -> Tab,
    CreateTag: (self: Window, props: TagProps) -> Tag,
    Notify: (self: Window, props: NotifyProps) -> (),
    Toast: (self: Window, props: ToastProps) -> (),
    Popup: (self: Window, props: PopupProps) -> Popup,
    PlayGreeting: (self: Window, props: GreetingProps?) -> (),
    Show: (self: Window) -> (),
    Hide: (self: Window) -> (),
    ToggleHide: (self: Window) -> (),
    ToggleMinimise: (self: Window) -> (),
    Navigate: (self: Window, tab: string | Tab) -> (),
    ChangeTheme: (self: Window, theme: Theme) -> (),
    SetTabStyle: (self: Window, style: "white" | "accent") -> (), -- switch the shared tab pill live
    SetTabAccentColor: (self: Window, color: Color3) -> (), -- recolour the accent pill + its glow
    SetTabAccentGlow: (self: Window, shown: boolean) -> (), -- toggle the soft glow under the accent pill
    -- live font swap: "Auto" (brand font) or any built-in Roblox font name
    SetFont: (self: Window, name: string) -> (),
    -- Devlog 7 "glass window": 0 (opaque, default) to 100 (fully invisible)
    SetTransparency: (self: Window, percent: number) -> (),
    -- Devlog 7: frosts the game behind the window via a Lighting blur
    SetAcrylic: (self: Window, enabled: boolean, size: number?) -> (),
    SetLocale: (self: Window, localeId: string) -> (),
    SetTranslator: (self: Window, translator: Translator?) -> (),
    RegisterTranslations: (self: Window, translations: Translations) -> (),
    Save: (self: Window, name: string?) -> boolean,
    Load: (self: Window, name: string?) -> boolean,
    ListConfigs: (self: Window) -> { string },
    DeleteConfig: (self: Window, name: string) -> boolean,
    Unload: (self: Window) -> (),
}

export type Rayfield = {
    CreateWindow: (self: Rayfield, props: WindowProps) -> Window,
}

return {}
