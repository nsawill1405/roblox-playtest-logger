local ViewMath = require("../src/Logger/ViewMath")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["center of the screen looks straight ahead"] = function()
		local r, u, f = ViewMath.rayCoefficients(70, 16 / 9, 0.5, 0.5)
		assert(near(r, 0) and near(u, 0) and f == 1)
	end,
	["corners follow the field of view"] = function()
		local t = math.tan(math.rad(90) / 2)
		local r, u = ViewMath.rayCoefficients(90, 2, 0, 0)
		assert(near(r, -t * 2) and near(u, t))
		local r2, u2 = ViewMath.rayCoefficients(90, 2, 1, 1)
		assert(near(r2, t * 2) and near(u2, -t))
	end,
	["fits rects inside containers"] = function()
		local w, h, x, y = ViewMath.fit(400, 400, 2)
		assert(w == 400 and h == 200 and x == 0 and y == 100)
		local w2, h2, x2 = ViewMath.fit(400, 100, 2)
		assert(w2 == 200 and h2 == 100 and x2 == 100)
	end,
	["normalizes and clamps points"] = function()
		local nx, ny = ViewMath.toNormalized(150, 75, 100, 50, 100, 50)
		assert(nx == 0.5 and ny == 0.5)
		local cx, cy = ViewMath.toNormalized(-10, 999, 0, 0, 100, 100)
		assert(cx == 0 and cy == 1)
	end,
	["downscales captures"] = function()
		local w, h = ViewMath.scaledSize(1920, 1080, 640, 360)
		assert(w == 640 and h == 360)
		local w2, h2 = ViewMath.scaledSize(300, 200, 640, 360)
		assert(w2 == 300 and h2 == 200)
	end,
}
