-- Saved by UniversalSynSaveInstance (Join to Copy Games) https://discord.gg/wx4ThpAsmw

-- Decompiled with Potassium's decompiler.

local Players = game:GetService("Players");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local LocalPlayer = Players.LocalPlayer;
local FormatModule = require(ReplicatedStorage:WaitForChild("FormatModule"));
local RebirthDefinitions = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("RebirthDefinitions"));
local Money = script.Parent:WaitForChild("Money");
local FriendsMulti = script.Parent:WaitForChild("FriendsMulti");
local VIPMulti = script.Parent:WaitForChild("VIPMulti");
local u1 = {};
local u2 = {};

for _, child in ipairs(script.Parent:GetChildren()) do
    if child:IsA("TextLabel") and child.Name == "RebirthMulti" then
        table.insert(u2, child);
    elseif child:IsA("TextLabel") and child.Name == "RobuxMulti" then
        table.insert(u1, child);
    end;
end;

local function formatMoney(p3) -- Line: 20
    -- upvalues: FormatModule (copy)
    return "$" .. FormatModule:AbbreviateNumbers(p3);
end;

local Money2 = LocalPlayer:WaitForChild("Money");
local Rebirths = LocalPlayer:WaitForChild("Rebirths");
local FriendsMultiplier = LocalPlayer:WaitForChild("FriendsMultiplier");
local VIP = LocalPlayer:WaitForChild("VIP");
local RobuxMultiplier = LocalPlayer:WaitForChild("Upgrades"):WaitForChild("RobuxMultiplier");

if not Money2:IsA("NumberValue") then
    warn("[MoneyController] Player.Money must be a NumberValue");

    return;
end;

local function formatMultiplier(p4) -- Line: 35
    local v5 = tonumber(p4) or 1;

    if v5 == math.floor(v5) then
        local v6 = math.floor(v5);

        return tostring(v6);
    end;

    local v7 = string.format("%.2f", v5);
    local v8 = string.gsub(v7, "0+$", "");

    return string.gsub(v8, "%.$", "");
end;

local function updateMultipliers() -- Line: 50
    -- upvalues: RebirthDefinitions (copy), Rebirths (copy), RobuxMultiplier (copy), VIP (copy), u2 (copy), formatMultiplier (copy), FriendsMulti (copy), FriendsMultiplier (copy), VIPMulti (copy), u1 (copy)
    local v9 = RebirthDefinitions:GetMultiplier(Rebirths.Value);
    local v10 = math.floor(RobuxMultiplier.Value);
    local v11 = 2 ^ math.clamp(v10, 0, 15);
    local v12 = VIP.Value and 1.25 or 1;

    for _, v in ipairs(u2) do
        v.Text = "x" .. formatMultiplier(v9);
    end;

    FriendsMulti.Text = "x" .. formatMultiplier(FriendsMultiplier.Value);
    VIPMulti.Text = "x" .. formatMultiplier(v12);

    for _, v in ipairs(u1) do
        v.Text = "x" .. formatMultiplier(v11);
    end;
end;

Money.Text = "$" .. FormatModule:AbbreviateNumbers(Money2.Value);
updateMultipliers();
Money2:GetPropertyChangedSignal("Value"):Connect(function() -- Line: 46, Name: updateMoney
    -- upvalues: Money (copy), Money2 (copy), FormatModule (copy)
    Money.Text = "$" .. FormatModule:AbbreviateNumbers(Money2.Value);
end);
Rebirths:GetPropertyChangedSignal("Value"):Connect(updateMultipliers);
RobuxMultiplier:GetPropertyChangedSignal("Value"):Connect(updateMultipliers);
FriendsMultiplier:GetPropertyChangedSignal("Value"):Connect(updateMultipliers);
VIP:GetPropertyChangedSignal("Value"):Connect(updateMultipliers);
