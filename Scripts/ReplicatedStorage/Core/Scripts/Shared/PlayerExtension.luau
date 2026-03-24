--!strict
local PlayerExtension = {}

--获取玩家头像
function PlayerExtension.GetPlayerHeadImage(playerId: number, size: Enum.ThumbnailSize): string
	if size == Enum.ThumbnailSize.Size48x48 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 48 .. "&h=" .. 48
	elseif size == Enum.ThumbnailSize.Size60x60 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 60 .. "&h=" .. 60
	elseif size == Enum.ThumbnailSize.Size100x100 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 100 .. "&h=" .. 100
	elseif size == Enum.ThumbnailSize.Size150x150 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 150 .. "&h=" .. 150
	elseif size == Enum.ThumbnailSize.Size180x180 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 180 .. "&h=" .. 180
	elseif size == Enum.ThumbnailSize.Size352x352 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 352 .. "&h=" .. 352
	elseif size == Enum.ThumbnailSize.Size420x420 then
		return "rbxthumb://type=AvatarHeadShot&id=" .. playerId .. "&w=" .. 420 .. "&h=" .. 420
	else
		return ""
	end
end

return PlayerExtension
