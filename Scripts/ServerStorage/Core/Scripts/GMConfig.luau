--!strict
local GMConfig = {}

local GMPlayerIds: {number} = {
	5508225687, --Sixcube
	4104055632, --庄小君
	6011063954, --庄小君2
	5440463669, --陈夏凌
	5488867237, --付雯
	5645420758, --郑金彬
	5511419798, --周洁1
	5864346636, --周洁2
	5511334360, --绣绣
	6009425878, --景然
	4809020050, --文龙
	9377209598, --贺熔
}

--是否是GM
function GMConfig.IsGMPlayer(playerId: number): boolean
	return table.find(GMPlayerIds, playerId) ~= nil
end

--获取GM玩家id列表
function GMConfig.GetGMPlayerIdList(): {number}
	return GMPlayerIds
end

return GMConfig
