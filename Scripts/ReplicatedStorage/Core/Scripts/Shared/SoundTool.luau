--!strict
local SoundTool = {}

local sounds: Folder = workspace:FindFirstChild("Sounds")
local localSoundAttachmentsPool: {Attachment} = {}
local soundsPools: {[Sound]: {Sound}} = {}
local soundService: SoundService = game:FindFirstChild("SoundService")
local soundGroups: Folder = soundService:FindFirstChild("SoundGroups") :: Folder
local bgmSoundGroup: SoundGroup = soundGroups:FindFirstChild("BGM") :: SoundGroup
local soundEffectsGroup: SoundGroup = soundGroups:FindFirstChild("SoundEffects") :: SoundGroup
local localSoundsPart: Part = Instance.new("Part")
localSoundsPart.Name = "LocalSoundEffects"
localSoundsPart.Transparency = 1
localSoundsPart.CanCollide = false
localSoundsPart.CanQuery = false
localSoundsPart.CanTouch = false
localSoundsPart.Anchored = true
localSoundsPart.Position = Vector3.zero
localSoundsPart.Parent = sounds

--回收声音
local function RestoreSound(sound: Sound, soundsPool: {Sound})
	if sound.Parent ~= nil and sound.Parent:IsA("Attachment") then
		table.insert(localSoundAttachmentsPool, sound.Parent)
	end
	sound.Parent = nil
	table.insert(soundsPool, sound)
end

--获取声音
local function GetSound(soundOrigin: Sound): Sound?
	local soundsPool: {Sound}? = soundsPools[soundOrigin]
	if soundsPool == nil then
		soundsPool = {}
		if soundsPool == nil then
			return nil
		end
		soundsPools[soundOrigin] = soundsPool
		soundOrigin.Destroying:Connect(function() 
			for soundIndex: number, sound: Sound in soundsPool do
				sound:Destroy()
			end
			soundsPool = nil
			soundsPools[soundOrigin] = nil
		end)
	end
	if soundsPool == nil then
		return nil
	end
	local sound: Sound? = table.remove(soundsPool)
	if sound ~= nil then
		return sound
	end
	sound = soundOrigin:Clone()
	if sound == nil then
		return nil
	end
	sound.Ended:Connect(function(soundId: string)
		if soundsPool == nil then
			sound:Destroy()
		else
			RestoreSound(sound, soundsPool)
		end
	end)
	sound.Stopped:Connect(function(soundId: string) 
		if soundsPool == nil then
			sound:Destroy()
		else
			RestoreSound(sound, soundsPool)
		end
	end)
	return sound
end

--获取局部声音附件
local function GetLocalSoundAttachment(): Attachment?
	local attachment: Attachment? = table.remove(localSoundAttachmentsPool)
	if attachment == nil then
		attachment = Instance.new("Attachment")
		if attachment ~= nil then
			attachment.Parent = localSoundsPart
		end
	end
	return attachment
end

--播放背景音乐
function SoundTool.PlayBGM(sound: Sound)
	sound.SoundGroup = bgmSoundGroup
	sound:Play()
end

--播放一次全局音效
function SoundTool.PlayGlobalSoundEffect(soundOrigin: Sound, looped: boolean) : Sound?
	local sound: Sound? = GetSound(soundOrigin)
	if sound == nil then
		return nil
	end
	sound.SoundGroup = soundEffectsGroup
	sound.Looped = looped
	sound.Parent = sounds
	sound:Play()
	return sound
end

--播放一次局部音效
function SoundTool.PlayLocalSoundEffect(soundOrigin: Sound, soundPosition: Vector3, looped: boolean): Sound?
	local sound: Sound? = GetSound(soundOrigin)
	if sound == nil then
		return
	end
	local soundAttachment: Attachment? = GetLocalSoundAttachment()
	if soundAttachment == nil then
		return
	end
	sound.SoundGroup = soundEffectsGroup
	sound.Looped = looped
	soundAttachment.WorldCFrame = CFrame.new(soundPosition)
	sound.Parent = soundAttachment
	sound:Play()
	return sound
end

--播放指定的音效
function SoundTool.PlayDesignatedSoundEffect(sound: Sound)
	sound.SoundGroup = soundEffectsGroup
	sound:Play()
end

--停止指定的音效
function SoundTool.StopDesignatedSoundEffect(sound: Sound)
	sound:Stop()
end

--设置背景音乐音量
function SoundTool.SetBGMVolumn(volume: number)
	bgmSoundGroup.Volume = volume
end

--设置音效音量
function SoundTool.SetSoundEffectVolume(volume: number)
	soundEffectsGroup.Volume = volume
end

return SoundTool