module TestPackage4
export hello4, domath4

hello4(who::String) = "Hello, $who"
domath4(x::Number) = x + 5
end
