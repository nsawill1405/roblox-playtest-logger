local LongString = require("../src/Logger/LongString")

return {
	["round-trips text through a comment"] = function()
		local text = "# Title\n- [ ] item"
		assert(LongString.extract(LongString.comment(text) .. "\nreturn nil\n") == text)
	end,
	["escapes closing brackets already in the text"] = function()
		local text = "a ]] b ]=] c"
		local wrapped = "return " .. LongString.literal(text)
		assert(string.find(wrapped, "[==[", 1, true))
		assert(LongString.extract(wrapped) == text)
	end,
	["returns nil without a long bracket"] = function()
		assert(LongString.extract("return 1") == nil)
	end,
}
