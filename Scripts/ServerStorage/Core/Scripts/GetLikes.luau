local id = "AKfycbyXWCSxn9zfGKzWFLB6bPSaiNPX8Hqwe5eBwL5kUYZOm0zQpU8dRt-3kVw4UY9mS2oxDQ"
local url = "https://script.google.com/macros/s/" .. id .. "/exec"
local https = game:GetService('HttpService')
local GetLikes = {}

function GetLikes.GetLikeCount(universeId) : string?
	local response = https:GetAsync(url .. "?UniverseId=" .. tostring(universeId))
	response = https:JSONDecode(response)
	if response.result == "error" then
		warn("Failed to get likes!")
		return nil
	else
		local likes = response.response.response.data[1].upVotes
		return likes
	end
end

return GetLikes