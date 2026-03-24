--!strict
local TranslationTool = {}

local replicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local core = replicatedStorage:WaitForChild("Core")
local coreScripts = core:WaitForChild("Scripts")
local coreSharedScripts = coreScripts:WaitForChild("Shared")
local RetryAsync = require(coreSharedScripts:FindFirstChild("RetryAsync"))
local localizationService: LocalizationService = game:GetService("LocalizationService")
local players: Players = game:GetService("Players")

local AttemptLimit: number = 5
local RetryDelay: number = 1

type LocalizeGui = TextLabel | TextButton | ProximityPrompt

type CustomAutoLocalizeGui = {
	source: string,
	key: string?,
	args: {string}?,
	source2: string?,
	key2: string?,
	args2: {string}?
}

assert(players.LocalPlayer)

local customAutoLocalizeGuis: {[LocalizeGui]: CustomAutoLocalizeGui} = {}
local playerTranslator: Translator?

local function RefreshCustomAutoLocalizeGui(guiInstance: LocalizeGui, customAutoLocalizeGui: CustomAutoLocalizeGui)
	local text: string
	if customAutoLocalizeGui.key == nil or customAutoLocalizeGui.key == "" or customAutoLocalizeGui.args == nil then
		text = TranslationTool.Translate(guiInstance, customAutoLocalizeGui.source)
	else
		text = TranslationTool.FormatByKey(customAutoLocalizeGui.source, customAutoLocalizeGui.key, customAutoLocalizeGui.args)
	end
	local text2: string
	if customAutoLocalizeGui.source2 ~= nil then
		if customAutoLocalizeGui.key2 == nil or customAutoLocalizeGui.key2 == "" or customAutoLocalizeGui.args2 == nil then
			text2 = TranslationTool.Translate(guiInstance, customAutoLocalizeGui.source2)
		else
			text2 = TranslationTool.FormatByKey(customAutoLocalizeGui.source2, customAutoLocalizeGui.key2, customAutoLocalizeGui.args2)
		end
	end
	if guiInstance:IsA("TextLabel") then
		guiInstance.Text = text
	elseif guiInstance:IsA("TextButton") then
		guiInstance.Text = text
	elseif guiInstance:IsA("ProximityPrompt") then
		guiInstance.ActionText = text
		if text2 ~= nil then
			guiInstance.ObjectText = text2
		end
	end
end

--自定义自动翻译Gui
local function CustomAutoLocalizeGui(guiInstance: LocalizeGui, source: string, key: string?, args: {string}?,
	source2: string?, key2: string?, args2: {string}?)
	local customAutoLocalizeGui: CustomAutoLocalizeGui = customAutoLocalizeGuis[guiInstance]
	if customAutoLocalizeGui == nil then
		customAutoLocalizeGui = {
			key = key,
			source = source,
			args = args,
			key2 = key2,
			source2 = source2,
			args2 = args2,
		}
		customAutoLocalizeGuis[guiInstance] = customAutoLocalizeGui
		guiInstance.Destroying:Connect(function()
			customAutoLocalizeGuis[guiInstance] = nil
		end)
	else
		customAutoLocalizeGui.key = key
		customAutoLocalizeGui.source = source
		customAutoLocalizeGui.args = args
		customAutoLocalizeGui.key2 = key2
		customAutoLocalizeGui.source2 = source2
		customAutoLocalizeGui.args2 = args2
	end
	RefreshCustomAutoLocalizeGui(guiInstance, customAutoLocalizeGui)
end

--根据原文内容翻译
function TranslationTool.Translate(context: Instance, text: string): string
	if playerTranslator == nil then
		return text
	end
	return playerTranslator:Translate(context, text)
end

--根据原文Key和参数翻译
function TranslationTool.FormatByKey(source: string, key: string, args: {string}): string
	if playerTranslator ~= nil then
		local success: boolean, result: string = pcall(function()
			return playerTranslator:FormatByKey(key, args)
		end)
		if success then
			return result
		end
	end
	source = source:gsub("{(%d+).-}", function(indexText: string)
		local index: number? = tonumber(indexText)
		if index == nil then
			return indexText
		else
			return args[index]
		end
	end)
	return source
end

--自定义自动翻译文本标签
function TranslationTool.CustomAutoLocalizeTextLabel(textLabel: TextLabel, textSource: string, textKey: string?, textArgs: {string}?)
	CustomAutoLocalizeGui(textLabel, textSource, textKey, textArgs)
end

--自定义自动翻译文本按钮
function TranslationTool.CustomAutoLocalizeTextButton(textButton: TextButton, textSource: string, textKey: string?, textArgs: {string}?)
	CustomAutoLocalizeGui(textButton, textSource, textKey, textArgs)
end

--自定义自动翻译接近提示
function TranslationTool.CustomAutoLocalizeProximityPrompt(proximityPrompt: ProximityPrompt, actionTextSource: string, 
	actionTextKey: string?, actionTextArgs: {string}?, objectTextSource: string?, objectTextKey: string?, objectArgs: {string}?)
	CustomAutoLocalizeGui(proximityPrompt, actionTextSource, actionTextKey, actionTextArgs,
		objectTextSource, objectTextKey, objectArgs)
end

--移除自定义自动翻译Gui
function TranslationTool.RemoveCustomAutoLocalizeGui(gui: LocalizeGui)
	customAutoLocalizeGuis[gui] = nil
end

local getTranslatorThread: thread = coroutine.create(function()
	local success: boolean, result: any = RetryAsync(function()
		return localizationService:GetTranslatorForPlayerAsync(players.LocalPlayer)
	end, AttemptLimit, RetryDelay)
	if success then
		playerTranslator = result
		if playerTranslator == nil then
			return
		end
		for guiInstance: LocalizeGui, customAutoLocalizeGui: CustomAutoLocalizeGui in customAutoLocalizeGuis do
			RefreshCustomAutoLocalizeGui(guiInstance, customAutoLocalizeGui)
		end
		playerTranslator:GetPropertyChangedSignal("LocaleId"): Connect(function()
			for guiInstance: LocalizeGui, customAutoLocalizeGui: CustomAutoLocalizeGui in customAutoLocalizeGuis do
				RefreshCustomAutoLocalizeGui(guiInstance, customAutoLocalizeGui)
			end
		end)
	end
end)
coroutine.resume(getTranslatorThread)

return TranslationTool