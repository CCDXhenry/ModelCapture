--!strict
local UserInutExtension = {}

local userInputService: UserInputService = game:GetService("UserInputService")

--输入类型
UserInutExtension.InputTypeString = {
	Keyboard_Mouse = "Keyboard_Mouse", --键盘和鼠标
	Touch = "Touch", --触摸屏
	Gamepad = "Gamepad", --手柄
}

local inputTypeString: string
if userInputService.KeyboardEnabled and userInputService.MouseEnabled then
	inputTypeString = UserInutExtension.InputTypeString.Keyboard_Mouse
elseif userInputService.TouchEnabled then
	inputTypeString = UserInutExtension.InputTypeString.Touch
elseif userInputService.GamepadEnabled then
	inputTypeString = UserInutExtension.InputTypeString.Gamepad
end

function UserInutExtension.GetInputType(): (string?, Enum.UserInputType)
	local lastInputEnum = userInputService:GetLastInputType()
	if lastInputEnum == Enum.UserInputType.Keyboard 
		or string.find(tostring(lastInputEnum.Name), "MouseButton") 
		or lastInputEnum == Enum.UserInputType.MouseWheel then
		inputTypeString = UserInutExtension.InputTypeString.Keyboard_Mouse
	elseif lastInputEnum == Enum.UserInputType.Touch then
		inputTypeString = UserInutExtension.InputTypeString.Touch
	elseif string.find(tostring(lastInputEnum.Name), "Gamepad") then
		inputTypeString = UserInutExtension.InputTypeString.Gamepad
	end
	return inputTypeString, lastInputEnum
end

return UserInutExtension