local TestRunner = {}

function TestRunner.run(suites)
	local passed = 0
	local failed = 0

	for suiteName, suite in suites do
		for testName, test in suite do
			local ok, err = pcall(test)
			if ok then
				passed += 1
			else
				failed += 1
				print(`FAIL {suiteName}: {testName}\n  {err}`)
			end
		end
	end

	if failed > 0 then
		error(`{failed} test(s) failed; {passed} passed`, 0)
	end

	print(`PASS {passed} test(s)`)
end

return TestRunner
