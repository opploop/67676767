--!strict

-- Copyright (c) 2026 Corridon Capital
-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at https://mozilla.org/MPL/2.0/.

-- Live machine-translation engine backing locale.autoTranslate (see locale.luau's own use of
-- this). Tries Google Translate's public keyless endpoint first, then MyMemory's free API as a
-- second attempt (see tryGoogle/tryMyMemory below for why two) - no signup, no API key, works
-- the moment autoTranslate is turned on. Every result is cached forever, both in memory and on
-- disk (same Rayfield/ folder configs already live in), so a given string only ever actually
-- gets translated once per locale on a given client - every use after that (this session or a
-- later one) is a plain table read, no network involved.
--
-- Deliberately its own file rather than folded into locale.luau: locale.luau owns the
-- *resolution policy* (which source wins - dev hook, live cache, built-in table, raw text); this
-- is just one *source* it can ask, the same separation assetResolver/fontManager already keep
-- from the modules that call them.

local network = require(script.Parent.network)
local variables = require(script.Parent.variables)
local filesystem = require(script.Parent.filesystem)
local path = require(script.Parent.path)
local log = require(script.Parent.log)

local autoTranslate = {}

-- in-memory: { [locale] = { [source] = translated } }. Loaded from/flushed to disk lazily, one
-- file per locale, so a cold session only ever reads the locales it actually ends up using.
local memoryCache: { [string]: { [string]: string } } = {}
local loadedFromDisk: { [string]: boolean } = {}
-- in-flight requests, deduped by "locale|source" - a whole tab's worth of toggles built in the
-- same frame, all asking to translate their own name, fires exactly one request between them
-- instead of one each.
local pending: { [string]: boolean } = {}

local function cacheDir(): string
    return variables.fileSystemManager:getPath("Translations")
end

local function cacheFile(localeId: string): string
    return path.join(cacheDir(), path.sanitizeFile(localeId) .. ".json")
end

local function ensureLoaded(localeId: string)
    if loadedFromDisk[localeId] then
        return
    end
    loadedFromDisk[localeId] = true
    memoryCache[localeId] = memoryCache[localeId] or {}

    local file = cacheFile(localeId)
    if not filesystem.isfile(file) then
        return
    end
    local ok, contents = pcall(filesystem.readfile, file)
    if not ok or type(contents) ~= "string" then
        return
    end
    local decodeOk, parsed = pcall(variables.httpService.JSONDecode, variables.httpService, contents)
    if not decodeOk or type(parsed) ~= "table" then
        return
    end
    for source, translated in parsed :: { [string]: unknown } do
        if type(source) == "string" and type(translated) == "string" then
            memoryCache[localeId][source] = translated
        end
    end
end

local function persist(localeId: string)
    pcall(filesystem.ensureFolder, cacheDir())
    local ok, encoded = pcall(variables.httpService.JSONEncode, variables.httpService, memoryCache[localeId] or {})
    if ok and type(encoded) == "string" then
        pcall(filesystem.writefile, cacheFile(localeId), encoded)
    end
end

-- Returns a cached translation if one already exists (disk or memory) - never blocks, never
-- makes a request. This is what locale.resolve() checks first, every call.
function autoTranslate.peek(source: string, localeId: string): string?
    ensureLoaded(localeId)
    local forLocale = memoryCache[localeId]
    return forLocale and forLocale[source]
end

-- %s, %d, %-5.2f and friends need to survive the round trip untouched - swap each one for a
-- short numbered token before sending, put the real specifier back after. Google generally
-- leaves a bare %s alone, but this makes sure "%d itens" can't come back "% d itens" or
-- reordered somewhere a target language's own word order would otherwise move it.
local specifierPattern = "%%[%-%+ #0]*%d*%.?%d*[diouxXeEfgGqscp%%]"

local function protectSpecifiers(text: string): (string, { string })
    local tokens = {}
    local protectedText = text:gsub(specifierPattern, function(specifier)
        table.insert(tokens, specifier)
        return "{{" .. #tokens .. "}}"
    end)
    return protectedText, tokens
end

local function restoreSpecifiers(text: string, tokens: { string }): string
    for i, specifier in tokens do
        -- a translation can pick up stray spaces inside the braces ("{{ 1 }}") - tolerate that
        text = text:gsub("{{%s*" .. i .. "%s*}}", specifier)
    end
    return text
end

local function httpGet(url: string): string?
    local fn = network.getRequestFn()
    if fn then
        local ok, response = pcall(fn, { Url = url, Method = "GET" })
        if ok and type(response) == "table" then
            local body = (response :: any).Body
            local status = (response :: any).StatusCode
            if type(body) == "string" and #body > 0 and (type(status) ~= "number" or (status >= 200 and status < 300)) then
                return body
            end
        end
    end
    -- falls back to the plain client HTTP call - no advanced request table needed for a simple
    -- unauthenticated GET, and this exact call is what this whole project's own dev-reload
    -- workflow already relies on working.
    local ok2, body2 = pcall(function()
        return game:HttpGet(url)
    end)
    if ok2 and type(body2) == "string" and #body2 > 0 then
        return body2
    end
    return nil
