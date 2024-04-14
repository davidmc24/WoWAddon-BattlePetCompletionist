BattlePetCompletionist = LibStub("AceAddon-3.0"):GetAddon("BattlePetCompletionist")
BrokerModule = BattlePetCompletionist:GetModule("BrokerModule")

function BattlePetCompletionist_OnAddonCompartmentClick(addonName, button)
    BrokerModule:OnClick(button)
end

function BattlePetCompletionist_OnAddonCompartmentEnter(addonName, button)
    GameTooltip:SetOwner(AddonCompartmentFrame)
    BrokerModule:OnTooltipShow(GameTooltip)
    GameTooltip:Show()
end

function BattlePetCompletionist_OnAddonCompartmentLeave(addonName, button)
    GameTooltip:Hide()
end
