local TestRunner = require("./TestRunner")

TestRunner.run({
	Categories = require("./Categories.spec"),
	LongString = require("./LongString.spec"),
	ConsoleBuffer = require("./ConsoleBuffer.spec"),
	EntryModel = require("./EntryModel.spec"),
	Markdown = require("./Markdown.spec"),
	ViewMath = require("./ViewMath.spec"),
})
