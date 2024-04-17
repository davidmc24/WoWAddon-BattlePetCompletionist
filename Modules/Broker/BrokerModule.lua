local BattlePetCompletionist = LibStub("AceAddon-3.0"):GetAddon("BattlePetCompletionist")
local BrokerModule = BattlePetCompletionist:NewModule("BrokerModule", "AceEvent-3.0")
local DataModule = BattlePetCompletionist:GetModule("DataModule")
local LibDataBroker = LibStub("LibDataBroker-1.1")
local LibPetJournal = LibStub("LibPetJournal-2.0")

function BrokerModule:GetDataObjectName()
    return BattlePetCompletionist:GetName()
end

-- Also used by MinimapModule
function BrokerModule:GetDataObject()
    return self.dataSource
end

function BrokerModule:RegisterEventHandlers()
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "RefreshData")
    LibPetJournal.RegisterCallback(self, "PetListUpdated", "RefreshData")
end

function BrokerModule:GetZonePetData()
    local mapId = C_Map.GetBestMapForUnit("player")
    return DataModule:GetPetsInMap(mapId) or {}
end

function BrokerModule:OnInitialize()
    self.dataSource = LibDataBroker:NewDataObject(self:GetDataObjectName(), {
        type = "data source",
        label = "BattlePets",
        icon = "Interface\\Icons\\Inv_Pet_Achievement_CaptureAWildPet",
        OnClick = function(_, button)
            self:OnClick(button)
        end,
        OnTooltipShow = function(tooltip)
            self:OnTooltipShow(tooltip, tooltip ~= LibDBIconTooltip)
        end,
        OnLeave = HideTooltip
    })
    self:RegisterEventHandlers()
end

function BrokerModule:QualityToColorCode(quality)
    if quality and quality >= 1 then
        return ITEM_QUALITY_COLORS[quality - 1].hex
    else
        return RED_FONT_COLOR_CODE
    end
end

function BrokerModule:TooltipToSourceTypeIcon(speciesId)
    local sourceType = DataModule:GetPetSource(speciesId)
    local icon
    if sourceType == BATTLE_PET_SOURCE_1 then -- Drop
        icon = "Interface/WorldMap/TreasureChest_64"
    elseif sourceType == BATTLE_PET_SOURCE_2 then -- Quest
        icon = "Interface/GossipFrame/AvailableQuestIcon"
    elseif sourceType == BATTLE_PET_SOURCE_3 then -- Vendor
        icon = "Interface/Minimap/Tracking/Banker"
    elseif sourceType == BATTLE_PET_SOURCE_4 then -- Profession
        icon = "Interface/Archeology/Arch-Icon-Marker"
    elseif sourceType == BATTLE_PET_SOURCE_5 then -- Pet Battle
        icon = "Interface/Icons/Tracking_WildPet"
    -- 6 Achievement; no icon assigned
    elseif sourceType == BATTLE_PET_SOURCE_7 then -- World Event
        icon = "Interface/GossipFrame/DailyQuestIcon"
    elseif sourceType == BATTLE_PET_SOURCE_8 then -- Promotion
        icon = "Interface/Minimap/Tracking/Banker"
    elseif sourceType == BATTLE_PET_SOURCE_9 then -- Trading Card Game
        icon = "Interface/Icons/inv_misc_hearthstonecard_legendary"
    elseif sourceType == BATTLE_PET_SOURCE_10 then -- Shop
        icon = "Interface/Icons/item_shop_giftbox01"
    elseif sourceType == BATTLE_PET_SOURCE_11 then -- Discovery
        icon = "Interface/Icons/Garrison_Building_MageTower"
    elseif sourceType == BATTLE_PET_SOURCE_12 then -- Trading Post
        icon = "Interface/Icons/TradingPostCurrency"
    else -- In case we encounter an unhandled source type
        icon = "Interface/Icons/Inv_misc_questionmark"
    end
    return icon
end

