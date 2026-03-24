--!strict
local AnimationExtension = {}

local runService: RunService = game:GetService("RunService")

type UVAnimation = {
	texture: Texture,
	animationValuesFolder: Folder,
	uSpeedValue: NumberValue,
	vSpeedValue: NumberValue,
}

type SpriteAnimation = {
	texture: Texture,
	animationValuesFolder: Folder,
	animationTime: number,
	frameRateValue: IntValue,
	frameCountValue: IntValue,
	imageColumnCountValue: IntValue,
}

type RotateAnimation = {
	instance: PVInstance,
	animationValuesFolder: Folder,
	xSpeedValue: NumberValue,
	ySpeedValue: NumberValue,
	zSpeedValue: NumberValue,
}

local uvAnimations: {UVAnimation} = {}
local spriteAnimations: {SpriteAnimation} = {}
local rotateAnimations: {RotateAnimation} = {}

--播放UV动画
function AnimationExtension.PlayUVAnimation(texture: Texture, animationValuesFolder: Folder)
	local uvAnimation: UVAnimation
	for uvAnimationTempIndex: number, uvAnimationTemp: UVAnimation in uvAnimations do
		if uvAnimationTemp.texture == texture and uvAnimationTemp.animationValuesFolder == animationValuesFolder then
			return
		end
	end
	uvAnimation = {
		texture = texture,
		animationValuesFolder = animationValuesFolder,
		uSpeedValue = animationValuesFolder:FindFirstChild("USpeed") :: NumberValue,
		vSpeedValue = animationValuesFolder:FindFirstChild("VSpeed") :: NumberValue,
	}
	table.insert(uvAnimations, uvAnimation)
	texture.Destroying:Connect(function() 
		AnimationExtension.StopUVAnimation(texture, animationValuesFolder)
	end)
end

--停止UV动画
function AnimationExtension.StopUVAnimation(texture: Texture, animationValuesFolder: Folder)
	for uvAnimationTempIndex: number, uvAnimationTemp: UVAnimation in uvAnimations do
		if uvAnimationTemp.texture == texture and uvAnimationTemp.animationValuesFolder == animationValuesFolder then
			table.remove(uvAnimations, uvAnimationTempIndex)
			break
		end
	end
end

--播放序列帧动画
function AnimationExtension.PlaySpriteAnimation(texture: Texture, animationValuesFolder: Folder)
	local spriteAnimation: SpriteAnimation
	for spriteAnimationTempIndex: number, spriteAnimationTemp: SpriteAnimation in spriteAnimations do
		if spriteAnimationTemp.texture == texture and spriteAnimationTemp.animationValuesFolder == animationValuesFolder then
			return
		end
	end
	spriteAnimation = {
		texture = texture,
		animationValuesFolder = animationValuesFolder,
		animationTime = 0,
		frameRateValue = animationValuesFolder:FindFirstChild("FrameRate") :: IntValue,
		frameCountValue = animationValuesFolder:FindFirstChild("FrameCount") :: IntValue,
		imageColumnCountValue = animationValuesFolder:FindFirstChild("ImageColumnCount") :: IntValue,
	}
	table.insert(spriteAnimations, spriteAnimation)
	texture.Destroying:Connect(function() 
		AnimationExtension.StopSpriteAnimation(texture, animationValuesFolder)
	end)
end

--停止序列帧动画
function AnimationExtension.StopSpriteAnimation(texture: Texture, animationValuesFolder: Folder)
	for spriteAnimationTempIndex: number, spriteAnimationTemp: SpriteAnimation in spriteAnimations do
		if spriteAnimationTemp.texture == texture and spriteAnimationTemp.animationValuesFolder == animationValuesFolder then
			table.remove(spriteAnimations, spriteAnimationTempIndex)
			break
		end
	end
end

--播放旋转动画
function AnimationExtension.PlayRotateAnimation(instance: PVInstance, animationValuesFolder: Folder)
	local rotateAnimation: RotateAnimation
	for rotateAnimationTempIndex: number, rotateAnimationTemp: RotateAnimation in rotateAnimations do
		if rotateAnimationTemp.instance == instance and rotateAnimationTemp.animationValuesFolder == animationValuesFolder then
			return
		end
	end
	rotateAnimation = {
		instance = instance,
		animationValuesFolder = animationValuesFolder,
		xSpeedValue = animationValuesFolder:FindFirstChild("XSpeed") :: NumberValue,
		ySpeedValue = animationValuesFolder:FindFirstChild("YSpeed") :: NumberValue,
		zSpeedValue = animationValuesFolder:FindFirstChild("ZSpeed") :: NumberValue,
	}
	table.insert(rotateAnimations, rotateAnimation)
	instance.Destroying:Connect(function() 
		AnimationExtension.StopRotateAnimation(instance, animationValuesFolder)
	end)
end

--停止旋转动画
function AnimationExtension.StopRotateAnimation(instance: PVInstance, animationValuesFolder: Folder)
	for rotateAnimationTempIndex: number, rotateAnimationTemp: RotateAnimation in rotateAnimations do
		if rotateAnimationTemp.instance == instance and rotateAnimationTemp.animationValuesFolder == animationValuesFolder then
			table.remove(rotateAnimations, rotateAnimationTempIndex)
			break
		end
	end
end

--每帧更新
local function OnRenderStepped(deltaTime: number)
	--更新UV动画
	for uvAnimationTempIndex: number, uvAnimationTemp: UVAnimation in uvAnimations do
		uvAnimationTemp.texture.OffsetStudsU += uvAnimationTemp.uSpeedValue.Value * deltaTime
		uvAnimationTemp.texture.OffsetStudsV += uvAnimationTemp.vSpeedValue.Value * deltaTime
	end
	--更新序列帧动画
	for spriteAnimationTempIndex: number, spriteAnimationTemp: SpriteAnimation in spriteAnimations do
		spriteAnimationTemp.animationTime += deltaTime
		local frameIndex: number = math.floor(spriteAnimationTemp.animationTime * spriteAnimationTemp.frameRateValue.Value) 
			% spriteAnimationTemp.frameCountValue.Value
		local lineIndex: number = math.floor(frameIndex / spriteAnimationTemp.imageColumnCountValue.Value)
		local columnIndex: number = frameIndex - lineIndex * spriteAnimationTemp.imageColumnCountValue.Value
		spriteAnimationTemp.texture.OffsetStudsU = spriteAnimationTemp.texture.StudsPerTileU 
			/ spriteAnimationTemp.imageColumnCountValue.Value * columnIndex
		spriteAnimationTemp.texture.OffsetStudsV = spriteAnimationTemp.texture.StudsPerTileV 
			/ spriteAnimationTemp.imageColumnCountValue.Value * lineIndex
	end
	--更新旋转动画
	for rotateAnimationTempIndex: number, rotateAnimationTemp: RotateAnimation in rotateAnimations do
		local rotateX: number = math.rad(rotateAnimationTemp.xSpeedValue.Value) * deltaTime
		local rotateY: number = math.rad(rotateAnimationTemp.ySpeedValue.Value) * deltaTime
		local rotateZ: number = math.rad(rotateAnimationTemp.zSpeedValue.Value) * deltaTime
		rotateAnimationTemp.instance:PivotTo(rotateAnimationTemp.instance:GetPivot() * CFrame.Angles(rotateX, rotateY, rotateZ))
	end
end

runService:BindToRenderStep(string.format("%s.RenderStepped", script.Name), Enum.RenderPriority.Camera.Value + 1, OnRenderStepped)

return AnimationExtension
