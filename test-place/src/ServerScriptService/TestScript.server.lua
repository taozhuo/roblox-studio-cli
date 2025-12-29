-- Test script to verify studioctl log streaming
print("=== Test Script Started ===")

local count = 0
while true do
	count = count + 1
	print("Server tick #" .. count)

	if count % 5 == 0 then
		warn("Warning at tick " .. count)
	end

	task.wait(1)
end
