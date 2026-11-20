-- Pure camera/layout math, kept free of Roblox datatypes so it can be unit tested.
local ViewMath = {}

-- Ray direction through a normalized screen point (0..1 from the top-left), expressed as
-- coefficients of the camera's Right, Up and Look vectors.
function ViewMath.rayCoefficients(fovDegrees: number, aspect: number, nx: number, ny: number): (number, number, number)
	local t = math.tan(math.rad(fovDegrees) / 2)
	local ndcX = nx * 2 - 1
	local ndcY = 1 - ny * 2
	return ndcX * t * aspect, ndcY * t, 1
end

-- Largest rect with the given aspect ratio that fits inside a container, centered.
function ViewMath.fit(containerW: number, containerH: number, aspect: number): (number, number, number, number)
	if containerW <= 0 or containerH <= 0 or aspect <= 0 then
		return 0, 0, 0, 0
	end
	local w = containerW
	local h = w / aspect
	if h > containerH then
		h = containerH
		w = h * aspect
	end
	return w, h, (containerW - w) / 2, (containerH - h) / 2
end

function ViewMath.toNormalized(
	px: number,
	py: number,
	rectX: number,
	rectY: number,
	rectW: number,
	rectH: number
): (number, number)
	if rectW <= 0 or rectH <= 0 then
		return 0.5, 0.5
	end
	return math.clamp((px - rectX) / rectW, 0, 1), math.clamp((py - rectY) / rectH, 0, 1)
end

-- Picks a downscaled capture size that keeps the aspect ratio and fits within maxW x maxH.
function ViewMath.scaledSize(w: number, h: number, maxW: number, maxH: number): (number, number)
	local scale = math.min(1, maxW / w, maxH / h)
	return math.max(1, math.floor(w * scale + 0.5)), math.max(1, math.floor(h * scale + 0.5))
end

return ViewMath