-- Also used by AddonCompartmentModule
function BrokerModule:OnTooltipShow(tooltip, includeDetails)
    tooltip:AddLine("Battle Pet Completionist")
    -- TODO: left vs. right click instructions
    tooltip:AddLine("|cffffff00Click|r to open the options dialog.")

    if not includeDetails then
        return
    end

    tooltip:AddLine(" ")
    local metGoalCount = 0
    local totalCount = 0
    local petData = self:GetZonePetData()
    -- TODO: sort
    for speciesId, _ in pairs(petData) do
        totalCount = totalCount + 1
        local numCollected, numRareCollected, limit = self:GetNumCollectedInfo(speciesId)
        local metGoal = self:MetGoal(numCollected, numRareCollected, limit)
        if metGoal then
            metGoalCount = metGoalCount + 1
        else
            local speciesName, speciesIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesId)
            local myPets = DataModule:GetOwnedPets(speciesId) or {}
            local petStrings = {}
            for _, myPetInfo in ipairs(myPets) do
                local petLevel, petQuality = myPetInfo[1], myPetInfo[2]
                table.insert(petStrings, self:QualityToColorCode(petQuality) .. "L" .. petLevel .. FONT_COLOR_CODE_CLOSE)
            end
            while #petStrings < limit do
                table.insert(petStrings, RED_FONT_COLOR_CODE .. "L0" .. FONT_COLOR_CODE_CLOSE)
            end
            local petSummary = table.concat(petStrings, "/")
            local sourceTypeIcon = self:TooltipToSourceTypeIcon(speciesId)
            local iconCode = string.format("|T%s:16:16|t|T%s:12:12:0:0|t", speciesIcon, sourceTypeIcon)
            tooltip:AddLine(string.format("%s %s %s", iconCode, speciesName, petSummary))
        end
    end
    if not petData then
        tooltip:AddLine("No pets found for current zone")
    else
        tooltip:AddLine(string.format("Met goal: %d/%d", metGoalCount, totalCount))
    end
end

-- Also used by AddonCompartmentModule
function BrokerModule:OnClick(button)
    if button == "LeftButton" then
        -- TODO: show new window
        InterfaceOptionsFrame_OpenToCategory(ConfigModule.OptionsFrame)
    elseif button == "RightButton" then
        InterfaceOptionsFrame_OpenToCategory(ConfigModule.OptionsFrame)
    end
end

function BrokerModule:MetGoal(numCollected, numRareCollected, limit)
    local goal = ConfigModule.AceDB.profile.brokerGoal
    if goal == "G1COLLECT" then
        return numCollected > 0
    elseif goal == "G2COLLECTRARE" then
        return numRareCollected > 0
    elseif goal == "G3COLLECTMAX" then
        return numCollected >= limit
    elseif goal == "G4COLLECTMAXRARE" then
        return numRareCollected >= limit
    else
        return false
    end
end

function BrokerModule:GetNumCollectedInfo(speciesId)
    local numCollected, limit = C_PetJournal.GetNumCollectedInfo(speciesId)
    local myPets = DataModule:GetOwnedPets(speciesId) or {}
    local rareQuality = 4
    local numRareCollected = 0
    for _, myPetInfo in ipairs(myPets) do
        local petQuality = myPetInfo[2]
        if petQuality >= rareQuality then
            numRareCollected = numRareCollected + 1
        end
    end
    return numCollected, numRareCollected, limit
end

function BrokerModule:RefreshData()
    local count = 0
    local totalCount = 0
    local petData = self:GetZonePetData()
    local goal = ConfigModule.AceDB.profile.brokerGoal
    local goalTextEnabled = ConfigModule.AceDB.profile.brokerGoalTextEnabled
    for speciesId, _ in pairs(petData) do
        totalCount = totalCount + 1
        if self:MetGoal(self:GetNumCollectedInfo(speciesId)) then
            count = count + 1
        end
    end
    local suffix
    if not goalTextEnabled then
        suffix = ""
    elseif goal == "G1COLLECT" then
        suffix = " Collected"
    elseif goal == "G2COLLECTRARE" then
        suffix = " Rare"
    elseif goal == "G3COLLECTMAX" then
        suffix = " Max Collected"
    elseif goal == "G4COLLECTMAXRARE" then
        suffix = " Max Rare"
    end
    self.dataSource.text = string.format("%d/%d%s", count, totalCount, suffix)
end
