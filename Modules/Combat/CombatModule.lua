--[[
    Copyright (C) 2023 GurliGebis

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
]]

local BattlePetCompletionist = LibStub("AceAddon-3.0"):GetAddon("BattlePetCompletionist")
local CombatModule = BattlePetCompletionist:NewModule("CombatModule", "AceEvent-3.0", "AceComm-3.0")
local ConfigModule = BattlePetCompletionist:GetModule("ConfigModule")
local DataModule = BattlePetCompletionist:GetModule("DataModule")
local AceSerializer = LibStub("AceSerializer-3.0")

local messagePrefixes = {
    ANNOUNCE_PETS = "BPC_ANNOUNCE",
    I_NEED_PETS   = "BPC_INEEDPETS",
    OFFER_PETS    = "BPC_OFFERPETS",
    ACCEPT_OFFER  = "BPC_ACCEPTOFFER",
    DECLINE_OFFER = "BPC_DECLINEOFFER",
    FORFEIT       = "BPC_FORFEIT"
}

local offerSentTo = ""

function CombatModule:OnEnable()
    self:RegisterEvent("PET_BATTLE_OPENING_START", "BattleHasStarted")

    self:RegisterComm(messagePrefixes.ANNOUNCE_PETS, "HaFOnReceivedAnnounce")
    self:RegisterComm(messagePrefixes.I_NEED_PETS, "HaFOnReceivedINeedPets")
    self:RegisterComm(messagePrefixes.OFFER_PETS, "HaFOnReceivedOfferPets")
    self:RegisterComm(messagePrefixes.ACCEPT_OFFER, "HaFOnReceivedAcceptOffer")
    self:RegisterComm(messagePrefixes.DECLINE_OFFER, "HaFOnReceivedDeclineOffer")
end

local function CanWeFindPlayerPosition()
    local mapId = C_Map.GetBestMapForUnit("player")
    local position = C_Map.GetPlayerMapPosition(mapId, "player")

    -- In some cases, we cannot get the player position, so there is no coordinates to share.
    return position ~= nil
end

function CombatModule:BattleHasStarted()
    local combatMode = ConfigModule:GetCombatMode()

    if combatMode == "HAF" then
        -- Help a Friend is enabled, so we call that startup function.
        self:HafBattleHasStarted()
    elseif combatMode == "FORFEIT" then
        -- Forfeit is enabled, so we call that startup function instead.
        self:ForfeitBattleHasStarted()
    else
        -- Combat mode is disabled, so nothing to do.
        return
    end
end

