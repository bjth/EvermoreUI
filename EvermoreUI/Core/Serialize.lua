if EV_BLOCKED then return end
--------------------------------------------------------------------------------
--  Serialize.lua
--  Profile strings: a settings table in, one line of text out, and back
--  again. Same idea as every other addon's import/export box, so a profile
--  can be shared, kept as a backup, or pasted back after Forever's beta
--  loses its SavedVariables.
--
--  Three steps, all ours (no libraries):
--
--    Pack    the table into a length-prefixed byte string. Nothing is
--            escaped or quoted, so any text, key or number survives intact.
--    Squash  LZW, 12-bit codes packed into bytes. Settings repeat
--            themselves ("enabled", "spacing", "RIGHT"), so this typically
--            takes about two thirds off.
--    Encode  base64 with a prefix and a checksum: EVUI1!<data>#<sum>
--
--  Unpack refuses anything it doesn't recognise rather than erroring, so a
--  half-copied string gives "that doesn't look like a profile string".
--------------------------------------------------------------------------------
local EV = EvermoreUI
local S = {}
EV.Serialize = S

local floor, concat, byte, char, sub = math.floor, table.concat, string.byte, string.char, string.sub
local PREFIX = "EVUI1!"

--------------------------------------------------------------------------------
--  Pack: table <-> byte string
--------------------------------------------------------------------------------
local function PackValue(v, out, depth)
    local t = type(v)
    if depth > 24 then out[#out + 1] = "N"; return end
    if v == nil then
        out[#out + 1] = "N"
    elseif t == "boolean" then
        out[#out + 1] = v and "T" or "F"
    elseif t == "number" then
        out[#out + 1] = "n" .. ("%.17g"):format(v) .. "~"
    elseif t == "string" then
        out[#out + 1] = "s" .. #v .. "~" .. v
    elseif t == "table" then
        out[#out + 1] = "{"
        for k, val in pairs(v) do
            local kt = type(k)
            if (kt == "string" or kt == "number") and type(val) ~= "function" then
                PackValue(k, out, depth + 1)
                PackValue(val, out, depth + 1)
            end
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "N"
    end
end

function S.Pack(tbl)
    local out = {}
    PackValue(tbl, out, 0)
    return concat(out)
end

local function UnpackValue(s, i)
    local tag = sub(s, i, i)
    if tag == "" then return nil, nil, "truncated" end
    i = i + 1
    if tag == "N" then return nil, i end
    if tag == "T" then return true, i end
    if tag == "F" then return false, i end
    if tag == "n" or tag == "s" then
        local stop = s:find("~", i, true)
        if not stop then return nil, nil, "truncated number or string" end
        local head = sub(s, i, stop - 1)
        if tag == "n" then
            local num = tonumber(head)
            if not num then return nil, nil, "bad number" end
            return num, stop + 1
        end
        local len = tonumber(head)
        if not len or len < 0 then return nil, nil, "bad string length" end
        local from = stop + 1
        if #s < from + len - 1 then return nil, nil, "truncated string" end
        return sub(s, from, from + len - 1), from + len
    end
    if tag == "{" then
        local t = {}
        while true do
            local peek = sub(s, i, i)
            if peek == "}" then return t, i + 1 end
            if peek == "" then return nil, nil, "unclosed table" end
            local k, ni, err = UnpackValue(s, i)
            if err then return nil, nil, err end
            local v; v, ni, err = UnpackValue(s, ni)
            if err then return nil, nil, err end
            if k ~= nil then t[k] = v end
            i = ni
        end
    end
    return nil, nil, "bad value"
end

function S.Unpack(s)
    local v, _, err = UnpackValue(s, 1)
    if err then return nil, err end
    return v
end

--------------------------------------------------------------------------------
--  Squash: LZW, codes widening from 9 to 14 bits as the dictionary fills
--------------------------------------------------------------------------------
local MAX_BITS = 14
local MAX_CODE = 2 ^ MAX_BITS - 1

local function Squash(input)
    local dict, next_code, width = {}, 256, 9
    local out, bits, nbits = {}, 0, 0
    local function emit(code)
        bits = bits * (2 ^ width) + code
        nbits = nbits + width
        while nbits >= 8 do
            nbits = nbits - 8
            local b = floor(bits / (2 ^ nbits))
            bits = bits - b * (2 ^ nbits)
            out[#out + 1] = char(b)
        end
    end
    local w = ""
    for i = 1, #input do
        local c = sub(input, i, i)
        local wc = w .. c
        if #wc == 1 or dict[wc] then
            w = wc
        else
            emit(#w == 1 and byte(w) or dict[w])
            if next_code <= MAX_CODE then
                dict[wc] = next_code
                next_code = next_code + 1
                if next_code == 2 ^ width and width < MAX_BITS then width = width + 1 end
            end
            w = c
        end
    end
    if w ~= "" then emit(#w == 1 and byte(w) or dict[w]) end
    if nbits > 0 then out[#out + 1] = char(floor(bits * (2 ^ (8 - nbits))) % 256) end
    return concat(out)
end

local function Unsquash(input)
    local dict, next_code, width = {}, 256, 9
    local out = {}
    local bits, nbits, pos = 0, 0, 1
    local function read()
        while nbits < width do
            if pos > #input then return nil end
            bits = bits * 256 + byte(input, pos)
            pos = pos + 1
            nbits = nbits + 8
        end
        nbits = nbits - width
        local code = floor(bits / (2 ^ nbits))
        bits = bits - code * (2 ^ nbits)
        return code
    end
    local function entry(code)
        if code < 256 then return char(code) end
        return dict[code]
    end
    local prev = read()
    if not prev then return "" end
    local first = entry(prev)
    if not first then return nil, "corrupt data" end
    out[#out + 1] = first
    while true do
        local code = read()
        if not code then break end
        local cur = entry(code)
        if not cur then
            local p = entry(prev)
            if not p then return nil, "corrupt data" end
            cur = p .. sub(p, 1, 1)
        end
        out[#out + 1] = cur
        if next_code <= MAX_CODE then
            local p = entry(prev)
            if not p then return nil, "corrupt data" end
            dict[next_code] = p .. sub(cur, 1, 1)
            next_code = next_code + 1
            -- The decoder is always one entry behind, so it widens a step early.
            if next_code + 1 == 2 ^ width and width < MAX_BITS then width = width + 1 end
        end
        prev = code
    end
    return concat(out)
end

--------------------------------------------------------------------------------
--  Encode: base64
--------------------------------------------------------------------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, #B64 do B64R[sub(B64, i, i)] = i - 1 end

local function ToBase64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = byte(data, i), byte(data, i + 1), byte(data, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = floor(n / 262144) % 64
        local c2 = floor(n / 4096) % 64
        local c3 = floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = sub(B64, c1 + 1, c1 + 1) .. sub(B64, c2 + 1, c2 + 1)
            .. (b and sub(B64, c3 + 1, c3 + 1) or "=") .. (c and sub(B64, c4 + 1, c4 + 1) or "=")
    end
    return concat(out)
end

local function FromBase64(text)
    text = text:gsub("[^A-Za-z0-9+/=]", "")
    local out = {}
    for i = 1, #text, 4 do
        local c1, c2 = B64R[sub(text, i, i)], B64R[sub(text, i + 1, i + 1)]
        local s3, s4 = sub(text, i + 2, i + 2), sub(text, i + 3, i + 3)
        if not (c1 and c2) then return nil, "bad characters" end
        local c3, c4 = B64R[s3], B64R[s4]
        local n = c1 * 262144 + c2 * 4096 + (c3 or 0) * 64 + (c4 or 0)
        out[#out + 1] = char(floor(n / 65536) % 256)
        if s3 ~= "=" and s3 ~= "" then out[#out + 1] = char(floor(n / 256) % 256) end
        if s4 ~= "=" and s4 ~= "" then out[#out + 1] = char(n % 256) end
    end
    return concat(out)
end

local function Checksum(s)
    local sum = 5381
    for i = 1, #s do sum = (sum * 33 + byte(s, i)) % 4294967296 end
    return ("%x"):format(sum)
end

--------------------------------------------------------------------------------
--  The two calls everything else uses
--------------------------------------------------------------------------------
--- Table to profile string.
function S.Encode(tbl)
    if type(tbl) ~= "table" then return nil, "nothing to export" end
    local packed = S.Pack(tbl)
    local body = ToBase64(Squash(packed))
    return PREFIX .. body .. "#" .. Checksum(packed)
end

--- Profile string to table, or nil and a reason.
function S.Decode(text)
    if type(text) ~= "string" then return nil, "nothing pasted" end
    text = text:gsub("%s+", "")
    if sub(text, 1, #PREFIX) ~= PREFIX then return nil, "that doesn't look like an EvermoreUI profile string" end
    local body, sum = text:match("^" .. PREFIX .. "([^#]*)#(%x+)$")
    if not body then return nil, "the string looks cut short" end
    local raw, err = FromBase64(body)
    if not raw then return nil, err end
    local packed; packed, err = Unsquash(raw)
    if not packed then return nil, err or "corrupt data" end
    if Checksum(packed) ~= sum then return nil, "the string is damaged (checksum)" end
    local tbl; tbl, err = S.Unpack(packed)
    if type(tbl) ~= "table" then return nil, err or "no settings in that string" end
    return tbl
end
