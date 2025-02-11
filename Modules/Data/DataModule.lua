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

BattlePetCompletionist = LibStub("AceAddon-3.0"):GetAddon("BattlePetCompletionist")
DataModule = BattlePetCompletionist:NewModule("DataModule")
ConfigModule = BattlePetCompletionist:GetModule("ConfigModule")
LibPetJournal = LibStub('LibPetJournal-2.0')

local function DoesPetMatchSourceFilters(speciesId)
    local petSource = DataModule:GetPetSource(speciesId)

    local enabledSources = ConfigModule:GetMapPinSources()

    for _, v in ipairs(enabledSources) do
        if v == petSource then
            return true
        end
    end

    return false
end

function DataModule:GetPetsInMap(mapId)
    return DataModule.PetData[mapId]
end

function DataModule:ShouldPetBeShown(speciesId)
    if ConfigModule.AceDB.profile.mapPinsToInclude == "T1ALL" then
        if DoesPetMatchSourceFilters(speciesId) then
            return true
        else
            return false
        end
    end

    if ConfigModule.AceDB.profile.mapPinsToInclude == "T4NONE" then
        return false
    end

    for _, petId in LibPetJournal:IteratePetIDs() do
        local speciesIdFromJournal, _, _, _, _, _, _, petName = C_PetJournal.GetPetInfoByPetID(petId)

        if speciesIdFromJournal == speciesId then
            if ConfigModule.AceDB.profile.mapPinsToInclude == "T2MISSING" then
                return false
            end

            if ConfigModule.AceDB.profile.mapPinsToInclude == "T3NOTRARE" then
                local quality = select(5, C_PetJournal.GetPetStats(petId))

                if (quality >= 4) then
                    -- quality 4 is Rare / Blue
                    return false
                end
            end

            if ConfigModule.AceDB.profile.mapPinsToInclude == "T5NOTMAXCOLLECTED" then
                numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesId)
                return numCollected < limit;
            end

            if ConfigModule.AceDB.profile.mapPinsToInclude == "T6NAMEFILTER" then
                if ConfigModule.AceDB.profile.mapPinsFilter == "" then
                    -- Name filter has been selected, but the filter text box is empty
                    -- So we just return true for all pets.
                    return true
                end
                
                -- Since string.find is case sensitive, we convert everything to lowercase first.
                local loweredTextBoxValue = string.lower(ConfigModule.AceDB.profile.mapPinsFilter)
                local loweredPetName = string.lower(petName)

                return string.find(loweredPetName, loweredTextBoxValue)
            end
        end
    end

    if DoesPetMatchSourceFilters(speciesId) then
        return true
    else
        return false
    end
end

function DataModule:GetOwnedPets(speciesId)
    local ownedPets = {}
    local anyPetsFound = false

    for _, petId in LibPetJournal:IteratePetIDs() do
        local speciesIdFromJournal, _, petLevel = C_PetJournal.GetPetInfoByPetID(petId)

        if speciesIdFromJournal == speciesId then
            local quality = select(5, C_PetJournal.GetPetStats(petId))

            table.insert(ownedPets, { petLevel, quality })
            anyPetsFound = true
        end
    end

    if anyPetsFound then
        return ownedPets
    else
        return nil
    end
end

function DataModule:GetEnemyPetsInBattle()
    local numberOfEnemyPets = C_PetBattles.GetNumPets(Enum.BattlePetOwner.Enemy)
    local foundNotOwnedPets = {}
    local foundOwnedPets = {}

    for i = 1, numberOfEnemyPets do
        local speciesId = C_PetBattles.GetPetSpeciesID(Enum.BattlePetOwner.Enemy, i)
        local breedQuality = C_PetBattles.GetBreedQuality(Enum.BattlePetOwner.Enemy, i)
        local ownedPets = DataModule:GetOwnedPets(speciesId)

        if (ownedPets == nil) then
            table.insert(foundNotOwnedPets, { speciesId, breedQuality })
        else
            table.insert(foundOwnedPets, { speciesId, breedQuality })
        end
    end

    return foundNotOwnedPets, foundOwnedPets
end

function DataModule:CanWeCapturePets()
    local isNpcControlled = C_PetBattles.IsPlayerNPC(Enum.BattlePetOwner.Enemy)

    if isNpcControlled == false then
        -- It is a PvP pet battle, you cannot capture pets here.
        return false
    end

    local isWildBattle = C_PetBattles.IsWildBattle()

    if isWildBattle == false then
        -- It is a quest or something else like that - you cannot capture pets here.
        return false
    end

    local numberOfEnemyPets = C_PetBattles.GetNumPets(Enum.BattlePetOwner.Enemy)

    for i = 1, numberOfEnemyPets do
        local speciesId = C_PetBattles.GetPetSpeciesID(Enum.BattlePetOwner.Enemy, i)
        local obtainable = select(11, C_PetJournal.GetPetInfoBySpeciesID(speciesId))

        -- We can end here, but without any captureable pets, so if we see at least one that can be captured, we return true.
        if (obtainable == true) then
            return true
        end
    end

    return false
end

function DataModule:GetPetSource(speciesId)
    local _, _, _, _, tooltipSource = C_PetJournal.GetPetInfoBySpeciesID(speciesId)
    local index = string.find(tooltipSource, ":")
    local source = ""

    if index then
        source = string.sub(tooltipSource, 1, index - 1)
    end

    if     string.find(source, BATTLE_PET_SOURCE_1) ~= nil then return BATTLE_PET_SOURCE_1
    elseif string.find(source, BATTLE_PET_SOURCE_2) ~= nil then return BATTLE_PET_SOURCE_2
    elseif string.find(source, BATTLE_PET_SOURCE_3) ~= nil then return BATTLE_PET_SOURCE_3
    elseif string.find(source, BATTLE_PET_SOURCE_4) ~= nil then return BATTLE_PET_SOURCE_4
    elseif string.find(source, BATTLE_PET_SOURCE_5) ~= nil then return BATTLE_PET_SOURCE_5
    elseif string.find(source, BATTLE_PET_SOURCE_6) ~= nil then return BATTLE_PET_SOURCE_6
    elseif string.find(source, BATTLE_PET_SOURCE_7) ~= nil then return BATTLE_PET_SOURCE_7
    elseif string.find(source, BATTLE_PET_SOURCE_8) ~= nil then return BATTLE_PET_SOURCE_8
    elseif string.find(source, BATTLE_PET_SOURCE_9) ~= nil then return BATTLE_PET_SOURCE_9
    elseif string.find(source, BATTLE_PET_SOURCE_10) ~= nil then return BATTLE_PET_SOURCE_10
    elseif string.find(source, BATTLE_PET_SOURCE_11) ~= nil then return BATTLE_PET_SOURCE_11
    else return nil end
end