function CombatModule:HafBattleHasStarted()
    if TomTom == nil then
        -- TomTom is required for this functionality to work.
        return
    end

    if CanWeFindPlayerPosition() == false then
        -- We are inside an instance (or the WoD garrison), so we cannot get our position.
        -- This means that we have nothing to share, so no need to continue.
        return
    end

    if DataModule:CanWeCapturePets() == false then
        -- We cannot capture any pets in this battle, so nothing to share.
        return
    end

    local notOwnedPets, ownedPets = DataModule.GetEnemyPetsInBattle()

    if (#notOwnedPets > 0) then
        -- There are one or more uncollected pets, so we shouldn't do anything.
        -- We prioritize ourselves first.
        return
    end

    -- If we end up here, the "Help a Friend" setting is enabled, we are in a pet battle, and we have already captured all the pets found.
    -- So we announce in the party addon channel, what we have, in case someone might need anything.
    self:SendCommMessage(messagePrefixes.ANNOUNCE_PETS, AceSerializer:Serialize(ownedPets), "PARTY")
end

function CombatModule:ForfeitBattleHasStarted()
    if DataModule:CanWeCapturePets() == false then
        -- We cannot capture any pets in this battle, so we shouldn't ask for forfeit.
        return
    end
    
    local notOwnedPets, ownedPets = DataModule.GetEnemyPetsInBattle()
    local forfeitThreshold = ConfigModule:GetForfeitThreshold()

    if (#notOwnedPets > 0) then
        -- First we see if there is any not owned pets - if there are, we shouldn't be asking the user.
        return
    end

    -- Okay, so all pets we are against is already known, so now we go through them one by one.
    -- Then, for each of them, we compare to the best one we already have.
    -- If there is an upgrade, we return, since we shouldn't ask then user then.
    -- If no of the pets are better, we ask the user if they want to forfeit.

    local upgradeFound = false

    for _, petInfo in ipairs(ownedPets) do
        local speciesId = petInfo[1]
        local breedQuality = petInfo[2]

        local myPets = DataModule:GetOwnedPets(speciesId)

        local highestOwnedQuality = 0

        -- Find the highest quality of the pet that we own.
        for _, myPetInfo in ipairs(myPets) do
            if myPetInfo[2] > highestOwnedQuality then
                highestOwnedQuality = myPetInfo[2]
            end
        end

        -- Is the found pet higher quality that our currently highest owned pet?
        if breedQuality > highestOwnedQuality then
            -- Now we have to compare with our threshold, since for example, we might be seeing an Uncommon version, but have Rare as our threshold.
            if forfeitThreshold == "BLUE" and breedQuality >= 4 then
                upgradeFound = true
            elseif forfeitThreshold == "GREEN" and breedQuality >= 3 then
                upgradeFound = true
            elseif forfeitThreshold == "WHITE" and breedQuality >= 2 then
                upgradeFound = true
            elseif forfeitThreshold == "GREY" and breedQuality >= 1 then
                upgradeFound = true
            end
        end
    end

    if upgradeFound then
        return
    end

    local dialogMessage = "There are no pet upgrades available (or they are below the threshold)|n|nWould you like to forfeit?"
    _G.StaticPopupDialogs[messagePrefixes.FORFEIT] = {
        text = dialogMessage,
        OnAccept = function()
            C_PetBattles.ForfeitGame()
        end,

        button1 = _G.QUIT,
        button2 = _G.NO
    }

    _G.StaticPopup_Show(messagePrefixes.FORFEIT)
end

function CombatModule:HaFOnReceivedAnnounce(_, msg, _, sender)
    local myName = UnitName("player")

    if sender == myName then
        return
    end

    local success, pets = AceSerializer:Deserialize(msg)

    if success == false then
        return
    end

    -- We received an announce from a party member.
    -- We check if the pets they have found are already captured by us.
    local notOwnedPets = {}

    for i = 1, #pets do
        local speciesId = pets[i][1]

        if DataModule:GetOwnedPets(speciesId) == nil then
            table.insert(notOwnedPets, speciesId)
        end
    end

    if #notOwnedPets == 0 then
        -- We have all the pets they have found, so we don't reply.
        return
    end

    -- The sender is in a battle with some pets, and we are missing them, so we tell the sender.
    self:SendCommMessage(messagePrefixes.I_NEED_PETS, AceSerializer:Serialize(notOwnedPets), "WHISPER", sender)
end

function CombatModule:HaFOnReceivedINeedPets(_, msg, _, sender)
    local myName = UnitName("player")

    if sender == myName then
        -- We should never get this from ourselves, but just in case it might happen, we handle it.
        return
    end

    local success, pets = AceSerializer:Deserialize(msg)

    if success == false then
        return
    end

    -- Someone in our party has reported that they are missing some of the pets - first we find the names of the pets.
    local petNames = {}

    for i = 1, #pets do
        local speciesName = C_PetJournal.GetPetInfoBySpeciesID(pets[i])
        table.insert(petNames, speciesName)
    end

    -- Now we find our own position.
    local mapId = C_Map.GetBestMapForUnit("player")
    local position = C_Map.GetPlayerMapPosition(mapId, "player")
    local x, y = position:GetXY()

    local message = {
        ["mapId"] = mapId,
        ["mapX"] = string.format("%.2f", x * 100),
        ["mapY"] = string.format("%.2f", y * 100),
        ["petNames"] = petNames
    }

    local dialogMessage = "Someone (" .. sender .. ") in your party needs one or more pets you are battling.|n|nDo you want to offer them these pets and send your location?|n|nNeeded pets: " .. table.concat(petNames, ", ")

    -- Ask the player if they want to notify the party member.
    _G.StaticPopupDialogs[messagePrefixes.I_NEED_PETS] = {
        text = dialogMessage,
        OnAccept = function()
            -- We do, so we store their name and sent the offer.
            offerSentTo = sender
            self:SendCommMessage(messagePrefixes.OFFER_PETS, AceSerializer:Serialize(message), "WHISPER", sender)
        end,

        timeout = 10,
        button1 = _G.YES,
        button2 = _G.NO
    }

    _G.StaticPopup_Show(messagePrefixes.I_NEED_PETS)
end

function CombatModule:HaFOnReceivedOfferPets(_, msg, _, sender)
    local myName = UnitName("player")

    if sender == myName then
        -- We should never get this from ourselves, but just in case it might happen, we handle it.
        return
    end

    local success, message = AceSerializer:Deserialize(msg)

    if success == false then
        return
    end

    -- We have received an offer for some pets from a party member.
    -- First we find out which map the user is on and ask the player if they want the pets.
    local mapInfo = C_Map.GetMapInfo(tonumber(message["mapId"]))
    local dialogMessage = "Someone (" .. sender .. " - in zone: " .. mapInfo["name"] .. ") in your party is offering you the following battle pets.|n|nBy clicking Accept, a TomTom waypoint will be created, and a notifaction will be sent.|n|nNeeded pets: " .. table.concat(message["petNames"], ", ")

    _G.StaticPopupDialogs[messagePrefixes.OFFER_PETS] = {
        text = dialogMessage,
        OnAccept = function()
            -- We have accepted the offer, so we create a TomTom waypoint
            local icon = "Interface\\icons\\inv_pet_achievement_captureawildpet"

            local options = {
                title = "Battle Pet Completionist friend - " .. sender,
                minimap_icon = icon,
                worldmap_icon = icon
            }

            TomTom:AddWaypoint(tonumber(message["mapId"]), tonumber(message["mapX"]) / 100, tonumber(message["mapY"] / 100), options)

            -- And send the accept message.
            self:SendCommMessage(messagePrefixes.ACCEPT_OFFER, AceSerializer.Serialize(message), "WHISPER", sender)
        end,
        OnCancel = function()
            -- We have declined, so we send the decline message.
            self:SendCommMessage(messagePrefixes.DECLINE_OFFER, AceSerializer.Serialize(message), "WHISPER", sender)
        end,

        button1 = _G.ACCEPT,
        button2 = _G.DECLINE
    }

    _G.StaticPopup_Show(messagePrefixes.OFFER_PETS)
end

function CombatModule:HaFOnReceivedAcceptOffer(_, msg, _, sender)
    local myName = UnitName("player")

    if sender == myName then
        -- We should never get this from ourselves, but just in case it might happen, we handle it.
        return
    end

    if sender ~= offerSentTo then
        -- Someone is sending us an accept, but we haven't send them an offer, so we just return.
        return
    end

    local success = AceSerializer:Deserialize(msg)

    if success == false then
        return
    end

    -- The other player accepted our offer.
    offerSentTo = ""
    local dialogMessage = sender .. " has accepted your offer|n|nPlease wait for them before forfeiting."

    _G.StaticPopupDialogs[messagePrefixes.ACCEPT_OFFER] = {
        text = dialogMessage,

        timeout = 10,
        button1 = _G.OKAY
    }

    _G.StaticPopup_Show(messagePrefixes.ACCEPT_OFFER)
end

function CombatModule:HaFOnReceivedDeclineOffer(_, msg, _, sender)
    local myName = UnitName("player")

    if sender == myName then
        -- We should never get this from ourselves, but just in case it might happen, we handle it.
        return
    end

    if sender ~= offerSentTo then
        -- Someone is sending us an accept, but we haven't send them an offer, so we just return.
        return
    end

    local success = AceSerializer:Deserialize(msg)

    if success == false then
        return
    end

    -- The other player declined our offer.
    offerSentTo = ""
    local dialogMessage = sender .. " has declined your offer."

    _G.StaticPopupDialogs[messagePrefixes.DECLINE_OFFER] = {
        text = dialogMessage,

        timeout = 10,
        button1 = _G.OKAY
    }

    _G.StaticPopup_Show(messagePrefixes.DECLINE_OFFER)
end