end

-- Two providers, tried in order, both free and keyless. Google generally wins on quality and is
-- tried first, but its answer depends on the executor's outbound IP not already being flagged by
-- Google's own abuse detection - confirmed hitting exactly that live while building this (a clean
-- 429 "Sorry..." page, no account to appeal it with). MyMemory is the second attempt: a genuinely
-- documented free API, lower quality on long sentences (it leans on a translation-memory database
-- more than pure MT) but perfectly fine for short UI copy, and it's what actually answered during
-- that same test. Only once *both* fail does resolve() fall back to the built-in/registered table.
local function tryGoogle(protectedText: string, targetLang: string): string?
    local url = ("https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=%s&dt=t&q=%s")
        :format(variables.httpService:UrlEncode(targetLang), variables.httpService:UrlEncode(protectedText))
    local body = httpGet(url)
    if not body then
        return nil
    end
    -- response shape: [[[translatedChunk, sourceChunk, ...], ...], ...] - a long sentence comes
    -- back split into several chunks that need stitching back together.
    local ok, decoded = pcall(variables.httpService.JSONDecode, variables.httpService, body)
    if not ok or type(decoded) ~= "table" or type(decoded[1]) ~= "table" then
        return nil
    end
    local parts = {}
    for _, chunk in decoded[1] :: { any } do
        if type(chunk) == "table" and type(chunk[1]) == "string" then
            table.insert(parts, chunk[1])
        end
    end
    if #parts == 0 then
        return nil
    end
    return table.concat(parts)
end

local function tryMyMemory(protectedText: string, targetLang: string): string?
    -- MyMemory wants an explicit source language rather than an auto-detect flag - every source
    -- string in this project is written in English (see locale.luau's own header comment: "English
    -- is canonical"), so that's a safe fixed value rather than something worth detecting.
    local url = ("https://api.mymemory.translated.net/get?q=%s&langpair=en|%s")
        :format(variables.httpService:UrlEncode(protectedText), variables.httpService:UrlEncode(targetLang))
    local body = httpGet(url)
    if not body then
        return nil
    end
    local ok, decoded = pcall(variables.httpService.JSONDecode, variables.httpService, body)
    if not ok or type(decoded) ~= "table" then
        return nil
    end
    local data = (decoded :: any).responseData
    if type(data) ~= "table" or type(data.translatedText) ~= "string" or data.translatedText == "" then
        return nil
    end
    return data.translatedText
end

-- Both providers accept a region-qualified code ("pt-BR") and it matters for quality, not just
-- pickiness - live-caught requesting the same word both ways: a bare "pt" came back "Secções"
-- (European Portuguese), "pt-BR" came back "Seções" (Brazilian) for the exact same input. Roblox
-- locale ids are already lowercase-hyphenated ("pt-br"); this just fixes the region's casing to
-- what the APIs expect. Falls back to the bare language when there's no region at all.
local function apiLangCode(localeId: string): string
    local lang, region = string.match(localeId, "^(%a+)-(%a+)$")
    if lang and region then
        return lang .. "-" .. string.upper(region)
    end
    return string.match(localeId, "^(%a+)") or localeId
end

-- Fires (or joins) a live translation request. Never yields the caller - the actual HTTP calls
-- run on their own thread; `onDone()` (if given) fires once a result lands in the cache,
-- success or not, so a caller can re-resolve whatever was showing the fallback text meanwhile.
function autoTranslate.request(source: string, localeId: string, onDone: (() -> ())?)
    ensureLoaded(localeId)
    if memoryCache[localeId] and memoryCache[localeId][source] then
        return -- already cached, nothing to do
    end
    local key = localeId .. "|" .. source
    if pending[key] then
        return -- already in flight - the call that started it will notify everyone once it lands
    end
    pending[key] = true

    task.spawn(function()
        local protectedText, tokens = protectSpecifiers(source)
        local targetLang = apiLangCode(localeId)

        local translated = tryGoogle(protectedText, targetLang)
        local usedFallbackProvider = false
        if not translated then
            translated = tryMyMemory(protectedText, targetLang)
            usedFallbackProvider = translated ~= nil
        end

        pending[key] = nil

        if translated and translated ~= "" then
            translated = restoreSpecifiers(translated, tokens)
            memoryCache[localeId] = memoryCache[localeId] or {}
            memoryCache[localeId][source] = translated
            persist(localeId)
            if usedFallbackProvider then
                log.print("Rayfield: auto-translate used the MyMemory fallback for '" .. localeId .. "' (Google unavailable).")
            end
            if onDone then
                onDone()
            end
        else
            log.warn(
                "Rayfield: auto-translate couldn't reach either provider for locale '"
                    .. localeId
                    .. "' - falling back to the built-in table/source text."
            )
        end
    end)
end

return autoTranslate
